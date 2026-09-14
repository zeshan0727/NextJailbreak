const MAIN_ORIGIN = 'https://nextjailbreak.com';
const ALLOWED_ORIGINS = new Set([
  'https://nextjailbreak.com',
  'https://www.nextjailbreak.com',
  'https://repo.nextjailbreak.com'
]);

function cors(origin) {
  const allowed = ALLOWED_ORIGINS.has(origin) ? origin : 'https://nextjailbreak.com';
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin'
  };
}

function json(data, status = 200, origin = '') {
  return new Response(JSON.stringify(data), {
    status,
    headers: {'Content-Type':'application/json; charset=utf-8', ...cors(origin)}
  });
}

async function sha256(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
}

async function repoResponse(request) {
  const url = new URL(request.url);
  let path = url.pathname;
  if (path === '/' || path === '/index.html') path = '/repo-site/index.html';
  const upstream = new URL(path + url.search, MAIN_ORIGIN);
  const headers = new Headers(request.headers);
  headers.set('Host', new URL(MAIN_ORIGIN).host);
  headers.delete('Cookie');
  const response = await fetch(upstream.toString(), {
    method: request.method === 'HEAD' ? 'HEAD' : 'GET',
    headers,
    redirect: 'follow',
    cf: {cacheEverything: true, cacheTtl: path.startsWith('/debfiles/') ? 86400 : 300}
  });
  const out = new Headers(response.headers);
  out.set('X-Next-Jailbreak-Repo', 'repo.nextjailbreak.com');
  out.delete('set-cookie');
  if (path === '/repo-site/index.html') {
    out.set('Cache-Control', 'public, max-age=120');
  }
  return new Response(response.body, {status: response.status, headers: out});
}

async function commentsResponse(request, env) {
  const url = new URL(request.url);
  const origin = request.headers.get('Origin') || '';
  if (request.method === 'OPTIONS') return new Response(null, {status:204, headers:cors(origin)});

  if (request.method === 'GET' && url.pathname === '/api/comments') {
    const slug = String(url.searchParams.get('slug') || '').slice(0, 300);
    if (!slug.startsWith('/')) return json({error:'Invalid article path.'}, 400, origin);
    const result = await env.COMMENTS.prepare(
      'SELECT id, slug, name, body, created_at FROM comments WHERE slug = ? AND approved = 1 ORDER BY id ASC LIMIT 500'
    ).bind(slug).all();
    return json({comments: result.results || []}, 200, origin);
  }

  if (request.method === 'POST' && url.pathname === '/api/comments') {
    if (origin && !ALLOWED_ORIGINS.has(origin)) return json({error:'Origin not allowed.'}, 403, origin);
    let payload;
    try { payload = await request.json(); } catch { return json({error:'Invalid request.'}, 400, origin); }
    const slug = String(payload.slug || '').trim().slice(0, 300);
    const name = String(payload.name || '').trim().replace(/\s+/g, ' ').slice(0, 60);
    const body = String(payload.body || '').trim().slice(0, 2000);
    const website = String(payload.website || '').trim();
    if (website) return json({ok:true}, 201, origin); // honeypot: silently discard bots
    if (!slug.startsWith('/') || name.length < 2 || body.length < 2) return json({error:'Name and comment are required.'}, 400, origin);
    if (/https?:\/\//gi.test(body) && (body.match(/https?:\/\//gi) || []).length > 2) return json({error:'Too many links in one comment.'}, 400, origin);

    const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
    const ipHash = await sha256(`${env.COMMENT_SALT || 'nextjailbreak'}:${ip}`);
    const recent = await env.COMMENTS.prepare(
      "SELECT COUNT(*) AS total FROM comments WHERE ip_hash = ? AND created_at >= datetime('now','-10 minutes')"
    ).bind(ipHash).first();
    if (Number(recent?.total || 0) >= 5) return json({error:'Please wait a few minutes before posting again.'}, 429, origin);

    const result = await env.COMMENTS.prepare(
      "INSERT INTO comments (slug, name, body, ip_hash, approved, created_at) VALUES (?, ?, ?, ?, 1, datetime('now')) RETURNING id, slug, name, body, created_at"
    ).bind(slug, name, body, ipHash).first();
    return json({ok:true, comment:result}, 201, origin);
  }

  if (request.method === 'DELETE' && /^\/api\/comments\/\d+$/.test(url.pathname)) {
    const auth = request.headers.get('Authorization') || '';
    if (!env.ADMIN_TOKEN || auth !== `Bearer ${env.ADMIN_TOKEN}`) return json({error:'Unauthorized.'}, 401, origin);
    const id = Number(url.pathname.split('/').pop());
    await env.COMMENTS.prepare('DELETE FROM comments WHERE id = ?').bind(id).run();
    return json({ok:true}, 200, origin);
  }

  return json({error:'Not found.'}, 404, origin);
}

export default {
  async fetch(request, env) {
    const host = new URL(request.url).hostname.toLowerCase();
    if (host === 'repo.nextjailbreak.com') return repoResponse(request);
    if (host === 'comments.nextjailbreak.com') return commentsResponse(request, env);
    return new Response('Next Jailbreak edge worker', {status:200});
  }
};
