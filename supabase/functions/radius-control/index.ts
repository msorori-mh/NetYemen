import {
  accountingRpcBody,
  authorizationRequestId,
  authorizeRpcBody,
  freeRadiusAccept,
  parseRadiusRequest,
} from "./protocol.ts";
import type { RpcAuthorizeResult } from "./protocol.ts";

const MAX_BODY_BYTES = 8_192;

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);

  const internalKey = Deno.env.get("WASEL_RADIUS_INTERNAL_KEY");
  const suppliedKey = request.headers.get("x-wasel-radius-key");
  if (!internalKey) return json({ error: "SERVICE_NOT_CONFIGURED" }, 503);
  if (!suppliedKey || !(await constantTimeEqual(suppliedKey, internalKey))) {
    return json({ error: "UNAUTHORIZED" }, 401);
  }

  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    return json({ error: "PAYLOAD_TOO_LARGE" }, 413);
  }

  let raw: string;
  try {
    raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
      return json({ error: "PAYLOAD_TOO_LARGE" }, 413);
    }
  } catch {
    return json({ error: "INVALID_BODY" }, 400);
  }

  try {
    const body = parseRadiusRequest(JSON.parse(raw));
    if (body.action === "authorize") {
      const requestId = await authorizationRequestId(body);
      const result = await callRpc(
        "radius_authorize_access",
        authorizeRpcBody(body, requestId),
      ) as RpcAuthorizeResult;
      return json(freeRadiusAccept(result), 200);
    }

    await callRpc("radius_record_accounting", accountingRpcBody(body));
    return new Response(null, { status: 204, headers: { "cache-control": "no-store" } });
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNKNOWN";
    if (message.startsWith("RPC_DENIED:")) {
      // Do not disclose database policy details to the NAS boundary.
      return json({ accepted: false, error: "ACCESS_REJECT" }, 403);
    }
    if (message === "SERVICE_NOT_CONFIGURED") {
      return json({ error: "SERVICE_NOT_CONFIGURED" }, 503);
    }
    if (message === "UNKNOWN_ACTION" || message.startsWith("INVALID_")) {
      return json({ error: message }, 400);
    }
    console.error("radius-control internal failure", { category: message.split(":", 1)[0] });
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});

async function callRpc(name: string, body: Record<string, unknown>): Promise<unknown> {
  const baseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!baseUrl || !serviceKey) throw new Error("SERVICE_NOT_CONFIGURED");
  const response = await fetch(`${baseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "authorization": `Bearer ${serviceKey}`,
      "apikey": serviceKey,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    await response.body?.cancel();
    if (response.status >= 400 && response.status < 500) throw new Error("RPC_DENIED:POLICY");
    throw new Error(`RPC_FAILURE:${response.status}`);
  }
  return await response.json();
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

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}
