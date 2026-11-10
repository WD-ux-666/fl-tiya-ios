import test from "node:test";
import assert from "node:assert/strict";
import { createPaymentServices } from "../_shared/payment-runtime.mjs";
import { createPurchaseHandler, createNotificationHandler } from "../_shared/payment-handlers.mjs";

const userId = "4108389d-a330-4c60-8a4f-78b6b1fbd923";
const sessionId = "5108389d-a330-4c60-8a4f-78b6b1fbd923";
const fixtureURL = "https://fixture.supabase.co";
// Public synthetic token used only for the in-memory test environment.
const notificationToken = "notification_fixture_".padEnd(43, "x");
const encoded = value => Buffer.from(JSON.stringify(value)).toString("base64url");
// These values are synthetic routing/transport fixtures, never signed receipts.
const jwsFixture = value => `${encoded({ alg: "ES256" })}.${encoded(value)}.fixture`;
const transaction = {
  transactionId: "12345678", environment: "Production", bundleId: "test.payment.fixture",
  appAccountToken: userId, productId: "fixture.pack", type: "Consumable", quantity: 1,
  signedDate: Date.now(),
};
const settings = { bundle_id: transaction.bundleId, app_apple_id: 123, purchases_enabled: true, allow_sandbox: false, store_environment: "Production" };

async function ephemeralConfiguration() {
  const key = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const exported = await crypto.subtle.exportKey("pkcs8", key.privateKey);
  return {
    SUPABASE_URL: fixtureURL, SUPABASE_ANON_KEY: "public-fixture", SUPABASE_SERVICE_ROLE_KEY: "server-fixture",
    APPLE_IAP_NOTIFICATION_TOKEN: notificationToken,
    APPLE_IAP_ISSUER_ID: "6108389d-a330-4c60-8a4f-78b6b1fbd923", APPLE_IAP_KEY_ID: "FIXTURE001",
    APPLE_IAP_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${Buffer.from(exported).toString("base64")}\n-----END PRIVATE KEY-----`,
  };
}

test("full purchase runtime obtains current Apple state then sends only trusted RPC identity", async () => {
  const environment = await ephemeralConfiguration();
  const calls = [];
  const services = createPaymentServices(name => environment[name], async (url, init) => {
    calls.push(url);
    if (url === `${fixtureURL}/auth/v1/user`) return Response.json({ id: userId });
    if (url.endsWith("/rpc/payment_server_settings")) return Response.json(settings);
    if (new URL(url).hostname === "api.storekit.apple.com") {
      assert.match(init.headers.Authorization, /^Bearer /);
      assert.equal(new URL(url).pathname, "/inApps/v1/transactions/12345678");
      return Response.json({ signedTransactionInfo: jwsFixture(transaction) });
    }
    assert.equal(init.headers.apikey, "server-fixture");
    const parameters = JSON.parse(init.body);
    if (url.endsWith("/rpc/apply_apple_refund")) {
      assert.equal(parameters.apple_is_refunded, false);
      assert.equal(parameters.apple_event_date, transaction.signedDate);
      return Response.json({ disposition: "unchanged" });
    }
    assert.ok(url.endsWith("/rpc/credit_apple_purchase"));
    assert.equal(parameters.target_user_id, userId);
    assert.equal(parameters.target_session_id, sessionId);
    assert.equal(parameters.apple_product_id, transaction.productId);
    assert.equal(parameters.amount, undefined);
    return Response.json({ transaction_id: transaction.transactionId, environment: "Production", disposition: "credited", credited_sparks: 400, wallet: { sparks: 400, refund_debt_sparks: 0 } });
  });
  const accessToken = jwsFixture({ sub: userId, session_id: sessionId, role: "authenticated", aud: "authenticated", iss: `${fixtureURL}/auth/v1`, exp: Math.floor(Date.now() / 1000) + 3600 });
  const request = new Request("https://fixture.example/", { method: "POST", headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" }, body: JSON.stringify({ signed_transaction: jwsFixture({ transactionId: transaction.transactionId, environment: "Production", productId: "forged-other-product", appAccountToken: sessionId, quantity: 9999 }) }) });
  const response = await createPurchaseHandler(services)(request);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).credited_sparks, 400);
  assert.equal(calls.length, 5);
});

test("missing Apple credentials fail closed without sending a notification to Apple", async () => {
  const environment = { SUPABASE_URL: fixtureURL, SUPABASE_ANON_KEY: "public-fixture", SUPABASE_SERVICE_ROLE_KEY: "server-fixture", APPLE_IAP_NOTIFICATION_TOKEN: notificationToken };
  const calls = [];
  const services = createPaymentServices(name => environment[name], async url => {
    calls.push(url);
    return Response.json(settings);
  });
  const request = new Request(`https://fixture.example/?token=${notificationToken}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ signedPayload: jwsFixture({ data: { signedTransactionInfo: jwsFixture(transaction) } }) }) });
  const response = await createNotificationHandler(services)(request);
  assert.equal(response.status, 503);
  assert.equal(calls.length, 1);
});

test("malformed notification routing is rejected before any database or Apple request", async () => {
  const calls = [];
  const services = createPaymentServices(name => name === "APPLE_IAP_NOTIFICATION_TOKEN" ? notificationToken : "fixture", async url => { calls.push(url); return Response.json(settings); });
  const request = new Request(`https://fixture.example/?token=${notificationToken}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ signedPayload: "malformed" }) });
  const response = await createNotificationHandler(services)(request);
  assert.equal(response.status, 400);
  assert.deepEqual(calls, []);
});

test("missing or incorrect notification tokens cannot query the database or Apple", async () => {
  const calls = [];
  const environment = { SUPABASE_URL: fixtureURL, SUPABASE_ANON_KEY: "public-fixture", SUPABASE_SERVICE_ROLE_KEY: "server-fixture", APPLE_IAP_NOTIFICATION_TOKEN: notificationToken };
  const services = createPaymentServices(name => environment[name], async url => { calls.push(url); return Response.json(settings); });
  const handler = createNotificationHandler(services);
  const invalidQueries = ["", "?token=wrong", `?token=${"y".repeat(43)}`, `?token=${notificationToken}&token=${notificationToken}`, `?token=${notificationToken}&other=1`, `?token=${"x".repeat(257)}`, `?token=${"x".repeat(42)}!`];
  for (const query of invalidQueries) {
    const response = await handler(new Request(`https://fixture.example/${query}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ signedPayload: jwsFixture({ data: { signedTransactionInfo: jwsFixture(transaction) } }) }) }));
    assert.equal(response.status, 401);
    const body = await response.text();
    assert.equal(body, JSON.stringify({ error: "notification_authentication_required" }));
    assert.equal(body.includes(notificationToken), false);
  }
  assert.deepEqual(calls, []);
});

test("an unset or malformed server notification token fails closed before external work", async () => {
  for (const expected of [undefined, "short", "x".repeat(257), `${"x".repeat(43)}!`]) {
    const calls = [];
    const environment = { SUPABASE_URL: fixtureURL, SUPABASE_ANON_KEY: "public-fixture", SUPABASE_SERVICE_ROLE_KEY: "server-fixture", APPLE_IAP_NOTIFICATION_TOKEN: expected };
    const services = createPaymentServices(name => environment[name], async url => { calls.push(url); return Response.json(settings); });
    const response = await createNotificationHandler(services)(new Request(`https://fixture.example/?token=${notificationToken}`, { method: "POST" }));
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: "notifications_not_configured" });
    assert.deepEqual(calls, []);
  }
});

test("the configured notification token permits an authoritative Apple state refresh", async () => {
  const environment = await ephemeralConfiguration();
  const calls = [];
  const services = createPaymentServices(name => environment[name], async (url, init) => {
    calls.push(url);
    if (url.endsWith("/rpc/payment_server_settings")) return Response.json(settings);
    if (new URL(url).hostname === "api.storekit.apple.com") return Response.json({ signedTransactionInfo: jwsFixture(transaction) });
    assert.ok(url.endsWith("/rpc/apply_apple_refund"));
    assert.equal(JSON.parse(init.body).apple_is_refunded, false);
    return Response.json({ disposition: "unchanged" });
  });
  const request = new Request(`https://fixture.example/?token=${notificationToken}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ signedPayload: jwsFixture({ data: { signedTransactionInfo: jwsFixture(transaction) } }) }) });
  const response = await createNotificationHandler(services)(request);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { received: true });
  assert.equal(calls.length, 3);
  assert.equal(calls.some(url => url.includes(notificationToken)), false);
});
