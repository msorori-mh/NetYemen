import { createServer } from "node:http";

const port = 8787;
const expectedKey = process.env.WASEL_RADIUS_INTERNAL_KEY;
const sessionId = "99000000-0000-4000-8000-000000000001";
const stats = { authorizeAccepted: 0, authorizeDenied: 0, accounting: 0 };

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

  let body;
  try {
    body = JSON.parse(await readLimitedBody(request, 8_192));
  } catch {
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
    });
  }

  if (body.action === "accounting" && body.session_id === sessionId) {
    stats.accounting += 1;
    response.writeHead(204, { "cache-control": "no-store" });
    return response.end();
  }
  return sendJson(response, 400, { error: "INVALID_ACTION" });
}).listen(port, "0.0.0.0");

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
