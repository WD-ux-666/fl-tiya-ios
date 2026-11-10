import test from "node:test";
import assert from "node:assert/strict";
import {
  PaymentError, requireSettings, validateTransaction, reconciliationFor,
  validatedSession, validateCreditResult,
} from "../_shared/payment-validation.mjs";

const user = "4108389d-a330-4c60-8a4f-78b6b1fbd923";
const session = "5108389d-a330-4c60-8a4f-78b6b1fbd923";
const settings = {
  bundle_id: "test.payment.fixture", app_apple_id: 123, allow_sandbox: false,
  purchases_enabled: true, store_environment: "Production",
};
const transaction = {
  transactionId: "12345678", productId: "fixture.pack", bundleId: settings.bundle_id,
  environment: "Production", type: "Consumable", quantity: 1,
  appAccountToken: user, signedDate: 1700000000000,
};
const fail = (operation, code) => assert.throws(operation, e => e instanceof PaymentError && e.code === code);
const token = claims => `e30.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.fixture`;
const claims = {
  sub: user, session_id: session, role: "authenticated", aud: "authenticated",
  exp: 2000000000, iss: "https://fixture.supabase.co/auth/v1",
};

test("payments require explicit configuration and optional app IDs must be numeric", () => {
  fail(() => requireSettings({}), "payments_not_configured");
  fail(() => requireSettings({ ...settings, purchases_enabled: false }), "purchases_disabled");
  fail(() => requireSettings({ ...settings, app_apple_id: "123" }), "payments_not_configured");
  fail(() => requireSettings({ ...settings, app_apple_id: 0 }), "payments_not_configured");
  assert.equal(requireSettings({ ...settings, app_apple_id: null }).app_apple_id, null);
  assert.equal(requireSettings(settings).store_environment, "Production");
  assert.equal(requireSettings({ ...settings, purchases_enabled: false }, false).purchases_enabled, false);
});

test("sandbox purchase mode requires separate explicit sandbox permission", () => {
  fail(() => requireSettings({ ...settings, store_environment: "Sandbox" }), "payments_not_configured");
  assert.equal(requireSettings({ ...settings, store_environment: "Sandbox", allow_sandbox: true }).store_environment, "Sandbox");
});

test("only an authenticated JWT matching its Auth response supplies a session", () => {
  assert.deepEqual(validatedSession(token(claims), { id: user }, "https://fixture.supabase.co", 1800000000), { userId: user, sessionId: session });
  for (const patch of [{ session_id: null }, { sub: session }, { role: "service_role" }, { exp: 1 }, { iss: "https://other.example/auth/v1" }, { aud: "other" }]) {
    fail(() => validatedSession(token({ ...claims, ...patch }), { id: user }, "https://fixture.supabase.co", 1800000000), "invalid_session");
  }
  fail(() => validatedSession(token(claims), { id: user, is_anonymous: true }, "https://fixture.supabase.co", 1800000000), "invalid_session");
  fail(() => validatedSession("not-a-jwt", { id: user }, "https://fixture.supabase.co", 1800000000), "invalid_session");
});

test("validated consumables produce only Apple transaction identity", () => {
  assert.deepEqual(validateTransaction(transaction, settings, user), {
    environment: "Production", transactionId: "12345678", productId: "fixture.pack", accountToken: user,
    signedDate: 1700000000000, isRefunded: false,
  });
  for (const patch of [{ quantity: 2 }, { quantity: "1" }, { type: "Non-Consumable" }, { transactionId: "../other" }, { productId: "" }, { productId: "x".repeat(201) }, { appAccountToken: null }, { bundleId: "other.app" }, { environment: "Xcode" }, { environment: "LocalTesting" }]) {
    fail(() => validateTransaction({ ...transaction, ...patch }, settings, user), "invalid_transaction");
  }
});

test("transaction delivery rejects cross-account and unexpected sandbox replay", () => {
  fail(() => validateTransaction({ ...transaction, appAccountToken: session }, settings, user), "transaction_account_mismatch");
  fail(() => validateTransaction({ ...transaction, environment: "Sandbox" }, { ...settings, allow_sandbox: true }, user), "transaction_environment_mismatch");
  assert.equal(validateTransaction({ ...transaction, environment: "Sandbox" }, { ...settings, allow_sandbox: true, store_environment: "Sandbox" }, user).environment, "Sandbox");
});

test("authoritative revocation is reconciled before a purchase can be delivered", () => {
  const revoked = validateTransaction({ ...transaction, revocationDate: 1700000000001, revocationReason: 0 }, settings, user);
  assert.equal(reconciliationFor(revoked).apple_is_refunded, true);
  fail(() => validateTransaction({ ...transaction, revocationReason: 0 }, settings, user), "invalid_transaction");
  fail(() => validateTransaction({ ...transaction, signedDate: null }, settings, user), "invalid_transaction");
});

test("partial and unsupported revocations cannot silently debit a full consumable pack", () => {
  for (const patch of [
    { revocationType: "REFUND_PRORATED", revocationPercentage: 50000 },
    { revocationType: "FAMILY_REVOKE" }, { revocationPercentage: 99999 },
    { revocationType: "FUTURE_REVOCATION" },
  ]) {
    fail(() => validateTransaction({ ...transaction, revocationDate: 1700000000001, ...patch }, settings, user), "unsupported_refund_state");
  }
  assert.equal(validateTransaction({ ...transaction, revocationDate: 1700000000001, revocationType: "REFUND_FULL", revocationPercentage: 100000 }, settings, user).isRefunded, true);
});

test("refund reconciliation uses authoritative snapshot facts with deterministic identity", () => {
  const refunded = validateTransaction({ ...transaction, revocationDate: 1700000000001 }, settings, undefined, "Production");
  assert.deepEqual(reconciliationFor(refunded), {
    apple_environment: "Production", apple_transaction_id: "12345678", apple_product_id: "fixture.pack",
    apple_account_token: user, apple_event_id: "apple-api:Production:12345678:1700000000000:refunded",
    apple_event_date: 1700000000000, apple_is_refunded: true,
  });
  assert.equal(reconciliationFor(validateTransaction(transaction, settings)).apple_is_refunded, false);
  fail(() => validateTransaction({ ...transaction, signedDate: -1 }, settings), "invalid_transaction");
});

test("credit response has a bounded explicit public shape and matching environment", () => {
  const response = { transaction_id: "12345678", environment: "Production", disposition: "credited", credited_sparks: 400, wallet: { sparks: 400, refund_debt_sparks: 0 }, internal: "hidden" };
  assert.equal(validateCreditResult(response, "12345678", "Production").internal, undefined);
  fail(() => validateCreditResult({ ...response, environment: "Sandbox" }, "12345678", "Production"), "payment_service_unavailable");
  fail(() => validateCreditResult({ ...response, wallet: { sparks: -1, refund_debt_sparks: 0 } }, "12345678", "Production"), "payment_service_unavailable");
});
