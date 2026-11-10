import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createPrivacyPolicyHandler } from '../_shared/privacy-policy.mjs';

const edge = new URL('../privacy-policy/policy.json', import.meta.url);
const bundled = new URL('../../../FLTiya/Resources/PrivacyPolicy.json', import.meta.url);
const policy = JSON.parse(readFileSync(edge, 'utf8'));
const base = 'https://fixture.supabase.co/functions/v1/privacy-policy';
const request = (suffix = '', method = 'GET') => new Request(base + suffix, {method});

test('published static and bundled policy are identical and retain current draft/contact facts', () => {
  assert.equal(readFileSync(edge, 'utf8'), readFileSync(bundled, 'utf8'));
  assert.equal(policy.status, 'draft'); assert.equal(policy.effective_date, null);
  assert.equal(policy.contact, 'fltiya.support@gmail.com'); assert.equal(policy.contact_is_placeholder, false);
  assert.equal(policy.sections.length, 12);
  assert.match(policy.notice, /legal operator/);
  assert.ok(policy.sections.some(s => /Photo avatars/.test(s.title)));
  assert.ok(policy.sections.some(s => /pending.*review|held for review/.test(s.text)));
});

test('unauthenticated browser request returns human-readable plain text and Contact near title', async () => {
  const response = createPrivacyPolicyHandler(policy)(request());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'text/plain; charset=utf-8');
  const text = await response.text();
  assert.ok(text.startsWith('FL-Tiya Privacy Policy\nDraft · Not yet effective\nContact: fltiya.support@gmail.com\n'));
  assert.ok(!text.includes('<html'));
  assert.ok(!text.includes('example.com'));
  for (const section of policy.sections) assert.ok(text.includes(section.text));
});

test('JSON format returns same canonical payload without authentication or personalized content', async () => {
  const handler = createPrivacyPolicyHandler(policy);
  const response = handler(request('?format=json'));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'application/json; charset=utf-8');
  assert.equal(await response.text(), readFileSync(edge, 'utf8'));
  const credentialed = new Request(base + '?format=json', {headers: {Authorization: 'Bearer private-fixture', Cookie: 'session=private-fixture'}});
  assert.deepEqual(await handler(credentialed).json(), policy);
  assert.equal(response.headers.get('set-cookie'), null);
  assert.equal(response.headers.get('x-policy-version'), policy.document_version);
});

test('HEAD returns headers without body for text and JSON; OPTIONS permits only readonly methods', async () => {
  const handler = createPrivacyPolicyHandler(policy);
  for (const suffix of ['', '?format=json']) {
    const response = handler(request(suffix, 'HEAD'));
    assert.equal(response.status, 200); assert.equal(await response.text(), '');
  }
  const response = handler(request('', 'OPTIONS'));
  assert.equal(response.status, 204); assert.equal(await response.text(), '');
  assert.equal(response.headers.get('allow'), 'GET, HEAD, OPTIONS');
  assert.equal(response.headers.get('access-control-allow-credentials'), null);
});

test('write methods and unsupported parameters are rejected without echoing request contents', async () => {
  const handler = createPrivacyPolicyHandler(policy);
  for (const method of ['POST', 'PUT', 'PATCH', 'DELETE']) {
    const response = handler(request('', method));
    assert.equal(response.status, 405);
    assert.equal(response.headers.get('cache-control'), 'no-store');
  }
  for (const suffix of ['?format=html', '?format=json&format=json', '?user_id=private-fixture']) {
    const response = handler(request(suffix)); assert.equal(response.status, 400);
    assert.ok(!(await response.text()).includes('private-fixture'));
  }
});

test('malformed, inconsistent and oversized policy documents fail before serving', () => {
  for (const changed of [
    {schema_version: 2}, {contact: 'bad\nHeader: injected'},
    {status: 'effective', effective_date: null}, {status: 'draft', effective_date: '2026-11-06'},
    {document_version: 'injected\r\nheader'}, {document_version: 'trailing-newline\n'}, {notice: 'x'.repeat(3001)},
    {sections: [{id: 'x', title: 'x', text: 'x'}, {id: 'x', title: 'x', text: 'x'}]},
    {sections: Array.from({length: 40}, (_, i) => ({id: 's' + i, title: 'Section', text: 'x'.repeat(12000)}))},
  ]) assert.throws(() => createPrivacyPolicyHandler({...policy, ...changed}));
});
