import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.38.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type AccountType = "customer" | "network_owner";

// The gate may be open for at most this long. A far-future expiry would turn a
// temporary pilot door into a permanent unauthenticated signup endpoint.
const MAX_GATE_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;
const PHONE_PATTERN = /^\+9677\d{8}$/;

interface TestOnboardingPayload {
  full_name: string;
  phone: string;
  password: string;
  requested_account_type: AccountType;
  governorate: string;
  city: string;
  latitude: number;
  longitude: number;
  location_accuracy_m?: number;
  invite_code: string;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405);
  }

  let rawBody: string;
  let body: unknown;
  try {
    rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).byteLength > 16_384) {
      return jsonResponse({ error: "REQUEST_TOO_LARGE" }, 413);
    }
    body = JSON.parse(rawBody);
  } catch {
    return jsonResponse({ error: "INVALID_REQUEST" }, 400);
  }

  const gateError = await validateGate(body);
  if (gateError) return gateError;

  let payload: TestOnboardingPayload;
  try {
    payload = validatePayload(body);
  } catch (error) {
    return jsonResponse(
      { error: "INVALID_REQUEST", message: safeMessage(error) },
      400,
    );
  }

  // The allowlist is mandatory (validateGate refuses an empty one). A phone
  // outside it gets exactly the same answer as a wrong invite code, so the
  // endpoint cannot be used to learn which numbers are on the tester list.
  if (!allowedPhoneNumbers().includes(payload.phone)) {
    console.error("test-onboarding rejected a phone outside the allowlist");
    return jsonResponse({ error: "INVALID_INVITE" }, 403);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("test-onboarding server configuration is incomplete");
    return jsonResponse({ error: "SERVICE_UNAVAILABLE" }, 503);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let createdUserId: string | null = null;
  try {
    const { data, error } = await admin.auth.admin.createUser({
      phone: payload.phone,
      password: payload.password,
      phone_confirm: true,
      user_metadata: { full_name: payload.full_name },
      app_metadata: { onboarding_channel: "test_invite" },
    });
    if (error || !data.user) {
      const duplicate = error?.message?.toLowerCase().includes("already") ??
        false;
      if (duplicate) {
        // No ACCOUNT_EXISTS oracle: an already-registered phone receives the
        // same response as a newly created one. Nothing is created or changed
        // (the existing password is untouched), so the caller can only get in
        // by signing in with the real password. The detail stays server-side.
        console.warn("test-onboarding: phone already registered; no account created");
        return acceptedResponse();
      }
      console.error(
        "test-onboarding createUser failed:",
        error?.message ?? "no user returned",
      );
      return jsonResponse({ error: "ACCOUNT_CREATION_FAILED" }, 400);
    }

    createdUserId = data.user.id;
    const { data: application, error: applicationError } = await admin.rpc(
      "register_test_onboarding",
      {
        p_user_id: createdUserId,
        p_requested_account_type: payload.requested_account_type,
        p_governorate: payload.governorate,
        p_city: payload.city,
        p_latitude: payload.latitude,
        p_longitude: payload.longitude,
        p_location_accuracy_m: payload.location_accuracy_m ?? null,
        p_invite_label: Deno.env.get("TEST_ONBOARDING_INVITE_LABEL") ||
          "controlled-pilot",
      },
    );
    if (applicationError) throw applicationError;

    console.log(
      "test-onboarding created an account:",
      application?.verification_state ?? "unknown",
      application?.owner_review_status ?? "unknown",
    );
    return acceptedResponse();
  } catch (error) {
    console.error(
      "test-onboarding failed without logging credentials:",
      safeMessage(error),
    );
    if (createdUserId) {
      await cleanupNewIdentity(admin, createdUserId);
    }
    return jsonResponse({ error: "ACCOUNT_CREATION_FAILED" }, 500);
  }
});

// One response for "created" and "already registered" (see above). The account
// state is deliberately not echoed; the app reads it after signing in.
function acceptedResponse(): Response {
  return jsonResponse({ accepted: true }, 201);
}

function allowedPhoneNumbers(): string[] {
  return (Deno.env.get("TEST_ONBOARDING_ALLOWED_PHONES") || "")
    .split(",")
    .map((phone) => phone.trim())
    .filter(Boolean);
}

async function cleanupNewIdentity(
  // Same client type the notification adapter uses (and CI type-checks).
  // ReturnType<typeof createClient> resolves the generic parameters to their
  // constraints, which the client created above is not assignable to.
  admin: SupabaseClient,
  userId: string,
): Promise<void> {
  // Exact, newly-created identity cleanup. profiles and wallet_accounts use
  // ON DELETE RESTRICT, so their automatic rows must be removed first.
  const cleanupSteps = [
    () =>
      admin.from("test_onboarding_applications").delete().eq("user_id", userId),
    () => admin.from("wallet_accounts").delete().eq("user_id", userId),
    () => admin.from("profiles").delete().eq("id", userId),
  ];
  for (const cleanup of cleanupSteps) {
    const { error } = await cleanup();
    if (error) {
      console.error("test-onboarding cleanup step failed:", error.message);
    }
  }
  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) {
    console.error("test-onboarding auth cleanup failed:", error.message);
  }
}

async function validateGate(value: unknown): Promise<Response | null> {
  if (Deno.env.get("TEST_ONBOARDING_ENABLED") !== "true") {
    return jsonResponse({ error: "TEST_ONBOARDING_DISABLED" }, 503);
  }

  const expiresAt = Deno.env.get("TEST_ONBOARDING_EXPIRES_AT");
  if (
    !expiresAt || Number.isNaN(Date.parse(expiresAt)) ||
    Date.now() >= Date.parse(expiresAt)
  ) {
    return jsonResponse({ error: "TEST_ONBOARDING_EXPIRED" }, 403);
  }
  if (Date.parse(expiresAt) - Date.now() > MAX_GATE_WINDOW_MS) {
    console.error(
      "TEST_ONBOARDING_EXPIRES_AT is more than 14 days ahead; refusing to run",
    );
    return jsonResponse({ error: "SERVICE_UNAVAILABLE" }, 503);
  }

  // A named-tester allowlist is mandatory. With an empty list the only barrier
  // would be one shared invite code, i.e. anyone holding it could mint
  // phone-confirmed accounts for arbitrary numbers.
  const allowedPhones = allowedPhoneNumbers();
  if (
    allowedPhones.length === 0 ||
    allowedPhones.some((phone) => !PHONE_PATTERN.test(phone))
  ) {
    console.error(
      "TEST_ONBOARDING_ALLOWED_PHONES is empty or contains an invalid number; refusing to run",
    );
    return jsonResponse({ error: "SERVICE_UNAVAILABLE" }, 503);
  }

  const expectedDigest = (Deno.env.get("TEST_ONBOARDING_INVITE_SHA256") || "")
    .toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(expectedDigest)) {
    console.error("TEST_ONBOARDING_INVITE_SHA256 is missing or invalid");
    return jsonResponse({ error: "SERVICE_UNAVAILABLE" }, 503);
  }

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return jsonResponse({ error: "INVALID_REQUEST" }, 400);
  }
  const body = value as Record<string, unknown>;
  const inviteCode = typeof body.invite_code === "string"
    ? body.invite_code
    : "";
  const actualDigest = await sha256Hex(inviteCode);
  if (!(await constantTimeEqual(actualDigest, expectedDigest))) {
    return jsonResponse({ error: "INVALID_INVITE" }, 403);
  }
  return null;
}

function validatePayload(value: unknown): TestOnboardingPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("البيانات المرسلة غير صحيحة");
  }
  const body = value as Record<string, unknown>;
  const fullName = requiredText(body.full_name, "الاسم", 3, 120);
  const phone = requiredText(body.phone, "رقم الهاتف", 13, 13);
  if (!PHONE_PATTERN.test(phone)) {
    throw new Error("رقم الهاتف اليمني غير صحيح");
  }
  const password = requiredPassword(body.password);
  if (!/[A-Za-z]/.test(password) || !/\d/.test(password)) {
    throw new Error("كلمة المرور يجب أن تحتوي حرفاً ورقماً");
  }
  const accountType = body.requested_account_type;
  if (accountType !== "customer" && accountType !== "network_owner") {
    throw new Error("نوع الحساب غير صحيح");
  }
  const governorate = requiredText(body.governorate, "المحافظة", 2, 80);
  const city = requiredText(body.city, "المدينة", 2, 120);
  const latitude = requiredNumber(body.latitude, "خط العرض", -90, 90);
  const longitude = requiredNumber(body.longitude, "خط الطول", -180, 180);
  const accuracy = body.location_accuracy_m === undefined
    ? undefined
    : requiredNumber(body.location_accuracy_m, "دقة الموقع", 0, 100000);
  const inviteCode = requiredText(body.invite_code, "رمز المختبر", 12, 256);

  return {
    full_name: fullName,
    phone,
    password,
    requested_account_type: accountType,
    governorate,
    city,
    latitude,
    longitude,
    location_accuracy_m: accuracy,
    invite_code: inviteCode,
  };
}

function requiredText(
  value: unknown,
  label: string,
  minLength: number,
  maxLength: number,
): string {
  if (typeof value !== "string") throw new Error(`${label} مطلوب`);
  const result = value.trim();
  if (result.length < minLength || result.length > maxLength) {
    throw new Error(`${label} غير صحيح`);
  }
  return result;
}

function requiredPassword(value: unknown): string {
  if (typeof value !== "string" || value.length < 8 || value.length > 128) {
    throw new Error("كلمة المرور غير صحيحة");
  }
  if (value !== value.trim()) {
    throw new Error("كلمة المرور لا تبدأ أو تنتهي بمسافة");
  }
  return value;
}

function requiredNumber(
  value: unknown,
  label: string,
  minimum: number,
  maximum: number,
): number {
  if (
    typeof value !== "number" || !Number.isFinite(value) || value < minimum ||
    value > maximum
  ) {
    throw new Error(`${label} غير صحيح`);
  }
  return value;
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

// Constant-time comparison: both inputs are hashed to fixed-length digests and
// every byte is compared, with no early exit on length or on the first
// difference (same helper as radius-control).
async function constantTimeEqual(left: string, right: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [leftHash, rightHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  const a = new Uint8Array(leftHash);
  const b = new Uint8Array(rightHash);
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}

function safeMessage(error: unknown): string {
  return error instanceof Error ? error.message : "حدث خطأ غير متوقع";
}

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}
