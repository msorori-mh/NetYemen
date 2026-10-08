import { createServer } from "node:http";

const port = 8787;
const expectedKey = process.env.WASEL_RADIUS_INTERNAL_KEY;
const sessionId = "99000000-0000-4000-8000-000000000001";
const stats = {
  authorizeAccepted: 0,
  authorizeDenied: 0,
  accounting: 0,
  accountingEvents: [],
  invalidJson: 0,
  invalidAccounting: 0,
};

if (!expectedKey || expectedKey.startsWith("REPLACE")) {
  throw new Error("WASEL_RADIUS_INTERNAL_KEY is required");
}

createServer(async (request, response) => {
  if (request.method === "GET" && request.url === "/health") {
    return sendJson(response, 200, { status: "ok" });
  }
  if (request.method === "GET" && request.url === "/stats") {
    return sendJson(response, 200, stats);
  }
  if (request.method !== "POST" || request.url !== "/") {
    return sendJson(response, 404, { error: "NOT_FOUND" });
  }
  if (request.headers["x-wasel-radius-key"] !== expectedKey) {
    return sendJson(response, 401, { error: "UNAUTHORIZED" });
  }

  let raw;
  try {
    raw = await readLimitedBody(request, 8_192);
  } catch {
    return sendJson(response, 413, { error: "PAYLOAD_TOO_LARGE" });
  }

  // Strict parse, exactly like the real Edge Function. A FreeRADIUS template
  // that expands a missing attribute to nothing (`"input_bytes":,`) must fail
  // this harness loudly instead of being swallowed.
  let body;
  try {
    body = JSON.parse(raw);
  } catch (error) {
    stats.invalidJson += 1;
    console.error(`MOCK FAIL: FreeRADIUS sent invalid JSON (${error.message}): ${raw}`);
    return sendJson(response, 400, { error: "INVALID_JSON" });
  }
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    stats.invalidJson += 1;
    console.error(`MOCK FAIL: FreeRADIUS sent a non-object JSON body: ${raw}`);
    return sendJson(response, 400, { error: "INVALID_BODY" });
  }

  if (body.action === "authorize") {
    const valid = body.nas_identifier === "wasel-e2e-nas-01" &&
      body.username === "w1-0123456789abcdef01234567" &&
      body.password === "TEST_ONLY_E2E_PASSWORD" &&
      body.request_key === "hs-e2e-000001";
    if (!valid) {
      stats.authorizeDenied += 1;
      return sendJson(response, 403, { accepted: false, error: "ACCESS_REJECT" });
    }
    stats.authorizeAccepted += 1;
    return sendJson(response, 200, {
      "reply:Class": sessionId,
      "reply:Session-Timeout": 3600,
      "reply:Idle-Timeout": 300,
      "reply:Acct-Interim-Interval": 60,
      "reply:Mikrotik-Rate-Limit": "4096k/4096k",
      "reply:Mikrotik-Total-Limit": 1048576,
      "reply:Mikrotik-Total-Limit-Gigawords": 1,
    });
  }

  if (body.action === "accounting") {
    const problem = accountingProblem(body);
    if (problem) {
      stats.invalidAccounting += 1;
      console.error(`MOCK FAIL: invalid accounting request (${problem}): ${raw}`);
      return sendJson(response, 400, { error: problem });
    }
    stats.accounting += 1;
    stats.accountingEvents.push({
      event_type: body.event_type,
      event_key: body.event_key,
      input_bytes: body.input_bytes,
      output_bytes: body.output_bytes,
      input_gigawords: body.input_gigawords,
      output_gigawords: body.output_gigawords,
      session_seconds: body.session_seconds,
    });
    response.writeHead(204, { "cache-control": "no-store" });
    return response.end();
  }
  return sendJson(response, 400, { error: "INVALID_ACTION" });
}).listen(port, "0.0.0.0");

// Mirrors supabase/functions/radius-control/protocol.ts parseAccounting():
// counters must be JSON numbers; null/missing is tolerated for `start` only.
function accountingProblem(body) {
  if (body.session_id !== sessionId) return "INVALID_SESSION_ID";
  if (body.nas_identifier !== "wasel-e2e-nas-01") return "INVALID_NAS_IDENTIFIER";
  if (typeof body.event_key !== "string" || body.event_key.length === 0 ||
    body.event_key.length > 256) {
    return "INVALID_EVENT_KEY";
  }
  if (!["start", "interim-update", "stop"].includes(body.event_type)) {
    return "INVALID_EVENT_TYPE";
  }
  if (typeof body.event_at !== "string" || Number.isNaN(Date.parse(body.event_at))) {
    return "INVALID_EVENT_AT";
  }
  const isStart = body.event_type === "start";
  for (const name of ["input_bytes", "output_bytes", "session_seconds"]) {
    const value = body[name];
    if (isStart && (value === undefined || value === null)) continue;
    if (!isCounter(value)) return `INVALID_${name.toUpperCase()}`;
  }
  for (const name of ["input_gigawords", "output_gigawords"]) {
    const value = body[name];
    if (value === undefined || value === null) continue;
    if (!isCounter(value)) return `INVALID_${name.toUpperCase()}`;
  }
  return null;
}

function isCounter(value) {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

async function readLimitedBody(request, maxBytes) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maxBytes) throw new Error("PAYLOAD_TOO_LARGE");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function sendJson(response, status, value) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(JSON.stringify(value));
}
