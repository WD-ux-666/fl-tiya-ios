// Static public legal content only. No credentials, database, account state,
// request body or user-controlled text is included in the policy response.
export function createPrivacyPolicyHandler(policy) {
  validatePolicy(policy);
  const json = JSON.stringify(policy, null, 2) + '\n';
  const effective = policy.status === 'draft' ? 'Draft · Not yet effective' : 'Effective: ' + policy.effective_date;
  const plain = [policy.title, effective, 'Contact: ' + policy.contact,
    'Version: ' + policy.document_version, '', policy.notice, '',
    ...policy.sections.flatMap(section => [section.title, section.text, ''])].join('\n') + '\n';
  const allow = 'GET, HEAD, OPTIONS';
  const base = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': allow,
    'Access-Control-Allow-Headers': 'content-type',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Cache-Control': 'public, max-age=300, must-revalidate',
    'X-Policy-Version': policy.document_version,
  };
  return request => {
    if (request.method === 'OPTIONS') {
      return new Response(null, {status: 204, headers: {...base, Allow: allow}});
    }
    if (!['GET', 'HEAD'].includes(request.method)) {
      return new Response('Method not allowed\n', {status: 405,
        headers: {...base, Allow: allow, 'Cache-Control': 'no-store', 'Content-Type': 'text/plain; charset=utf-8'}});
    }
    const params = new URL(request.url).searchParams;
    if ([...params.keys()].some(key => key !== 'format') || params.getAll('format').length > 1
      || (params.has('format') && params.get('format') !== 'json')) {
      return new Response(request.method === 'HEAD' ? null : 'Unsupported format\n', {status: 400,
        headers: {...base, 'Cache-Control': 'no-store', 'Content-Type': 'text/plain; charset=utf-8'}});
    }
    const isJSON = params.get('format') === 'json';
    return new Response(request.method === 'HEAD' ? null : isJSON ? json : plain, {
      status: 200, headers: {...base, 'Content-Type': isJSON ? 'application/json; charset=utf-8' : 'text/plain; charset=utf-8'},
    });
  };
}

function validatePolicy(p) {
  const bounded = (value, limit) => typeof value === 'string' && value.trim().length > 0 && value.length <= limit;
  const identifier = value => bounded(value, 80) && !/[^A-Za-z0-9._-]/.test(value);
  if (!p || p.schema_version !== 1 || !bounded(p.document_version, 80)
    || !identifier(p.document_version) || !bounded(p.title, 120)
    || !['draft', 'effective'].includes(p.status) || !bounded(p.contact, 254)
    || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(p.contact) || typeof p.contact_is_placeholder !== 'boolean'
    || !bounded(p.notice, 3000) || !Array.isArray(p.sections) || p.sections.length < 1 || p.sections.length > 40
    || new Set(p.sections.map(s => s.id)).size !== p.sections.length
    || p.sections.some(s => !identifier(s.id)
      || !bounded(s.title, 160) || !bounded(s.text, 12000))
    || (p.status === 'effective' && (p.contact_is_placeholder || p.effective_date?.length !== 10
      || !/^\d{4}-\d{2}-\d{2}$/.test(p.effective_date)))
    || (p.status === 'draft' && p.effective_date !== null)
    || new TextEncoder().encode(JSON.stringify(p, null, 2) + '\n').length > 128 * 1024) {
    throw new Error('Invalid static policy');
  }
}
