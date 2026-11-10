import assert from 'node:assert/strict';
import test from 'node:test';
import { webcrypto } from 'node:crypto';
import {
  AppleAPIError,
  decodeUntrustedNotificationHint,
  decodeUntrustedTransactionHint,
  fetchAppleTransaction,
  isAppleAPIConfigured,
} from './apple-api.mjs';

const settings = {
  bundle_id: 'com.example.payments',
  store_environment: 'Production',
  allow_sandbox: false,
};
const transactionID = '2000000123456789';
const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const jws = (value) => `${encode({ alg: 'ES256' })}.${encode(value)}.not-a-verified-signature`;
const payload = (overrides = {}) => ({
  transactionId: transactionID,
  bundleId: settings.bundle_id,
  environment: 'Production',
  productId: 'com.example.sparks.small',
  type: 'Consumable',
  quantity: 1,
  signedDate: 1793664000000,
  ...overrides,
});

async function testSecrets() {
  const pair = await webcrypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = await webcrypto.subtle.exportKey('pkcs8', pair.privateKey);
  const encoded = Buffer.from(der).toString('base64').match(/.{1,64}/g).join('\n');
  return {
    pair,
    values: {
      APPLE_IAP_ISSUER_ID: '00000000-0000-4000-8000-000000000001',
      APPLE_IAP_KEY_ID: 'TESTKEY123',
      APPLE_IAP_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${encoded}\n-----END PRIVATE KEY-----`,
    },
  };
}
const fixture = await testSecrets();
function options(fetchImpl, additions = {}) {
  return { secrets: fixture.values, fetchImpl, cryptoImpl: webcrypto, ...additions };
}
function appleResponse(body = payload(), additions = {}) {
  return new Response(JSON.stringify({ signedTransactionInfo: jws(body) }), {
    headers: { 'Content-Type': 'application/json' }, ...additions,
  });
}
function hasCode(code) {
  return (error) => error instanceof AppleAPIError && error.code === code;
}

test('client transaction data yields only an untrusted routing hint', () => {
  assert.deepEqual(decodeUntrustedTransactionHint(jws(payload({ credited_sparks: 1000000 }))), {
    transactionId: transactionID, environment: 'Production',
  });
});

test('notification data yields only a nested transaction routing hint', () => {
  assert.deepEqual(decodeUntrustedNotificationHint(jws({
    notificationType: 'REFUND',
    data: { signedTransactionInfo: jws(payload()) },
  })), { transactionId: transactionID, environment: 'Production' });
});

test('malformed routing data and unsupported test environments fail closed', () => {
  for (const value of ['', 'a.b.c', jws([]), jws({ transactionId: '../other' }),
    jws(payload({ environment: 'Xcode' })), jws(payload({ environment: ['Production'] })), 'x'.repeat(40000)]) {
    assert.throws(() => decodeUntrustedTransactionHint(value), hasCode('invalid_transaction'));
  }
  assert.throws(() => decodeUntrustedNotificationHint(jws({ notificationType: 'TEST' })),
    hasCode('invalid_transaction'));
});

test('missing Apple credentials prevent any network call', async () => {
  assert.equal(isAppleAPIConfigured({}), false);
  assert.equal(isAppleAPIConfigured(fixture.values), true);
  let called = false;
  await assert.rejects(fetchAppleTransaction(transactionID, settings, options(() => {
    called = true;
  }, { secrets: {} })), hasCode('payments_unavailable'));
  assert.equal(called, false);
});

test('request JWT uses a valid ES256 signature and exact Apple authorization claims', async () => {
  const now = 1793664000000;
  let observed;
  const result = await fetchAppleTransaction(transactionID, settings, options(async (url, init) => {
    observed = { url, init };
    return appleResponse();
  }, { now: () => now }));
  assert.equal(observed.url, `https://api.storekit.apple.com/inApps/v1/transactions/${transactionID}`);
  assert.equal(observed.init.redirect, 'error');
  assert.equal(observed.init.method, 'GET');
  assert.ok(observed.init.signal instanceof AbortSignal);
  const token = observed.init.headers.Authorization.slice('Bearer '.length);
  const [header, body, signature] = token.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), {
    alg: 'ES256', kid: fixture.values.APPLE_IAP_KEY_ID, typ: 'JWT',
  });
  assert.deepEqual(JSON.parse(Buffer.from(body, 'base64url')), {
    iss: fixture.values.APPLE_IAP_ISSUER_ID,
    iat: now / 1000, exp: now / 1000 + 300,
    aud: 'appstoreconnect-v1', bid: settings.bundle_id,
  });
  assert.equal(await webcrypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, fixture.pair.publicKey,
    Buffer.from(signature, 'base64url'), Buffer.from(`${header}.${body}`)), true);
  assert.deepEqual(result, payload());
});

test('Sandbox is rejected unless explicitly allowed and uses only its fixed Apple host', async () => {
  await assert.rejects(fetchAppleTransaction(transactionID, settings, options(() => appleResponse(),
    { environment: 'Sandbox' })), hasCode('payments_unavailable'));
  let observed;
  const result = await fetchAppleTransaction(transactionID, { ...settings, allow_sandbox: true }, options(async (url) => {
    observed = url;
    return appleResponse(payload({ environment: 'Sandbox' }));
  }, { environment: 'Sandbox' }));
  assert.equal(observed, `https://api.storekit-sandbox.apple.com/inApps/v1/transactions/${transactionID}`);
  assert.equal(result.environment, 'Sandbox');
  await assert.rejects(fetchAppleTransaction(transactionID, settings, options(() => appleResponse(),
    { environment: 'https://attacker.invalid' })), hasCode('payments_unavailable'));
});

test('authoritative Apple response must match the requested transaction, configured bundle and environment', async () => {
  for (const overrides of [{ transactionId: '2000000999999999' }, { bundleId: 'com.other.app' },
    { environment: 'Sandbox' }]) {
    await assert.rejects(fetchAppleTransaction(transactionID, settings, options(async () => appleResponse(payload(overrides)))),
      hasCode('invalid_apple_response'));
  }
});

test('invalid transaction paths are rejected before the Apple request', async () => {
  for (const value of ['../credentials', '123?x=1', '', 123, '1'.repeat(65)]) {
    await assert.rejects(fetchAppleTransaction(value, settings, options(() => appleResponse())),
      hasCode('invalid_transaction'));
  }
});

test('network failures, redirects and Apple temporary errors do not grant a purchase', async () => {
  for (const failure of [async () => { throw new TypeError('redirect blocked'); },
    async () => new Response('', { status: 302 }),
    async () => new Response('', { status: 429 }),
    async () => new Response('', { status: 500 })]) {
    await assert.rejects(fetchAppleTransaction(transactionID, settings, options(failure)),
      hasCode('apple_transaction_unavailable'));
  }
});

test('Apple not-found and key failures have safe separate error states', async () => {
  await assert.rejects(fetchAppleTransaction(transactionID, settings, options(async () => new Response('', { status: 404 }))),
    hasCode('invalid_transaction'));
  await assert.rejects(fetchAppleTransaction(transactionID, settings, options(async () => new Response('', { status: 401 }))),
    hasCode('apple_configuration_invalid'));
});

test('oversized or malformed Apple API responses fail closed', async () => {
  const failures = [
    async () => new Response('x'.repeat(66000), { headers: { 'Content-Type': 'application/json' } }),
    async () => new Response('{}', { headers: { 'Content-Type': 'text/html' } }),
    async () => new Response('{}', { headers: { 'Content-Type': 'application/json' } }),
    async () => new Response('not-json', { headers: { 'Content-Type': 'application/json' } }),
    async () => new Response(JSON.stringify({ signedTransactionInfo: jws([]) }), { headers: { 'Content-Type': 'application/json' } }),
  ];
  for (const failure of failures) {
    await assert.rejects(fetchAppleTransaction(transactionID, settings, options(failure)), hasCode('invalid_apple_response'));
  }
});

test('a malformed private key is reported without leaking key material', async () => {
  const marker = 'PRIVATE-SECRET-CONTENT';
  const secrets = { ...fixture.values, APPLE_IAP_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${marker}\n-----END PRIVATE KEY-----` };
  try {
    await fetchAppleTransaction(transactionID, settings, options(() => appleResponse(), { secrets }));
    assert.fail('The malformed key must fail');
  } catch (error) {
    assert.equal(String(error).includes(marker), false);
    assert.equal(error.status, 503);
  }
});
