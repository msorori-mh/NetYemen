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
 * Optional:
 *   - INTERNAL_FUNCTION_SECRET          (dedicated bearer secret for internal actions)
 *   - ALLOWED_ORIGINS                   (comma-separated browser origins; when set,
 *                                        CORS is restricted to exactly these origins)
 *
 * For local/source-only builds, FCM credentials may be omitted; the function
 * returns `credential_required` and does NOT fake success. CARD_MASTER_KEY_v1
 * has no production fallback: the deterministic TEST_ONLY key is available only
 * to local tests under the conditions enforced in crypto.ts.
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.38.0";
import { aes256GcmDecrypt, CardKeyVersion, getCardMasterKey } from "./crypto.ts";
import { extractRevealedCardPin } from "./reveal.ts";

// CORS is limited to the single method and the request headers that
// supabase-js / supabase_flutter actually send to an Edge Function.
const CORS_ALLOW_HEADERS = "authorization, x-client-info, apikey, content-type";
const CORS_ALLOW_METHODS = "POST, OPTIONS";

/**
 * Returns the CORS headers for this request, or null when the request comes
 * from a browser origin that is not allowed.
 *
 * - ALLOWED_ORIGINS unset/empty: unchanged legacy behaviour (`*`). Every action
 *   still requires a bearer credential, and no cookies are used.
 * - ALLOWED_ORIGINS set: only the listed origins are echoed back. A request
 *   that carries any other Origin is refused. Requests without an Origin
 *   header (mobile apps, server-to-server) are not browser requests and are
 *   unaffected.
 */
function resolveCors(req: Request): Record<string, string> | null {
  const allowedOrigins = (Deno.env.get("ALLOWED_ORIGINS") || "")
    .split(",")
    .map((origin) => origin.trim().replace(/\/+$/, ""))
    .filter(Boolean);
  const base: Record<string, string> = {
    "Access-Control-Allow-Headers": CORS_ALLOW_HEADERS,
    "Access-Control-Allow-Methods": CORS_ALLOW_METHODS,
  };
  if (allowedOrigins.length === 0) {
    return { ...base, "Access-Control-Allow-Origin": "*" };
  }
  const origin = req.headers.get("origin");
  if (origin === null) return { ...base, "Vary": "Origin" };
  if (!allowedOrigins.includes(origin)) return null;
  return { ...base, "Access-Control-Allow-Origin": origin, "Vary": "Origin" };
}

function withCors(response: Response, cors: Record<string, string>): Response {
  for (const [name, value] of Object.entries(cors)) {
    response.headers.set(name, value);
  }
  return response;
}

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
  const cors = resolveCors(req);
  if (cors === null) {
    return jsonResponse({ error: "ORIGIN_NOT_ALLOWED" }, 403);
  }
  if (req.method === "OPTIONS") {
    return withCors(new Response("ok"), cors);
  }
  return withCors(await handleRequest(req), cors);
});

async function handleRequest(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405);
  }

  let body: RequestPayload;
  try {
    body = await req.json();
  } catch (_) {
    return jsonResponse({ error: "INVALID_JSON" }, 400);
  }

  // Sensitive actions are restricted to server-side/service-role callers.
  // Anon or customer JWTs must never be able to dispatch pushes or decrypt
  // card secrets generically.
  if (body.action === "dispatch_push" || body.action === "decrypt_card_secret") {
    const authError = await requireInternalAuth(req);
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
    return jsonResponse({ error: "INTERNAL_ERROR" }, 500);
  }
}

/**
 * Verifies that the request carries the service-role key (or a dedicated
 * internal function secret). This prevents anon/customer JWTs from reaching
 * dispatch_push / decrypt_card_secret.
 */
async function requireInternalAuth(req: Request): Promise<Response | null> {
  const authHeader = req.headers.get("authorization") || "";
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    console.error("Authorization missing for sensitive action");
    return jsonResponse({ error: "UNAUTHORIZED", status: "forbidden" }, 401);
  }

  const token = match[1];
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const internalSecret = Deno.env.get("INTERNAL_FUNCTION_SECRET");

  // Constant-time comparison (both sides hashed first): `===` on secrets leaks
  // the length of the matching prefix through response timing. Both candidates
  // are always evaluated so the timing does not reveal which one is configured.
  const isServiceRole = await secretMatches(token, serviceRoleKey);
  const isInternalSecret = await secretMatches(token, internalSecret);

  if (!isServiceRole && !isInternalSecret) {
    console.error("Authorization rejected for sensitive action");
    return jsonResponse({ error: "FORBIDDEN", status: "forbidden" }, 403);
  }

  return null;
}

async function secretMatches(supplied: string, expected: string | undefined): Promise<boolean> {
  // Always run the comparison, even when the secret is not configured.
  const matches = await constantTimeEqual(supplied, expected || "");
  return Boolean(expected) && matches;
}

async function constantTimeEqual(left: string, right: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [leftHash, rightHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  const a = new Uint8Array(leftHash);
  const b = new Uint8Array(rightHash);
  let difference = 0;
  for (let index = 0; index < a.length; index++) difference |= a[index] ^ b[index];
  return difference === 0;
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
      { accepted: false, status: "transient_failure", error: errorMessage(e) },
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
  } catch (e) {
    const failure = e instanceof FcmSendError ? e.failure : "transient";
    const message = errorMessage(e);
    console.error("FCM send failed:", { failure, message });

    if (failure === "token_invalid") {
      // The ONLY case in which the device token is deactivated: FCM stated that
      // this specific token is unregistered or malformed.
      await deactivatePushToken(payload.user_id, payload.token);
      await recordDeliveryResponse(payload.delivery_id, "failed", null, "permanent_failure");
      return jsonResponse(
        { accepted: false, status: "permanent_failure", error: message },
        200,
      );
    }
    if (failure === "message_rejected") {
      // FCM rejected this message (payload problem), not the token. Do not
      // retry this delivery and do not touch the token.
      await recordDeliveryResponse(payload.delivery_id, "failed", null, "permanent_failure");
      return jsonResponse(
        { accepted: false, status: "permanent_failure", token_deactivated: false, error: message },
        200,
      );
    }
    if (failure === "configuration") {
      // 401/403: our credentials, project or sender are wrong. Every token
      // would fail the same way, so the caller must stop the batch. Tokens stay
      // active: deactivating them here would silently unsubscribe every user.
      await recordDeliveryResponse(payload.delivery_id, "failed", null, "configuration_error");
      return jsonResponse(
        { accepted: false, status: "configuration_error", retryable: false, error: message },
        503,
      );
    }
    // 429 quota, 5xx and network errors: retry later, token stays active.
    await recordDeliveryResponse(payload.delivery_id, "failed", null, "transient_failure");
    return jsonResponse(
      { accepted: false, status: "transient_failure", retryable: true, error: message },
      502,
    );
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
    console.error("Card secret decryption failed:", errorMessage(e));
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

  // The RPC enforces purchase ownership, audits the reveal and decrypts the
  // card inside Postgres (pgcrypto). It returns the PIN as `card_pin`.
  const { data: revealData, error: revealError } = await customerClient.rpc(
    "reveal_purchase_card_secret",
    { p_purchase_id: payload.purchase_id },
  );
  if (revealError || !revealData) {
    console.error("Customer card reveal RPC rejected", revealError?.code || "unknown");
    return jsonResponse({ error: "CARD_REVEAL_DENIED" }, 403);
  }

  const plaintext = extractRevealedCardPin(revealData);
  if (!plaintext) {
    console.error("Customer card reveal payload is incomplete");
    return jsonResponse({ error: "CARD_SECRET_UNAVAILABLE" }, 409);
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

  const fcmError = (responseJson.error ?? {}) as FcmErrorBody;
  const message = fcmError.message || responseText || `HTTP ${response.status}`;
  throw new FcmSendError(message, response.status, classifyFcmFailure(response.status, fcmError));
}

type FcmFailure = "token_invalid" | "message_rejected" | "configuration" | "transient";

interface FcmErrorBody {
  message?: string;
  status?: string;
  details?: Array<{
    "@type"?: string;
    errorCode?: string;
    fieldViolations?: Array<{ field?: string; description?: string }>;
  }>;
}

class FcmSendError extends Error {
  readonly status: number;
  readonly failure: FcmFailure;

  constructor(message: string, status: number, failure: FcmFailure) {
    super(message);
    this.name = "FcmSendError";
    this.status = status;
    this.failure = failure;
  }
}

/**
 * Maps an FCM HTTP v1 error to what the caller may do about it.
 * https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode
 *
 *   UNREGISTERED / HTTP 404          -> token_invalid   (deactivate the token)
 *   INVALID_ARGUMENT about the token -> token_invalid   (deactivate the token)
 *   other INVALID_ARGUMENT / 4xx     -> message_rejected (keep the token)
 *   HTTP 401 / 403                   -> configuration   (fail the batch, keep tokens)
 *   HTTP 429 / 5xx                   -> transient       (retry, keep tokens)
 */
function classifyFcmFailure(httpStatus: number, error: FcmErrorBody): FcmFailure {
  const details = Array.isArray(error.details) ? error.details : [];
  const errorCode = details.find((detail) => typeof detail?.errorCode === "string")?.errorCode ||
    error.status || "";

  if (httpStatus === 401 || httpStatus === 403) return "configuration";
  if (httpStatus === 429 || httpStatus >= 500) return "transient";
  if (errorCode === "UNREGISTERED" || httpStatus === 404) return "token_invalid";
  if (errorCode === "INVALID_ARGUMENT" || httpStatus === 400) {
    const tokenFieldViolation = details.some((detail) =>
      Array.isArray(detail?.fieldViolations) &&
      detail.fieldViolations.some((violation) => violation?.field === "message.token")
    );
    const tokenMessage = /registration token/i.test(error.message || "");
    return tokenFieldViolation || tokenMessage ? "token_invalid" : "message_rejected";
  }
  if (httpStatus >= 400 && httpStatus < 500) return "message_rejected";
  return "transient";
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
  // CORS headers are added once, in the request entry point (withCors).
  // `no-store` on every response: reveal_card_secret / decrypt_card_secret
  // carry a card PIN that must never be written to an HTTP cache.
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Pragma": "no-cache",
    },
  });
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "Unknown error";
}
