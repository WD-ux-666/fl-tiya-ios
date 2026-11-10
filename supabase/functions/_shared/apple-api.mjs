/**
 * Authoritative App Store Server API lookup using fixed Apple HTTPS endpoints.
 *
 * Client / notification JWS values are NEVER treated as verified facts here.
 * They supply a transaction ID for a fresh authenticated Apple API request.
 * The returned transaction payload is trusted because it came directly from
 * Apple's TLS endpoint, with redirects disabled, and is bound to this app,
 * environment and exact requested transaction ID. This does not implement
 * standalone JWS certificate-chain verification. Do not reuse the payload
 * decoder as a verifier for client-provided or notification-provided data.
 *
 * References:
 * https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info
 * https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests
 */

const MAX_JWS_LENGTH = 32768;
const MAX_APPLE_RESPONSE_BYTES = 65536;
const REQUEST_TIMEOUT_MS = 10000;
const TRANSACTION_ID = /^[0-9]{1,64}$/;
const APPLE_ENDPOINTS = Object.freeze({
  Production: 'https://api.storekit.apple.com',
  Sandbox: 'https://api.storekit-sandbox.apple.com',
});

export class AppleAPIError extends Error {
  constructor(code, status = 502) {
    super(code);
    this.name = 'AppleAPIError';
    this.code = code;
    this.status = status;
  }
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function fail(code, status) {
  throw new AppleAPIError(code, status);
}

function decodePayload(jws, code, status) {
  if (typeof jws !== 'string' || jws.length > MAX_JWS_LENGTH) fail(code, status);
  const parts = jws.split('.');
  if (parts.length !== 3 || parts.some((part) => !/^[A-Za-z0-9_-]+$/.test(part))) fail(code, status);
  try {
    const normalized = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const binary = atob(normalized);
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    const value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    if (!isObject(value)) fail(code, status);
    return value;
  } catch {
    fail(code, status);
  }
}

/** A routing hint only. The signature and all economic/account claims are untrusted. */
export function decodeUntrustedTransactionHint(jws) {
  const value = decodePayload(jws, 'invalid_transaction', 400);
  if (typeof value.transactionId !== 'string' || !TRANSACTION_ID.test(value.transactionId)) {
    fail('invalid_transaction', 400);
  }
  if (value.environment !== undefined && (typeof value.environment !== 'string'
    || !Object.hasOwn(APPLE_ENDPOINTS, value.environment))) {
    fail('invalid_transaction', 400);
  }
  return {
    transactionId: value.transactionId,
    ...(value.environment === undefined ? {} : { environment: value.environment }),
  };
}

/** Webhooks only request rechecking Apple; no webhook claim authorizes a wallet change. */
export function decodeUntrustedNotificationHint(jws) {
  const value = decodePayload(jws, 'invalid_transaction', 400);
  if (!isObject(value.data)) fail('invalid_transaction', 400);
  return decodeUntrustedTransactionHint(value.data.signedTransactionInfo);
}

export function isAppleAPIConfigured(secrets) {
  return isObject(secrets)
    && typeof secrets.APPLE_IAP_ISSUER_ID === 'string'
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(secrets.APPLE_IAP_ISSUER_ID)
    && typeof secrets.APPLE_IAP_KEY_ID === 'string'
    && /^[A-Za-z0-9]{10}$/.test(secrets.APPLE_IAP_KEY_ID)
    && typeof secrets.APPLE_IAP_PRIVATE_KEY === 'string'
    && /^-----BEGIN PRIVATE KEY-----\s+[A-Za-z0-9+/=\s]+\s+-----END PRIVATE KEY-----\s*$/.test(secrets.APPLE_IAP_PRIVATE_KEY);
}

function base64url(bytes) {
  const value = btoa(String.fromCharCode(...bytes));
  return value.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function encodedJSON(value) {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

async function createAuthorizationToken(secrets, bundleId, cryptoImpl, now) {
  try {
    const encodedKey = secrets.APPLE_IAP_PRIVATE_KEY
      .replace('-----BEGIN PRIVATE KEY-----', '')
      .replace('-----END PRIVATE KEY-----', '').replace(/\s/g, '');
    const der = Uint8Array.from(atob(encodedKey), (character) => character.charCodeAt(0));
    const key = await cryptoImpl.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
    const issuedAt = Math.floor(now() / 1000);
    const header = encodedJSON({ alg: 'ES256', kid: secrets.APPLE_IAP_KEY_ID, typ: 'JWT' });
    const payload = encodedJSON({
      iss: secrets.APPLE_IAP_ISSUER_ID,
      iat: issuedAt,
      exp: issuedAt + 300,
      aud: 'appstoreconnect-v1',
      bid: bundleId,
    });
    const signingInput = `${header}.${payload}`;
    const signature = new Uint8Array(await cryptoImpl.subtle.sign(
      { name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(signingInput),
    ));
    // Web Crypto returns the 64-byte IEEE P1363 representation ES256 JWTs require.
    if (signature.length !== 64) fail('apple_configuration_invalid', 503);
    return `${signingInput}.${base64url(signature)}`;
  } catch {
    // Do not expose private-key input, imported-key details or low-level crypto errors.
    fail('apple_configuration_invalid', 503);
  }
}

async function readAppleResponse(response) {
  const contentType = response.headers.get('content-type')?.split(';')[0].trim().toLowerCase();
  const contentLength = response.headers.get('content-length');
  if (contentType !== 'application/json' || (contentLength !== null && Number(contentLength) > MAX_APPLE_RESPONSE_BYTES)) {
    fail('invalid_apple_response', 502);
  }
  if (!response.body) fail('invalid_apple_response', 502);
  const reader = response.body.getReader();
  const chunks = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > MAX_APPLE_RESPONSE_BYTES) {
        await reader.cancel();
        fail('invalid_apple_response', 502);
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  try {
    const value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    if (!isObject(value)) fail('invalid_apple_response', 502);
    return value;
  } catch {
    fail('invalid_apple_response', 502);
  }
}

/**
 * Fetch facts directly from Apple. Callers must still enforce app-account-token
 * ownership, product catalog, consumable type, quantity and refund ordering.
 * The environment override is for rechecking a known notification transaction;
 * callers must not silently change purchase environment from a client hint.
 */
export async function fetchAppleTransaction(transactionId, settings, {
  secrets,
  environment = settings?.store_environment,
  fetchImpl = globalThis.fetch,
  cryptoImpl = globalThis.crypto,
  now = Date.now,
} = {}) {
  if (typeof transactionId !== 'string' || !TRANSACTION_ID.test(transactionId)) fail('invalid_transaction', 400);
  if (!isObject(settings) || typeof settings.bundle_id !== 'string'
    || !/^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$/.test(settings.bundle_id)
    || typeof environment !== 'string' || !Object.hasOwn(APPLE_ENDPOINTS, environment)
    || (environment === 'Sandbox' && settings.allow_sandbox !== true)
    || !isAppleAPIConfigured(secrets)) {
    fail('payments_unavailable', 503);
  }
  const authorization = await createAuthorizationToken(secrets, settings.bundle_id, cryptoImpl, now);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetchImpl(`${APPLE_ENDPOINTS[environment]}/inApps/v1/transactions/${transactionId}`, {
      method: 'GET',
      headers: { Authorization: `Bearer ${authorization}`, Accept: 'application/json' },
      redirect: 'error',
      signal: controller.signal,
    });
    if (response.status === 404 || response.status === 400) fail('invalid_transaction', 400);
    if (response.status === 401 || response.status === 403) fail('apple_configuration_invalid', 503);
    if (!response.ok) fail('apple_transaction_unavailable', 503);
    const result = await readAppleResponse(response);
    const transaction = decodePayload(result.signedTransactionInfo, 'invalid_apple_response', 502);
    if (transaction.transactionId !== transactionId || transaction.bundleId !== settings.bundle_id
      || transaction.environment !== environment) {
      fail('invalid_apple_response', 502);
    }
    return transaction;
  } catch (error) {
    if (error instanceof AppleAPIError) throw error;
    // Network / TLS / timeout errors never become a successful verification.
    fail('apple_transaction_unavailable', 503);
  } finally {
    clearTimeout(timeout);
  }
}
