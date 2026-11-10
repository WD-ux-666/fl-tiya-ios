import test from "node:test";
import assert from "node:assert/strict";
import { createPurchaseHandler, createNotificationHandler } from "../_shared/payment-handlers.mjs";
import { PaymentError } from "../_shared/payment-validation.mjs";

const userId = "4108389d-a330-4c60-8a4f-78b6b1fbd923";
const sessionId = "5108389d-a330-4c60-8a4f-78b6b1fbd923";
const settings = { bundle_id: "test.payment.fixture", app_apple_id: 123, purchases_enabled: true, allow_sandbox: false, store_environment: "Production" };
const apple = { transactionId: "12345678", environment: "Production", bundleId: settings.bundle_id, appAccountToken: userId, type: "Consumable", quantity: 1, productId: "fixture.pack", signedDate: 1700000000000 };
const envelope = (key, value = "untrusted-routing-only") => new Request("https://fixture.example/", {
  method: "POST", headers: { authorization: "Bearer syntactic.jwt.only", "content-type": "application/json" }, body: JSON.stringify({ [key]: value }),
});
function setup(overrides = {}) {
  const calls = [];
  const services = {
    authenticate: async () => ({ userId, sessionId }),
    authenticateNotification: async () => {},
    getSettings: async () => settings,
    transactionHint: () => ({ transactionId: "12345678", environment: "Production" }),
    notificationHint: () => ({ transactionId: "12345678", environment: "Production" }),
    fetchTransaction: async () => { calls.push("apple"); return apple; },
    reconcile: async parameters => { calls.push({ reconcile: parameters }); return {}; },
    credit: async parameters => {
      calls.push({ credit: parameters });
      return { transaction_id: "12345678", environment: "Production", disposition: "credited", credited_sparks: 400, wallet: { sparks: 400, refund_debt_sparks: 0 } };
    },
    ...overrides,
  };
  return { services, calls };
}

test("purchase endpoint requires authentication before touching the server catalog or Apple", async () => {
  const { services, calls } = setup({ authenticate: async () => { throw new PaymentError(401, "invalid_session"); } });
  const response = await createPurchaseHandler(services)(envelope("signed_transaction"));
  assert.equal(response.status, 401);
  assert.deepEqual(calls, []);
});

test("missing auth, wrong method and arbitrary amount fields cannot invoke Apple", async () => {
  const { services, calls } = setup();
  const handler = createPurchaseHandler(services);
  assert.equal((await handler(new Request("https://fixture.example/"))).status, 405);
  assert.equal((await handler(new Request("https://fixture.example/", { method: "POST" }))).status, 401);
  assert.equal((await handler(new Request("https://fixture.example/", { method: "POST", headers: { authorization: "Bearer a.b.c", "content-type": "application/json" }, body: JSON.stringify({ signed_transaction: "fixture", beneficiary: userId, amount: 9999 }) }))).status, 400);
  assert.deepEqual(calls, []);
});

test("disabled new purchases still deliver a configured already-paid transaction", async () => {
  const { services, calls } = setup({ getSettings: async () => ({ ...settings, purchases_enabled: false }) });
  assert.equal((await createPurchaseHandler(services)(envelope("signed_transaction"))).status, 200);
  assert.equal(calls.length, 3);
});

test("only Apple's current response can supply credit facts and reconciliation runs first", async () => {
  const { services, calls } = setup();
  const response = await createPurchaseHandler(services)(envelope("signed_transaction"));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).credited_sparks, 400);
  assert.equal(calls[0], "apple");
  assert.equal(calls[1].reconcile.apple_is_refunded, false);
  assert.equal(calls[2].credit.target_user_id, userId);
  assert.equal(calls[2].credit.target_session_id, sessionId);
  assert.equal(calls[2].credit.apple_product_id, "fixture.pack");
  assert.equal(calls[2].credit.amount, undefined);
});

test("cross-account transaction is rejected before refund reconciliation or credit", async () => {
  const { services, calls } = setup({ fetchTransaction: async () => ({ ...apple, appAccountToken: sessionId }) });
  const response = await createPurchaseHandler(services)(envelope("signed_transaction"));
  assert.equal(response.status, 403);
  assert.deepEqual(calls, []);
});

test("revoked authoritative transaction is durably reconciled before refunded acknowledgement", async () => {
  const { services, calls } = setup({
    fetchTransaction: async () => ({ ...apple, revocationDate: 1699999999999 }),
    credit: async () => ({ transaction_id: "12345678", environment: "Production", disposition: "refunded", credited_sparks: 0, wallet: { sparks: 0, refund_debt_sparks: 0 } }),
  });
  const response = await createPurchaseHandler(services)(envelope("signed_transaction"));
  assert.equal((await response.json()).disposition, "refunded");
  assert.equal(calls[0].reconcile.apple_is_refunded, true);
});

test("transient reconciliation failure never acknowledges delivery or calls credit", async () => {
  const { services, calls } = setup({ reconcile: async () => { throw new Error("private details"); } });
  const response = await createPurchaseHandler(services)(envelope("signed_transaction"));
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "payment_service_unavailable" });
  assert.deepEqual(calls, ["apple"]);
});

test("a forged notification can only trigger authoritative lookup and cannot supply refund state", async () => {
  const { services, calls } = setup();
  const response = await createNotificationHandler(services)(envelope("signedPayload", "forged-refund-routing-hint"));
  assert.equal(response.status, 200);
  assert.equal(calls[0], "apple");
  assert.equal(calls[1].reconcile.apple_is_refunded, false);
  assert.equal(calls[1].reconcile.apple_event_date, apple.signedDate);
  assert.equal(calls.length, 2);
});

test("the notification authentication gate runs before body parsing and external work", async () => {
  const { services, calls } = setup({ authenticateNotification: async () => { throw new PaymentError(401, "notification_authentication_required"); } });
  const request = new Request("https://fixture.example/", { method: "POST", body: "invalid-body" });
  const response = await createNotificationHandler(services)(request);
  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "notification_authentication_required" });
  assert.deepEqual(calls, []);
});

test("notification processing continues with purchases disabled and never runs credit", async () => {
  const { services, calls } = setup({ getSettings: async () => ({ ...settings, purchases_enabled: false }) });
  assert.equal((await createNotificationHandler(services)(envelope("signedPayload"))).status, 200);
  assert.equal(calls.length, 2);
  assert.equal(calls[1].reconcile.apple_is_refunded, false);
});

test("a disabled sandbox and invalid authoritative type cannot mutate through notifications", async () => {
  const sandbox = setup({ notificationHint: () => ({ transactionId: "12345678", environment: "Sandbox" }) });
  assert.equal((await createNotificationHandler(sandbox.services)(envelope("signedPayload"))).status, 422);
  assert.deepEqual(sandbox.calls, []);
  const invalid = setup({ fetchTransaction: async () => ({ ...apple, type: "Auto-Renewable Subscription" }) });
  assert.equal((await createNotificationHandler(invalid.services)(envelope("signedPayload"))).status, 422);
  assert.deepEqual(invalid.calls, []);
});
