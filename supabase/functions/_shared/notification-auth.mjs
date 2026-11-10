import { PaymentError } from "./payment-validation.mjs";

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43,256}$/;
const COMPARISON_CONTEXT = new TextEncoder().encode("FL-Tiya Apple notification token comparison v1");

// Compare through native HMAC verification rather than a JavaScript equality
// operator or an early-return byte loop. The MAC and both keys stay in memory.
async function constantTimeTokenEqual(expected, provided, cryptoImpl) {
  const algorithm = { name: "HMAC", hash: "SHA-256" };
  const encoder = new TextEncoder();
  const expectedKey = await cryptoImpl.subtle.importKey("raw", encoder.encode(expected), algorithm, false, ["sign"]);
  const expectedMAC = await cryptoImpl.subtle.sign("HMAC", expectedKey, COMPARISON_CONTEXT);
  const providedKey = await cryptoImpl.subtle.importKey("raw", encoder.encode(provided), algorithm, false, ["verify"]);
  return cryptoImpl.subtle.verify("HMAC", providedKey, expectedMAC, COMPARISON_CONTEXT);
}

export async function authenticateNotification(request, expectedToken, cryptoImpl = globalThis.crypto) {
  if (typeof expectedToken !== "string" || !TOKEN_PATTERN.test(expectedToken)) {
    throw new PaymentError(503, "notifications_not_configured");
  }
  let provided;
  try {
    if (request.url.length > 4096) throw new Error();
    const parameters = new URL(request.url).searchParams;
    const tokens = parameters.getAll("token");
    if (tokens.length !== 1 || Array.from(parameters.keys()).length !== 1 || !TOKEN_PATTERN.test(tokens[0])) throw new Error();
    provided = tokens[0];
  } catch {
    throw new PaymentError(401, "notification_authentication_required");
  }
  let matches;
  try { matches = await constantTimeTokenEqual(expectedToken, provided, cryptoImpl); }
  catch { throw new PaymentError(503, "notifications_not_configured"); }
  if (!matches) throw new PaymentError(401, "notification_authentication_required");
  // Never log the request URL: its query string contains the notification secret.
  // Provider/proxy access logs must redact the token query parameter as well.
}
