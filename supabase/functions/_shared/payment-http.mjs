import { PaymentError, validatedSession } from "./payment-validation.mjs";

export function bearerToken(headers) {
  const value = headers.get("authorization");
  const match = value?.length <= 16384 && /^Bearer ([A-Za-z0-9_.-]+)$/i.exec(value);
  if (!match) throw new PaymentError(401, "authentication_required");
  return match[1];
}

export async function readPaymentJSON(request, field, maxBytes) {
  const mediaType = request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
  if (mediaType !== "application/json") throw new PaymentError(415, "json_required");
  const declaredLength = request.headers.get("content-length");
  if (declaredLength !== null && (!/^[0-9]+$/.test(declaredLength) || Number(declaredLength) > maxBytes)) {
    throw new PaymentError(413, "request_too_large");
  }
  const reader = request.body?.getReader();
  if (!reader) throw new PaymentError(400, "invalid_request");
  let bytes = 0;
  const chunks = [];
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maxBytes) {
        await reader.cancel();
        throw new PaymentError(413, "request_too_large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const buffer = new Uint8Array(bytes);
  let offset = 0;
  for (const chunk of chunks) { buffer.set(chunk, offset); offset += chunk.byteLength; }
  let parsed;
  try {
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(buffer));
  } catch { throw new PaymentError(400, "invalid_request"); }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) || Object.keys(parsed).length !== 1 ||
      typeof parsed[field] !== "string" || !parsed[field].length) throw new PaymentError(400, "invalid_request");
  return parsed[field];
}

export function jsonResponse(status, body, additionalHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...additionalHeaders },
  });
}

export function errorResponse(error) {
  // Do not serialize exception text: it can contain receipts, tokens or SQL details.
  if (error instanceof PaymentError) return jsonResponse(error.status, { error: error.code });
  return jsonResponse(503, { error: "payment_service_unavailable" });
}

async function responseJSON(response) {
  const text = await response.text();
  if (text.length > 524288) throw new Error("response_too_large");
  return JSON.parse(text);
}

export async function authenticateUser(token, configuration, fetchImpl = fetch, options = {}) {
  let response;
  try {
    response = await fetchImpl(`${configuration.url}/auth/v1/user`, {
      method: "GET", redirect: "error", signal: AbortSignal.timeout(10000),
      headers: { apikey: configuration.anonKey, Authorization: `Bearer ${token}` },
    });
  } catch { throw new PaymentError(503, "authentication_unavailable"); }
  if (response.status === 401 || response.status === 403) throw new PaymentError(401, "invalid_session");
  if (!response.ok) throw new PaymentError(503, "authentication_unavailable");
  let user;
  try { user = await responseJSON(response); }
  catch { throw new PaymentError(503, "authentication_unavailable"); }
  return validatedSession(token, user, configuration.url, Date.now() / 1000, options);
}

export async function rpcCall(name, parameters, configuration, fetchImpl = fetch) {
  if (!/^[a-z_]+$/.test(name)) throw new PaymentError(503, "payment_service_unavailable");
  let response;
  try {
    response = await fetchImpl(`${configuration.url}/rest/v1/rpc/${name}`, {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(10000),
      headers: { apikey: configuration.serviceRoleKey, Authorization: `Bearer ${configuration.serviceRoleKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(parameters),
    });
    if (!response.ok) throw new Error("rpc_failed");
    return await responseJSON(response);
  } catch { throw new PaymentError(503, "payment_service_unavailable"); }
}
