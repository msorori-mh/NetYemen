/**
 * NetYemen V1 External Pilot Binding — Notification Transport Adapter Edge Function
 *
 * Roles:
 *   A. FCM push transport adapter (OD-NOTIF-01)
 *   B. Card crypto operations: AES-256-GCM decrypt (OD-CARD-01)
 *
 * Environment variables required for production physical pilot:
 *   - SUPABASE_URL                      (auto-provided by Supabase)
 *   - SUPABASE_SERVICE_ROLE_KEY         (auto-provided by Supabase)
 *   - FCM_PROJECT_ID                    (Firebase project ID)
 *   - FCM_CLIENT_EMAIL                  (FCM service account client email)
 *   - FCM_PRIVATE_KEY                   (FCM service account PEM private key)
 *   - CARD_MASTER_KEY_v1                (Base64-encoded 32-byte AES-256 key)
 *
 * For local/source-only builds, FCM credentials may be omitted; the function
 * returns `credential_required` and does NOT fake success. CARD_MASTER_KEY_v1
 * may be omitted for local tests, in which case a deterministic TEST_ONLY key
 * is derived and a loud warning is logged.
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.38.0";
import { aes256GcmDecrypt, CardKeyVersion, getCardMasterKey } from "./crypto.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface DispatchPushPayload {
  action: "dispatch_push";
  delivery_id: string;
  user_id: string;
  token: string;
  title_ar: string;
  body_ar: string;
  deep_link?: string;
  event_id?: string;
}

interface DecryptCardSecretPayload {
  action: "decrypt_card_secret";
  key_version: CardKeyVersion;
  ciphertext_b64: string;
  nonce: string;
  auth_tag_b64: string;
}

interface RevealCardSecretPayload {
  action: "reveal_card_secret";
  purchase_id: string;
}

type RequestPayload =
  | DispatchPushPayload
  | DecryptCardSecretPayload
  | RevealCardSecretPayload;

interface FcmCredentials {
  projectId: string;
  clientEmail: string;
  privateKey: CryptoKey;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405);
  }

  let body: RequestPayload;
  try {
    body = await req.json();
  } catch (e) {
    return jsonResponse({ error: "INVALID_JSON", message: e.message }, 400);
  }

  // Sensitive actions are restricted to server-side/service-role callers.
  // Anon or customer JWTs must never be able to dispatch pushes or decrypt
  // card secrets generically.
  if (body.action === "dispatch_push" || body.action === "decrypt_card_secret") {
    const authError = requireInternalAuth(req);
    if (authError) return authError;
  }

  try {
    switch (body.action) {
      case "dispatch_push":
        return await handleDispatchPush(body);
      case "decrypt_card_secret":
        return await handleDecryptCardSecret(body);
      case "reveal_card_secret":
        return await handleCustomerCardReveal(req, body);
      default:
        return jsonResponse({ error: "UNKNOWN_ACTION" }, 400);
    }
  } catch (e) {
    console.error("Unhandled error in notification-transport-adapter:", e);
    return jsonResponse({ error: "INTERNAL_ERROR", message: e.message }, 500);
  }
});

/**
 * Verifies that the request carries the service-role key (or a dedicated
 * internal function secret). This prevents anon/customer JWTs from reaching
 * dispatch_push / decrypt_card_secret.
 */
function requireInternalAuth(req: Request): Response | null {
  const authHeader = req.headers.get("authorization") || "";
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    console.error("Authorization missing for sensitive action");
    return jsonResponse({ error: "UNAUTHORIZED", status: "forbidden" }, 401);
  }

  const token = match[1];
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const internalSecret = Deno.env.get("INTERNAL_FUNCTION_SECRET");

  const isServiceRole = serviceRoleKey && token === serviceRoleKey;
  const isInternalSecret = internalSecret && token === internalSecret;

  if (!isServiceRole && !isInternalSecret) {
    console.error("Authorization rejected for sensitive action");
    return jsonResponse({ error: "FORBIDDEN", status: "forbidden" }, 403);
  }

  return null;
}

async function handleDispatchPush(payload: DispatchPushPayload): Promise<Response> {
  const projectId = Deno.env.get("FCM_PROJECT_ID");
  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
  const privateKeyPem = Deno.env.get("FCM_PRIVATE_KEY");

  if (!projectId || !clientEmail || !privateKeyPem) {
    await recordDeliveryResponse(payload.delivery_id, "failed", null, "credential_required");
    return jsonResponse({ accepted: false, status: "credential_required" }, 200);
  }

  let credentials: FcmCredentials;
  try {
    credentials = {
      projectId,
      clientEmail,
      privateKey: await importFcmPrivateKey(privateKeyPem),
    };
  } catch (e) {
    console.error("Failed to import FCM private key:", e);
    await recordDeliveryResponse(payload.delivery_id, "failed", null, "credential_required");
    return jsonResponse(
      { accepted: false, status: "credential_required", error: "Invalid FCM private key" },
      200,
    );
  }

  let accessToken: string;
  try {
    accessToken = await getFcmAccessToken(credentials);
  } catch (e) {
    console.error("FCM OAuth token exchange failed:", e);
    await recordDeliveryResponse(payload.delivery_id, "failed", null, "transient_failure");
    return jsonResponse(
      { accepted: false, status: "transient_failure", error: e.message },
      502,
    );
  }

  try {
    const result = await sendFcmMessage(credentials, accessToken, payload);
    await recordDeliveryResponse(payload.delivery_id, "sent", result.name);
    return jsonResponse(
      { accepted: true, status: "sent", provider_message_id: result.name },
      200,
    );
  } catch (e: any) {
    console.error("FCM send failed:", e);
    if (e.isPermanent) {
      await deactivatePushToken(payload.user_id, payload.token);
      await recordDeliveryResponse(payload.delivery_id, "failed", null, "permanent_failure");
      return jsonResponse(
        { accepted: false, status: "permanent_failure", error: e.message },
        200,
      );
    } else {
      await recordDeliveryResponse(payload.delivery_id, "failed", null, "transient_failure");
      return jsonResponse(
        { accepted: false, status: "transient_failure", error: e.message },
        502,
      );
    }
  }
}

async function handleDecryptCardSecret(payload: DecryptCardSecretPayload): Promise<Response> {
  try {
    const key = await getCardMasterKey(payload.key_version);
    const plaintext = await aes256GcmDecrypt(
      key,
      payload.ciphertext_b64,
      payload.nonce,
      payload.auth_tag_b64,
    );
    // Plaintext is never logged.
    return jsonResponse({ plaintext }, 200);
  } catch (e) {
    console.error("Card secret decryption failed:", e.message);
    return jsonResponse({ error: "DECRYPTION_FAILED", status: "forbidden" }, 400);
  }
}

async function handleCustomerCardReveal(
  req: Request,
  payload: RevealCardSecretPayload,
): Promise<Response> {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    payload.purchase_id || "",
  )) {
    return jsonResponse({ error: "INVALID_PURCHASE_ID" }, 400);
  }

  const authHeader = req.headers.get("authorization") || "";
  if (!/^Bearer\s+.+/i.test(authHeader)) {
    return jsonResponse({ error: "UNAUTHORIZED", status: "forbidden" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anonKey) {
    console.error("Customer card reveal configuration is incomplete");
    return jsonResponse({ error: "REVEAL_SERVICE_UNAVAILABLE" }, 503);
  }

  const customerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await customerClient.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "UNAUTHORIZED", status: "forbidden" }, 401);
  }

  let revealKey: CryptoKey;
  try {
    revealKey = await getCardMasterKey("v1");
  } catch (error) {
    console.error(
      "Customer card reveal key is unavailable",
      error instanceof Error ? error.message : "unknown",
    );
    return jsonResponse({ error: "REVEAL_SERVICE_UNAVAILABLE" }, 503);
  }

  // Resolve and audit the encrypted payload through the caller's JWT. The RPC
  // enforces purchase ownership and never accepts ciphertext from the client.
  const { data: encryptedData, error: revealError } = await customerClient.rpc(
    "reveal_purchase_card_secret",
    { p_purchase_id: payload.purchase_id },
  );
  if (revealError || !encryptedData) {
    console.error("Customer card reveal RPC rejected", revealError?.code || "unknown");
    return jsonResponse({ error: "CARD_REVEAL_DENIED" }, 403);
  }

  const encrypted = encryptedData as Record<string, unknown>;
  const keyVersion = encrypted.key_version;
  const ciphertextB64 = encrypted.ciphertext_b64;
  const nonce = encrypted.nonce;
  const authTagB64 = encrypted.auth_tag_b64;
  if (
    keyVersion !== "v1" ||
    typeof ciphertextB64 !== "string" ||
    typeof nonce !== "string" ||
    typeof authTagB64 !== "string" ||
    !ciphertextB64 ||
    !nonce ||
    !authTagB64
  ) {
    console.error("Customer card reveal payload is incomplete");
    return jsonResponse({ error: "CARD_SECRET_UNAVAILABLE" }, 409);
  }

  let plaintext: string;
  try {
    plaintext = await aes256GcmDecrypt(
      revealKey,
      ciphertextB64,
      nonce,
      authTagB64,
    );
  } catch (error) {
    console.error(
      "Customer card reveal decryption failed",
      error instanceof Error ? error.message : "unknown",
    );
    return jsonResponse({ error: "CARD_DECRYPTION_FAILED" }, 409);
  }
  if (!plaintext.trim()) {
    return jsonResponse({ error: "CARD_SECRET_EMPTY" }, 409);
  }

  const { data: fulfillment, error: fulfillmentError } = await customerClient
    .from("card_fulfillment_records")
    .select("dispute_window_ends_at")
    .eq("purchase_id", payload.purchase_id)
    .maybeSingle();
  if (fulfillmentError) {
    console.error("Customer reveal deadline lookup failed", fulfillmentError.code);
  }

  return jsonResponse(
    {
      purchase_id: payload.purchase_id,
      status: "revealed",
      plaintext,
      revealed_at: new Date().toISOString(),
      dispute_deadline: fulfillment?.dispute_window_ends_at || null,
    },
    200,
  );
}

async function sendFcmMessage(
  credentials: FcmCredentials,
  accessToken: string,
  payload: DispatchPushPayload,
): Promise<{ name: string }> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${credentials.projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: payload.token,
          notification: {
            title: payload.title_ar,
            body: payload.body_ar,
          },
          android: {
            notification: {
              channel_id: "default",
              sound: "default",
            },
          },
          data: {
            deep_link: payload.deep_link || "",
            event_id: payload.event_id || "",
          },
        },
      }),
    },
  );

  const responseText = await response.text();
  let responseJson: Record<string, unknown> = {};
  try {
    responseJson = JSON.parse(responseText);
  } catch {
    // FCM may occasionally return non-JSON errors.
  }

  if (response.ok) {
    return { name: String(responseJson.name || "") };
  }

  const errorMessage =
    (responseJson.error as { message?: string })?.message || responseText || `HTTP ${response.status}`;
  const error = new Error(errorMessage);
  (error as any).status = response.status;
  // 4xx client errors are permanent for this token; 5xx and network errors are transient.
  (error as any).isPermanent = response.status >= 400 && response.status < 500;
  throw error;
}

async function getFcmAccessToken(credentials: FcmCredentials): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const jwt = await signJwt(
    { alg: "RS256", typ: "JWT" },
    {
      iss: credentials.clientEmail,
      sub: credentials.clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    },
    credentials.privateKey,
  );

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    throw new Error(`OAuth token exchange failed: ${response.status} ${await response.text()}`);
  }

  const data = await response.json();
  if (!data.access_token) {
    throw new Error("OAuth response did not contain access_token");
  }
  return data.access_token;
}

async function signJwt(
  header: object,
  payload: object,
  privateKey: CryptoKey,
): Promise<string> {
  const encodedHeader = base64url(JSON.stringify(header));
  const encodedPayload = base64url(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    new TextEncoder().encode(signingInput),
  );
  const encodedSignature = base64url(String.fromCharCode(...new Uint8Array(signature)));
  return `${signingInput}.${encodedSignature}`;
}

async function importFcmPrivateKey(pem: string): Promise<CryptoKey> {
  const pkcs8 = pemToArrayBuffer(pem);
  return crypto.subtle.importKey(
    "pkcs8",
    pkcs8,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN (RSA )?PRIVATE KEY-----/g, "")
    .replace(/-----END (RSA )?PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function base64url(source: string): string {
  return btoa(source).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function recordDeliveryResponse(
  deliveryId: string,
  status: "sent" | "failed",
  providerMessageId: string | null,
  skipReason?: string | null,
): Promise<void> {
  try {
    const supabase = getSupabaseServiceClient();

    const { data: delivery, error: fetchError } = await supabase
      .from("notification_deliveries")
      .select("attempt_count")
      .eq("id", deliveryId)
      .single();

    if (fetchError) {
      console.error("Failed to fetch delivery attempt_count:", fetchError);
    }

    const now = new Date().toISOString();
    const update: Record<string, unknown> = {
      status,
      provider_message_id: providerMessageId,
      attempt_count: (delivery?.attempt_count ?? 0) + 1,
      last_attempt_at: now,
      updated_at: now,
    };

    if (status === "sent") {
      update.delivered_at = now;
    }

    if (skipReason) {
      update.skip_reason = skipReason;
    }

    const { error: updateError } = await supabase
      .from("notification_deliveries")
      .update(update)
      .eq("id", deliveryId);

    if (updateError) {
      console.error("Failed to record delivery response:", updateError);
    }
  } catch (e) {
    console.error("Failed to record delivery response:", e);
  }
}

async function deactivatePushToken(userId: string, token: string): Promise<void> {
  try {
    const supabase = getSupabaseServiceClient();
    const { error } = await supabase
      .from("device_push_tokens")
      .update({ is_active: false, updated_at: new Date().toISOString() })
      .eq("user_id", userId)
      .eq("token", token);

    if (error) {
      console.error("Failed to deactivate push token:", error);
    }
  } catch (e) {
    console.error("Failed to deactivate push token:", e);
  }
}

function getSupabaseServiceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set");
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function jsonResponse(body: object, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
