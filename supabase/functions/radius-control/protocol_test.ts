import {
  accountingRpcBody,
  authorizationRequestId,
  freeRadiusAccept,
  parseRadiusRequest,
} from "./protocol.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("authorize parsing and request id are deterministic", async () => {
  const request = parseRadiusRequest({
    action: "authorize",
    nas_identifier: "wasel-pilot-nas-01",
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
});

Deno.test("accounting counters must be safe non-negative integers", () => {
  let rejected = false;
  try {
    parseRadiusRequest({
      action: "accounting",
      session_id: "99000000-0000-4000-8000-000000000001",
      nas_identifier: "wasel-pilot-nas-01",
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
