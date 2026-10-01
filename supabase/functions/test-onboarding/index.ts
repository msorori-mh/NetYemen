import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type AccountType = "customer" | "network_owner";

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

  const allowedPhones = (Deno.env.get("TEST_ONBOARDING_ALLOWED_PHONES") || "")
    .split(",")
    .map((phone) => phone.trim())
    .filter(Boolean);
  if (allowedPhones.length > 0 && !allowedPhones.includes(payload.phone)) {
    return jsonResponse({ error: "TESTER_NOT_ALLOWED" }, 403);
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
      return jsonResponse(
        { error: duplicate ? "ACCOUNT_EXISTS" : "ACCOUNT_CREATION_FAILED" },
        duplicate ? 409 : 400,
      );
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

    return jsonResponse(
      {
        created: true,
        verification_state: application.verification_state,
        owner_review_status: application.owner_review_status,
      },
      201,
    );
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

async function cleanupNewIdentity(
  admin: ReturnType<typeof createClient>,
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
  if (!constantTimeEqual(actualDigest, expectedDigest)) {
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
  if (!/^\+9677\d{8}$/.test(phone)) {
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

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
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
