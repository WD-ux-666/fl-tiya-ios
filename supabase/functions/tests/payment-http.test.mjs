import test from "node:test";
import assert from "node:assert/strict";
import { bearerToken, readPaymentJSON, authenticateUser, rpcCall } from "../_shared/payment-http.mjs";
import { PaymentError } from "../_shared/payment-validation.mjs";

const userId = "4108389d-a330-4c60-8a4f-78b6b1fbd923";
const sessionId = "5108389d-a330-4c60-8a4f-78b6b1fbd923";
const url = "https://fixture.supabase.co";
const jwt = payload => `e30.${Buffer.from(JSON.stringify(payload)).toString("base64url")}.untrusted`;
const token = jwt({ sub: userId, session_id: sessionId, iss: `${url}/auth/v1`, exp: 2000000000, role: "authenticated", aud: "authenticated" });
const fails = (operation, code) => assert.rejects(operation, e => e instanceof PaymentError && e.code === code);
const request = (body, headers = { "content-type": "application/json" }) => new Request("https://fixture.example/", { method: "POST", headers, body });

test("Bearer authorization is mandatory and cannot be supplied through another header", () => {
  assert.throws(() => bearerToken(new Headers({ apikey: token })), e => e.code === "authentication_required");
  assert.throws(() => bearerToken(new Headers({ authorization: "Basic fixture" })), e => e.code === "authentication_required");
  assert.equal(bearerToken(new Headers({ authorization: `Bearer ${token}` })), token);
});

test("JSON envelope rejects wrong media, malformed, excessive, and beneficiary fields", async () => {
  await fails(() => readPaymentJSON(request("{}", { "content-type": "text/plain" }), "signed_transaction", 100), "json_required");
  await fails(() => readPaymentJSON(request("{"), "signed_transaction", 100), "invalid_request");
  await fails(() => readPaymentJSON(request(JSON.stringify({ signed_transaction: "x".repeat(101) })), "signed_transaction", 100), "request_too_large");
  await fails(() => readPaymentJSON(request(JSON.stringify({ signed_transaction: "fixture", amount: 400 })), "signed_transaction", 100), "invalid_request");
  assert.equal(await readPaymentJSON(request(JSON.stringify({ signed_transaction: "fixture" })), "signed_transaction", 100), "fixture");
});

test("a syntactically plausible JWT cannot authenticate when Supabase rejects it", async () => {
  let requests = 0;
  await fails(() => authenticateUser(token, { url, anonKey: "public-fixture" }, async (endpoint, init) => {
    requests += 1;
    assert.equal(endpoint, `${url}/auth/v1/user`);
    assert.equal(init.headers.Authorization, `Bearer ${token}`);
    return new Response(JSON.stringify({ error: "bad token" }), { status: 401 });
  }), "invalid_session");
  assert.equal(requests, 1);
});

test("Auth rejection occurs before parsing user-controlled session claims", async () => {
  await fails(() => authenticateUser("totally-untrusted", { url, anonKey: "public-fixture" }, async () => new Response("{}", { status: 401 })), "invalid_session");
});

test("authenticated user and JWT must agree and include a valid current session", async () => {
  const configuration = { url, anonKey: "public-fixture" };
  assert.deepEqual(await authenticateUser(token, configuration, async () => Response.json({ id: userId })), { userId, sessionId });
  await fails(() => authenticateUser(token, configuration, async () => Response.json({ id: sessionId })), "invalid_session");
  await fails(() => authenticateUser(token, configuration, async () => Response.json({ id: userId, is_anonymous: true })), "invalid_session");
});

test("Auth network failures fail closed without exposing upstream error text", async () => {
  await fails(() => authenticateUser(token, { url, anonKey: "public-fixture" }, async () => { throw new Error("sensitive upstream details"); }), "authentication_unavailable");
});

test("database RPC uses server credentials and cannot leak database failures", async () => {
  const configuration = { url, serviceRoleKey: "server-fixture" };
  const result = await rpcCall("payment_server_settings", {}, configuration, async (endpoint, init) => {
    assert.equal(endpoint, `${url}/rest/v1/rpc/payment_server_settings`);
    assert.equal(init.headers.Authorization, "Bearer server-fixture");
    return Response.json({ purchases_enabled: false });
  });
  assert.equal(result.purchases_enabled, false);
  await fails(() => rpcCall("credit_apple_purchase", {}, configuration, async () => new Response("private SQL details", { status: 500 })), "payment_service_unavailable");
});
