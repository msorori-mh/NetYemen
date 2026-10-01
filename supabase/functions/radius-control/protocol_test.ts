import {
  accountingRpcBody,
  authorizationRequestId,
  freeRadiusAccept,
  parseRadiusRequest,
  parseRadiusRequestBody,
} from "./protocol.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("authorize parsing and request id are deterministic", async () => {
  const request = parseRadiusRequest({
    action: "authorize",
    nas_identifier: "wasel-pilot-nas-01",
    client_shortname: "wasel-pilot-nas-01",
    username: "w1-0123456789abcdef01234567",
    password: "TEST_ONLY_PASSWORD",
    request_key: "hs-a-000001",
    device_fingerprint_hash: "a".repeat(64),
  });
  assert(request.action === "authorize", "authorize action expected");
  if (request.action !== "authorize") return;
  const first = await authorizationRequestId(request);
  const second = await authorizationRequestId(request);
  assert(first === second, "same NAS request must produce same idempotency UUID");
  assert(/^[0-9a-f-]{36}$/.test(first), "UUID-shaped id expected");
});

Deno.test("invalid authorize input fails closed", () => {
  let rejected = false;
  try {
    parseRadiusRequest({
      action: "authorize",
      nas_identifier: "bad nas with spaces",
      username: "customer",
      password: "secret",
      request_key: "1",
    });
  } catch {
    rejected = true;
  }
  assert(rejected, "invalid request should be rejected");
});

Deno.test("FreeRADIUS response maps time, class and MikroTik rate", () => {
  const response = freeRadiusAccept({
    accepted: true,
    session_id: "99000000-0000-4000-8000-000000000001",
    session_timeout: 3600,
    idle_timeout: 300,
    speed_limit_kbps: 4096,
    remaining_bytes: 1024,
  });
  assert(response["reply:Class"] === "99000000-0000-4000-8000-000000000001", "Class mismatch");
  assert(response["reply:Acct-Interim-Interval"] === 60, "interim interval mismatch");
  assert(response["reply:Mikrotik-Rate-Limit"] === "4096k/4096k", "rate mapping mismatch");
  assert(response["reply:Mikrotik-Total-Limit"] === 1024, "data cap missing");
  assert(response["reply:Mikrotik-Total-Limit-Gigawords"] === 0, "data cap gigawords mismatch");
});

Deno.test("FreeRADIUS response splits large data caps into gigawords", () => {
  const response = freeRadiusAccept({
    accepted: true,
    session_id: "99000000-0000-4000-8000-000000000001",
    session_timeout: 3600,
    idle_timeout: 300,
    speed_limit_kbps: null,
    remaining_bytes: 5 * 4_294_967_296 + 123,
  });
  assert(response["reply:Mikrotik-Total-Limit"] === 123, "low word mismatch");
  assert(response["reply:Mikrotik-Total-Limit-Gigawords"] === 5, "gigawords mismatch");
});

Deno.test("unlimited entitlements get no data cap", () => {
  const response = freeRadiusAccept({
    accepted: true,
    session_id: "99000000-0000-4000-8000-000000000001",
    session_timeout: 3600,
    idle_timeout: 300,
    speed_limit_kbps: null,
    remaining_bytes: null,
  });
  assert(!("reply:Mikrotik-Total-Limit" in response), "unexpected data cap");
});

Deno.test("an exhausted allowance is never accepted", () => {
  let rejected = false;
  try {
    freeRadiusAccept({
      accepted: true,
      session_id: "99000000-0000-4000-8000-000000000001",
      session_timeout: 3600,
      idle_timeout: 300,
      speed_limit_kbps: null,
      remaining_bytes: 0,
    });
  } catch (error) {
    rejected = error instanceof Error && error.message === "INVALID_REMAINING_BYTES";
  }
  assert(rejected, "zero remaining bytes must fail closed");
});

Deno.test("accounting counters must be safe non-negative integers", () => {
  let rejected = false;
  try {
    parseRadiusRequest({
      action: "accounting",
      session_id: "99000000-0000-4000-8000-000000000001",
      nas_identifier: "wasel-pilot-nas-01",
      client_shortname: "wasel-pilot-nas-01",
      event_key: "event-1",
      event_type: "interim_update",
      event_at: new Date().toISOString(),
      input_bytes: -1,
      output_bytes: 0,
      session_seconds: 60,
    });
  } catch {
    rejected = true;
  }
  assert(rejected, "negative counters should be rejected");
});

Deno.test("RADIUS gigawords extend counters beyond 32 bits", () => {
  const request = parseRadiusRequest({
    action: "accounting",
    session_id: "99000000-0000-4000-8000-000000000001",
    nas_identifier: "wasel-pilot-nas-01",
    client_shortname: "wasel-pilot-nas-01",
    event_key: "event-large",
    event_type: "interim-update",
    event_at: new Date().toISOString(),
    input_bytes: 10,
    output_bytes: 20,
    input_gigawords: 1,
    output_gigawords: 2,
    session_seconds: 60,
  });
  if (request.action !== "accounting") throw new Error("accounting action expected");
  const body = accountingRpcBody(request);
  assert(body.p_input_bytes === 4_294_967_306, "input gigaword conversion mismatch");
  assert(body.p_output_bytes === 8_589_934_612, "output gigaword conversion mismatch");
});

function rejectionOf(value: unknown): string | null {
  try {
    parseRadiusRequest(value);
    return null;
  } catch (error) {
    return error instanceof Error ? error.message : "UNKNOWN";
  }
}

Deno.test("a NAS identifier not bound to the RADIUS client is rejected", () => {
  const authorize = {
    action: "authorize",
    nas_identifier: "wasel-pilot-nas-01",
    username: "w1-0123456789abcdef01234567",
    password: "TEST_ONLY_PASSWORD",
    request_key: "hs-a-000001",
  };
  assert(
    rejectionOf({ ...authorize, client_shortname: "wasel-pilot-nas-02" }) === "INVALID_NAS_BINDING",
    "authorize with a mismatched client shortname must be rejected",
  );
  assert(
    rejectionOf(authorize) === "INVALID_CLIENT_SHORTNAME",
    "authorize without a client shortname must be rejected",
  );
  const accounting = {
    action: "accounting",
    session_id: "99000000-0000-4000-8000-000000000001",
    nas_identifier: "wasel-pilot-nas-01",
    client_shortname: "WASEL-PILOT-NAS-01",
    event_key: "event-1",
    event_type: "start",
    event_at: new Date().toISOString(),
    input_bytes: 0,
    output_bytes: 0,
    session_seconds: 0,
  };
  assert(
    rejectionOf(accounting) === "INVALID_NAS_BINDING",
    "accounting binding comparison must be exact",
  );
});

Deno.test("malformed JSON bodies are client errors, not internal failures", () => {
  // index.ts maps every INVALID_* error to HTTP 400.
  let message = "";
  try {
    parseRadiusRequestBody('{"action":"accounting","input_bytes":,"output_bytes":}');
  } catch (error) {
    message = error instanceof Error ? error.message : "";
  }
  assert(message === "INVALID_BODY", "invalid JSON must map to INVALID_BODY");
});

Deno.test("accounting body with defaulted zero counters parses", () => {
  const request = parseRadiusRequestBody(JSON.stringify({
    action: "accounting",
    session_id: "99000000-0000-4000-8000-000000000001",
    nas_identifier: "wasel-pilot-nas-01",
    client_shortname: "wasel-pilot-nas-01",
    event_key: "hs-1:Start::::",
    event_type: "start",
    event_at: "2026-10-01 10:00:00",
    input_bytes: 0,
    output_bytes: 0,
    input_gigawords: 0,
    output_gigawords: 0,
    session_seconds: 0,
  }));
  assert(request.action === "accounting", "accounting action expected");
});
