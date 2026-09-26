const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const NAS_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const USERNAME_PATTERN = /^w1-[0-9a-f]{24}$/;

export interface AuthorizeRequest {
  action: "authorize";
  nas_identifier: string;
  username: string;
  password: string;
  request_key: string;
  device_fingerprint_hash?: string;
}

export interface AccountingRequest {
  action: "accounting";
  session_id: string;
  nas_identifier: string;
  event_key: string;
  event_type: "start" | "interim_update" | "stop";
  event_at: string;
  input_bytes: number;
  output_bytes: number;
  input_gigawords?: number;
  output_gigawords?: number;
  session_seconds: number;
}

export type RadiusRequest = AuthorizeRequest | AccountingRequest;

export interface RpcAuthorizeResult {
  accepted: boolean;
  session_id: string;
  session_timeout: number;
  idle_timeout: number;
  speed_limit_kbps: number | null;
  remaining_bytes: number | null;
}

export function parseRadiusRequest(value: unknown): RadiusRequest {
  if (!isRecord(value)) throw new Error("INVALID_BODY");
  if (value.action === "authorize") return parseAuthorize(value);
  if (value.action === "accounting") return parseAccounting(value);
  throw new Error("UNKNOWN_ACTION");
}

export async function authorizationRequestId(request: AuthorizeRequest): Promise<string> {
  const material = `${request.nas_identifier.toLowerCase()}\n${request.username.toLowerCase()}\n${request.request_key}`;
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(material)),
  );
  // Deterministic RFC 4122-shaped UUID. Version/variant bits are normalized so
  // retries of the same NAS request resolve to one database authorization.
  digest[6] = (digest[6] & 0x0f) | 0x50;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  const hex = [...digest.slice(0, 16)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function authorizeRpcBody(request: AuthorizeRequest, requestId: string): Record<string, unknown> {
  return {
    p_nas_identifier: request.nas_identifier,
    p_username: request.username,
    p_password: request.password,
    p_authorization_request_id: requestId,
    p_device_fingerprint_hash: request.device_fingerprint_hash ?? null,
  };
}

export function accountingRpcBody(request: AccountingRequest): Record<string, unknown> {
  const inputBytes = request.input_bytes + (request.input_gigawords ?? 0) * 4_294_967_296;
  const outputBytes = request.output_bytes + (request.output_gigawords ?? 0) * 4_294_967_296;
  if (!Number.isSafeInteger(inputBytes) || !Number.isSafeInteger(outputBytes)) {
    throw new Error("INVALID_COUNTER_RANGE");
  }
  return {
    p_session_id: request.session_id,
    p_nas_identifier: request.nas_identifier,
    p_event_key: request.event_key,
    p_event_type: request.event_type,
    p_event_at: request.event_at,
    p_input_bytes: inputBytes,
    p_output_bytes: outputBytes,
    p_session_seconds: request.session_seconds,
  };
}

export function freeRadiusAccept(result: RpcAuthorizeResult): Record<string, unknown> {
  if (!result.accepted || !UUID_PATTERN.test(result.session_id)) throw new Error("INVALID_RPC_RESPONSE");
  const reply: Record<string, unknown> = {
    "reply:Class": result.session_id,
    "reply:Session-Timeout": positiveInt(result.session_timeout, "session_timeout"),
    "reply:Idle-Timeout": positiveInt(result.idle_timeout, "idle_timeout"),
    "reply:Acct-Interim-Interval": 60,
  };
  if (result.speed_limit_kbps !== null) {
    const kbps = positiveInt(result.speed_limit_kbps, "speed_limit_kbps");
    reply["reply:Mikrotik-Rate-Limit"] = `${kbps}k/${kbps}k`;
  }
  return reply;
}

function parseAuthorize(value: Record<string, unknown>): AuthorizeRequest {
  const nas = requiredString(value.nas_identifier, "nas_identifier", 128);
  const username = requiredString(value.username, "username", 64).toLowerCase();
  const password = requiredString(value.password, "password", 128);
  const requestKey = requiredString(value.request_key, "request_key", 256);
  if (!NAS_PATTERN.test(nas)) throw new Error("INVALID_NAS_IDENTIFIER");
  if (!USERNAME_PATTERN.test(username)) throw new Error("INVALID_USERNAME");
  const deviceHash = optionalString(value.device_fingerprint_hash, "device_fingerprint_hash", 64);
  if (deviceHash !== undefined && !SHA256_PATTERN.test(deviceHash)) {
    throw new Error("INVALID_DEVICE_HASH");
  }
  return {
    action: "authorize",
    nas_identifier: nas,
    username,
    password,
    request_key: requestKey,
    ...(deviceHash === undefined ? {} : { device_fingerprint_hash: deviceHash }),
  };
}

function parseAccounting(value: Record<string, unknown>): AccountingRequest {
  const sessionId = requiredString(value.session_id, "session_id", 36);
  const nas = requiredString(value.nas_identifier, "nas_identifier", 128);
  const eventKey = requiredString(value.event_key, "event_key", 256);
  const eventType = value.event_type === "interim-update" ? "interim_update" : value.event_type;
  const eventAt = requiredString(value.event_at, "event_at", 40);
  if (!UUID_PATTERN.test(sessionId)) throw new Error("INVALID_SESSION_ID");
  if (!NAS_PATTERN.test(nas)) throw new Error("INVALID_NAS_IDENTIFIER");
  if (!(["start", "interim_update", "stop"] as unknown[]).includes(eventType)) {
    throw new Error("INVALID_EVENT_TYPE");
  }
  if (Number.isNaN(Date.parse(eventAt))) throw new Error("INVALID_EVENT_AT");
  return {
    action: "accounting",
    session_id: sessionId,
    nas_identifier: nas,
    event_key: eventKey,
    event_type: eventType as AccountingRequest["event_type"],
    event_at: eventAt,
    input_bytes: nonNegativeInt(value.input_bytes, "input_bytes"),
    output_bytes: nonNegativeInt(value.output_bytes, "output_bytes"),
    input_gigawords: nonNegativeInt(value.input_gigawords ?? 0, "input_gigawords"),
    output_gigawords: nonNegativeInt(value.output_gigawords ?? 0, "output_gigawords"),
    session_seconds: nonNegativeInt(value.session_seconds, "session_seconds"),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requiredString(value: unknown, name: string, max: number): string {
  if (typeof value !== "string" || value.length === 0 || value.length > max) {
    throw new Error(`INVALID_${name.toUpperCase()}`);
  }
  return value;
}

function optionalString(value: unknown, name: string, max: number): string | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  return requiredString(value, name, max);
}

function nonNegativeInt(value: unknown, name: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error(`INVALID_${name.toUpperCase()}`);
  }
  return value;
}

function positiveInt(value: unknown, name: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`INVALID_${name.toUpperCase()}`);
  }
  return value;
}
