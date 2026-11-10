// Serves fixed, public documents; no cookies, credentials or personalized data are read.
export function createLegalDocumentsHandler({baseURL, documents, legacyHandler}) {
  const origin = new URL(baseURL);
  if (origin.protocol !== 'https:' && !['localhost', '127.0.0.1', 'kong'].includes(origin.hostname)) {
    throw new Error('Invalid legal document origin');
  }
  const basePath = '/functions/v1/privacy-policy';
  const manifest = {};
  const files = new Map();
  for (const [key, filename] of [
    ['privacy_policy', 'privacy-policy.pdf'],
    ['user_agreement', 'user-agreement.pdf'],
  ]) {
    const {version, base64} = documents[key];
    const bytes = Uint8Array.from(atob(base64), char => char.charCodeAt(0));
    if (!/^[A-Za-z0-9._-]{1,80}$/.test(version) || bytes.length > 1024 * 1024
      || new TextDecoder().decode(bytes.subarray(0, 5)) !== '%PDF-') {
      throw new Error('Invalid legal document');
    }
    const path = basePath + '/' + filename;
    manifest[key] = {url: new URL(path, origin.origin).href, version};
    files.set(path, {bytes, filename, version});
  }

  const allow = 'GET, HEAD, OPTIONS';
  const common = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': allow,
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
  };
  return request => {
    const url = new URL(request.url);
    // The Edge Runtime may pass the function path with the gateway prefix stripped.
    const path = url.pathname.startsWith('/privacy-policy/') || url.pathname === '/privacy-policy'
      ? '/functions/v1' + url.pathname : url.pathname;
    if (path === basePath || path === basePath + '/') return legacyHandler(request);
    const send = (body, status, headers) => new Response(request.method === 'HEAD' ? null : body, {
      status, headers: {...common, ...headers},
    });
    if (!['GET', 'HEAD', 'OPTIONS'].includes(request.method)) {
      return send('Method not allowed\n', 405, {Allow: allow, 'Cache-Control': 'no-store'});
    }
    const pdf = files.get(path);
    const isManifest = path === basePath + '/documents';
    if (!pdf && !isManifest) return send('Not found\n', 404, {'Cache-Control': 'no-store'});
    if (url.search) return send('Unsupported parameters\n', 400, {'Cache-Control': 'no-store'});
    if (request.method === 'OPTIONS') return send(null, 204, {Allow: allow});
    if (isManifest) {
      return send(JSON.stringify(manifest) + '\n', 200, {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'public, max-age=300, must-revalidate',
      });
    }
    return send(pdf.bytes, 200, {
      'Content-Type': 'application/pdf',
      'Content-Disposition': 'inline; filename="' + pdf.filename + '"',
      'Cache-Control': 'public, max-age=300, must-revalidate',
      'X-Document-Version': pdf.version,
    });
  };
}
