// This module validates facts only after they are retrieved directly from Apple's
// authenticated HTTPS API. Decoding a client JWS never establishes these facts.
export class PaymentError extends Error {
  constructor(status, code) {
    super(code);
    this.name = "PaymentError";
    this.status = status;
    this.code = code;
  }
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const record = value => value !== null && typeof value === "object" && !Array.isArray(value);
const uuid = value => typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : null;
const positiveInteger = value => Number.isSafeInteger(value) && value > 0;
const nonnegativeInteger = value => Number.isSafeInteger(value) && value >= 0;
const fail = (status, code) => { throw new PaymentError(status, code); };

export function requireSettings(value, requirePurchasesEnabled = true) {
  if (!record(value) || typeof value.bundle_id !== "string" || !value.bundle_id.trim() ||
      (value.app_apple_id !== undefined && value.app_apple_id !== null && !positiveInteger(value.app_apple_id)) ||
      !["Production", "Sandbox"].includes(value.store_environment) ||
      typeof value.allow_sandbox !== "boolean" || typeof value.purchases_enabled !== "boolean" ||
      (value.store_environment === "Sandbox" && value.allow_sandbox !== true)) {
    fail(503, "payments_not_configured");
  }
  if (requirePurchasesEnabled && !value.purchases_enabled) fail(503, "purchases_disabled");
  return value;
}

// Call only AFTER Supabase Auth's /user endpoint has authenticated this same JWT.
// The database independently checks this session is still active at credit time.
export function validatedSession(token, authenticatedUser, supabaseURL, nowSeconds = Date.now() / 1000, options = {}) {
  let claims;
  try {
    const pieces = token.split(".");
    if (pieces.length !== 3 || !/^[A-Za-z0-9_-]+$/.test(pieces[1])) throw new Error();
    const base64 = pieces[1].replace(/-/g, "+").replace(/_/g, "/");
    const bytes = Uint8Array.from(atob(base64), char => char.charCodeAt(0));
    claims = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    fail(401, "invalid_session");
  }
  const userId = uuid(authenticatedUser?.id);
  const sessionId = uuid(claims?.session_id);
  const audience = claims?.aud;
  const userAnonymous = authenticatedUser?.is_anonymous === true;
  const claimsAnonymous = claims?.is_anonymous === true;
  if (!userId || !sessionId || uuid(claims?.sub) !== userId ||
      ((userAnonymous || claimsAnonymous) && (options.allowAnonymous !== true || !userAnonymous || !claimsAnonymous)) ||
      claims?.role !== "authenticated" ||
      !(audience === "authenticated" || (Array.isArray(audience) && audience.includes("authenticated"))) ||
      !positiveInteger(claims?.exp) || claims.exp <= nowSeconds ||
      claims?.iss !== `${supabaseURL.replace(/\/$/, "")}/auth/v1`) {
    fail(401, "invalid_session");
  }
  return { userId, sessionId };
}

export function validateTransaction(value, settings, expectedUserId, expectedEnvironment = settings.store_environment) {
  const accountToken = uuid(value?.appAccountToken);
  const hasRevocation = value?.revocationDate !== undefined && value.revocationDate !== null;
  if (!record(value) || !accountToken || typeof value.transactionId !== "string" ||
      !/^[0-9]{1,64}$/.test(value.transactionId) ||
      typeof value.productId !== "string" || !/^[\x21-\x7e]{1,200}$/.test(value.productId) ||
      value.bundleId !== settings.bundle_id || value.type !== "Consumable" || value.quantity !== 1 ||
      !["Production", "Sandbox"].includes(value.environment) ||
      (value.environment === "Sandbox" && settings.allow_sandbox !== true) ||
      !positiveInteger(value.signedDate) ||
      (hasRevocation && !positiveInteger(value.revocationDate)) ||
      (value.revocationReason !== undefined && value.revocationReason !== null &&
        (!hasRevocation || ![0, 1].includes(value.revocationReason))) ||
      (value.inAppOwnershipType !== undefined && value.inAppOwnershipType !== "PURCHASED")) {
    fail(422, "invalid_transaction");
  }
  if (value.environment !== expectedEnvironment) fail(409, "transaction_environment_mismatch");
  if (expectedUserId !== undefined && accountToken !== uuid(expectedUserId)) fail(403, "transaction_account_mismatch");
  const revocationType = value.revocationType;
  const revocationPercentage = value.revocationPercentage;
  if ((revocationType !== undefined && revocationType !== null && (!hasRevocation || revocationType !== "REFUND_FULL")) ||
      (revocationPercentage !== undefined && revocationPercentage !== null && (!hasRevocation || revocationPercentage !== 100000))) {
    // The wallet currently accounts for whole-pack refunds. Do not accidentally
    // debit a full pack for a partial refund or an unsupported revocation type.
    fail(503, "unsupported_refund_state");
  }
  return {
    environment: value.environment, transactionId: value.transactionId,
    productId: value.productId, accountToken,
    signedDate: value.signedDate, isRefunded: hasRevocation,
  };
}

export function reconciliationFor(transaction) {
  return {
    apple_environment: transaction.environment,
    apple_transaction_id: transaction.transactionId,
    apple_product_id: transaction.productId,
    apple_account_token: transaction.accountToken,
    apple_event_id: `apple-api:${transaction.environment}:${transaction.transactionId}:${transaction.signedDate}:${transaction.isRefunded ? "refunded" : "active"}`,
    apple_event_date: transaction.signedDate,
    apple_is_refunded: transaction.isRefunded,
  };
}

export function validateCreditResult(value, transactionId, environment) {
  if (!record(value) || value.transaction_id !== transactionId || value.environment !== environment ||
      !["credited", "already_credited", "refunded"].includes(value.disposition) ||
      !nonnegativeInteger(value.credited_sparks) || !record(value.wallet) ||
      !nonnegativeInteger(value.wallet.sparks) || !nonnegativeInteger(value.wallet.refund_debt_sparks)) {
    fail(503, "payment_service_unavailable");
  }
  return {
    transaction_id: value.transaction_id, environment: value.environment,
    disposition: value.disposition, credited_sparks: value.credited_sparks,
    wallet: { sparks: value.wallet.sparks, refund_debt_sparks: value.wallet.refund_debt_sparks },
  };
}
