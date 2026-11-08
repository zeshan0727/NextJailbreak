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

// Private, opt-in location test. No location is collected on GET or page load.
// The caller generates a 256-bit bearer capability and only its SHA-256 is stored.
function locationJson(data, status, origin) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store, max-age=0',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
      ...cors(origin)
    }
  });
}

// Only coarse, browser-visible device characteristics are accepted.
// No fingerprint IDs, serial numbers, IP addresses, cookies or complete user agents.
function normalizeDeviceSummary(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const allowed = ['deviceType','os','browser','screen','language','timezone','touch'];
  const summary = {};
  for (const key of allowed) {
    const value = raw[key];
    if (value === undefined || value === null) continue;
    if (typeof value !== 'string' || value.length > 100) return null;
    summary[key] = value.slice(0,100);
  }
  return Object.keys(summary).length ? summary : null;
}
function parseDeviceSummary(value) {
  try { return typeof value === 'string' ? JSON.parse(value) : null; }
  catch { return null; }
}
const LOCATION_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function locationAdminResponse(request, env, url, payload, reply) {
  // A separately configured, high-entropy Worker secret is required. No public list.
  const configured = String(env.LOCATION_ADMIN_TOKEN || '');
  if (configured.length < 32) return reply({error:'Private dashboard is not configured.'},503);
  const rawHeader = request.headers.get('Authorization') || '';
  const supplied = rawHeader.startsWith('Bearer ') ? rawHeader.slice(7) : '';
  if (supplied.length !== configured.length || await sha256(supplied) !== await sha256(configured)) {
    return reply({error:'Invalid admin access key.'},401);
  }
  const path = url.pathname;
  // Keep the dashboard metadata-only until a specific entry is opened.
  if (path === '/api/location-test/admin/list') {
    const rows = await env.COMMENTS.prepare(
      "SELECT t.id,t.created_at,t.expires_at,d.summary_json FROM location_tests t LEFT JOIN location_test_devices d ON d.id=t.id WHERE t.expires_at > datetime('now') ORDER BY t.created_at DESC LIMIT 100"
    ).all();
    return reply({ok:true,sessions:(rows.results || []).map(row=>({
      id:row.id,createdAt:row.created_at,expiresAt:row.expires_at,
      device:parseDeviceSummary(row.summary_json)
    }))});
  }
  const id=String(payload.id || '');
  if (!LOCATION_ID_PATTERN.test(id)) return reply({error:'Invalid test ID.'},400);
  if (path === '/api/location-test/admin/detail') {
    const row=await env.COMMENTS.prepare(
      "SELECT t.latitude,t.longitude,t.accuracy_m,t.created_at,t.expires_at,d.summary_json FROM location_tests t LEFT JOIN location_test_devices d ON d.id=t.id WHERE t.id=? AND t.expires_at > datetime('now')"
    ).bind(id).first();
    if (!row) return reply({error:'Test not found or expired.'},404);
    return reply({ok:true,session:{
      id,latitude:row.latitude,longitude:row.longitude,accuracyMeters:row.accuracy_m,
      createdAt:row.created_at,expiresAt:row.expires_at,
      device:parseDeviceSummary(row.summary_json)
    }});
  }
  if (path === '/api/location-test/admin/delete') {
    await env.COMMENTS.prepare("DELETE FROM location_test_devices WHERE id=?").bind(id).run();
    const deletion=await env.COMMENTS.prepare("DELETE FROM location_tests WHERE id=?").bind(id).run();
    if (!deletion?.meta?.changes) return reply({error:'Test not found.'},404);
    return reply({ok:true});
  }
  return reply({error:'Not found.'},404);
}

async function locationTestResponse(request, env, url, origin) {
  const reply = (data, status=200) => locationJson(data, status, origin);
  if (request.method !== 'POST') return reply({error:'Only POST is supported.'}, 405);
  if (!ALLOWED_ORIGINS.has(origin) || !origin.startsWith('https://nextjailbreak.com') && !origin.startsWith('https://www.nextjailbreak.com')) {
    return reply({error:'Origin is not permitted.'}, 403);
  }
  if (!env.COMMENTS) return reply({error:'Private test storage is not configured.'}, 503);
  if (!(request.headers.get('Content-Type') || '').startsWith('application/json')) {
    return reply({error:'JSON requests only.'}, 415);
  }
  let payload;
  try {
    const raw = await request.text();
    if (raw.length > 2048) return reply({error:'Request too large.'}, 413);
    payload = JSON.parse(raw);
  } catch { return reply({error:'Invalid JSON.'}, 400); }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return reply({error:'Invalid payload.'}, 400);

  if (url.pathname.startsWith('/api/location-test/admin/')) {
    return locationAdminResponse(request, env, url, payload, reply);
  }

  const id = String(payload.id || '');
  if (!LOCATION_ID_PATTERN.test(id)) {
    return reply({error:'Invalid test identifier.'}, 400);
  }
  // Opportunistic expiry cleanup; no unauthenticated retrieval/list endpoint exists.
  await env.COMMENTS.prepare("DELETE FROM location_test_devices WHERE id IN (SELECT id FROM location_tests WHERE expires_at <= datetime('now'))").run();
  await env.COMMENTS.prepare("DELETE FROM location_tests WHERE expires_at <= datetime('now')").run();

  if (url.pathname === '/api/location-test/create') {
    const tokenHash = String(payload.tokenHash || '').toLowerCase();
    const latitude = Number(payload.latitude), longitude = Number(payload.longitude);
    const accuracy = Number(payload.accuracyMeters);
    if (payload.consent !== true || !/^[0-9a-f]{64}$/.test(tokenHash) ||
      !Number.isFinite(latitude) || Math.abs(latitude)>90 ||
      !Number.isFinite(longitude) || Math.abs(longitude)>180 ||
      !Number.isFinite(accuracy) || accuracy < 0 || accuracy > 100000) {
      return reply({error:'Coordinates and explicit consent are required.'}, 400);
    }
    // Conservative cap to limit storage abuse during the first private test.
    const count = await env.COMMENTS.prepare(
      "SELECT COUNT(*) AS total FROM location_tests WHERE created_at >= datetime('now', '-1 hour')"
    ).first();
    if (Number(count?.total || 0) >= 50) return reply({error:'Test capacity reached. Try again later.'}, 429);
    const device = payload.device === undefined ? null : normalizeDeviceSummary(payload.device);
    if (payload.device !== undefined && !device) return reply({error:'Invalid device summary.'},400);
    const batch = [env.COMMENTS.prepare(
      "INSERT OR IGNORE INTO location_tests(id,token_hash,latitude,longitude,accuracy_m,created_at,expires_at) VALUES(?,?,?,?,?,datetime('now'),datetime('now','+24 hours'))"
    ).bind(id, tokenHash, latitude, longitude, accuracy)];
    if (device) batch.push(env.COMMENTS.prepare(
      "INSERT INTO location_test_devices(id,summary_json) VALUES(?,?)"
    ).bind(id,JSON.stringify(device)));
    const results = await env.COMMENTS.batch(batch);
    if (!results[0]?.meta?.changes) return reply({error:'Duplicate test identifier.'}, 409);
    return reply({ok:true,id,retentionHours:24}, 201);
  }

  const token = String(payload.token || '');
  if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return reply({error:'Private key required.'}, 401);
  const tokenHash = await sha256(token);

  if (url.pathname === '/api/location-test/read') {
    const row = await env.COMMENTS.prepare(
      "SELECT t.latitude,t.longitude,t.accuracy_m,t.created_at,t.expires_at,d.summary_json FROM location_tests t LEFT JOIN location_test_devices d ON d.id=t.id WHERE t.id=? AND t.token_hash=? AND t.expires_at>datetime('now')"
    ).bind(id, tokenHash).first();
    if (!row) return reply({error:'Record missing, expired, or private key invalid.'}, 404);
    return reply({ok:true,location:{
      latitude:row.latitude,longitude:row.longitude,accuracyMeters:row.accuracy_m,
      createdAt:row.created_at,expiresAt:row.expires_at,device:parseDeviceSummary(row.summary_json)
    }});
  }
  if (url.pathname === '/api/location-test/delete') {
    const result = await env.COMMENTS.prepare(
      "DELETE FROM location_tests WHERE id=? AND token_hash=?"
    ).bind(id, tokenHash).run();
    if (result?.meta?.changes) await env.COMMENTS.prepare("DELETE FROM location_test_devices WHERE id=?").bind(id).run();
    if (!result?.meta?.changes) return reply({error:'Record not found.'}, 404);
    return reply({ok:true});
  }
  return reply({error:'Not found.'}, 404);
}

async function commentsResponse(request, env) {
  const url = new URL(request.url);
  const origin = request.headers.get('Origin') || '';
  if (request.method === 'OPTIONS') return new Response(null, {status:204, headers:cors(origin)});
  if (url.pathname.startsWith('/api/location-test/')) return locationTestResponse(request, env, url, origin);

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
  async scheduled(event, env, ctx) {
    if (env.COMMENTS) ctx.waitUntil((async()=>{
      await env.COMMENTS.prepare("DELETE FROM location_test_devices WHERE id IN (SELECT id FROM location_tests WHERE expires_at <= datetime('now'))").run();
      await env.COMMENTS.prepare("DELETE FROM location_tests WHERE expires_at <= datetime('now')").run();
    })());
  },
  async fetch(request, env) {
    const host = new URL(request.url).hostname.toLowerCase();
    if (host === 'repo.nextjailbreak.com') return repoResponse(request);
    if (host === 'comments.nextjailbreak.com') return commentsResponse(request, env);
    return new Response('Next Jailbreak edge worker', {status:200});
  }
};
