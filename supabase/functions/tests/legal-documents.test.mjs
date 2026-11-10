import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createLegalDocumentsHandler} from '../_shared/legal-documents.mjs';
import {createPrivacyPolicyHandler} from '../_shared/privacy-policy.mjs';
import {documents} from '../privacy-policy/documents.mjs';

const origin = 'https://fixture.supabase.co';
const basePath = '/functions/v1/privacy-policy';
const policy = JSON.parse(readFileSync(new URL('../privacy-policy/policy.json', import.meta.url), 'utf8'));
const handler = createLegalDocumentsHandler({
  baseURL: origin, documents, legacyHandler: createPrivacyPolicyHandler(policy),
});
const request = (path, method = 'GET') => new Request('https://untrusted.invalid' + path, {method});

test('manifest advertises canonical public URLs for both exact PDF bytes and matching revisions', async () => {
  const index = await handler(request('/privacy-policy/documents')).json();
  for (const [key, filename, resource] of [
    ['privacy_policy', 'privacy-policy.pdf', 'PrivacyPolicy.json'],
    ['user_agreement', 'user-agreement.pdf', 'UserAgreement.json'],
  ]) {
    const source = JSON.parse(readFileSync(new URL('../../../FLTiya/Resources/' + resource, import.meta.url)));
    const local = readFileSync(new URL('../../legal/' + filename, import.meta.url));
    assert.deepEqual(index[key], {url: origin + basePath + '/' + filename, version: source.document_version});
    const response = handler(new Request(index[key].url));
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'application/pdf');
    assert.equal(response.headers.get('content-disposition'), 'inline; filename="' + filename + '"');
    assert.equal(response.headers.get('x-document-version'), source.document_version);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), local);
  }
});

test('new routes remain read-only and preserve legacy public text and JSON', async () => {
  assert.equal(await handler(request('/privacy-policy/user-agreement.pdf', 'HEAD')).text(), '');
  assert.equal(handler(request(basePath + '/documents', 'POST')).status, 405);
  assert.equal(handler(request(basePath + '/other.pdf')).status, 404);
  assert.equal(handler(request(basePath + '/documents?user=ignored')).status, 400);
  assert.match(await handler(request(basePath)).text(), /Contact: fltiya\.support@gmail\.com/);
  assert.deepEqual(await handler(request('/privacy-policy?format=json')).json(), policy);
});
