const ALLOWED_ORIGINS = new Set([
  'https://nextjailbreak.com',
  'https://www.nextjailbreak.com',
  'https://accounts.nextjailbreak.com'
]);

function cors(origin) {
  const allow = ALLOWED_ORIGINS.has(origin) ? origin : 'https://nextjailbreak.com';
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,HEAD,OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization,Content-Type,X-File-Name,X-File-Category,X-Record-Type,X-Record-Id,X-Entity-Id',
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

function cleanIdentifier(value) {
  const s = String(value || '');
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(s)) throw new Error('Invalid SQL identifier.');
  return s;
}

async function sha256Hex(value) {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2,'0')).join('');
}

async function isAuthorized(request, env) {
  if (!env.OWNER_TOKEN) return {ok:false, status:503, error:'Owner authentication is not configured yet.'};
  const auth = request.headers.get('Authorization') || '';
  if (!auth.startsWith('Bearer ')) return {ok:false, status:401, error:'Authorization required.'};
  const supplied = auth.slice(7).trim();
  if (!supplied) return {ok:false, status:401, error:'Authorization required.'};
  const pair = await Promise.all([sha256Hex(supplied), sha256Hex(env.OWNER_TOKEN)]);
  return pair[0] === pair[1] ? {ok:true} : {ok:false, status:401, error:'Invalid authorization.'};
}

async function audit(env, action, resource = '', resourceId = '', details = {}) {
  try {
    await env.DB.prepare("INSERT INTO WebAuditLog(Action,Resource,ResourceId,DetailsJson,CreatedAt) VALUES(?,?,?,?,datetime('now'))")
      .bind(action, resource, String(resourceId || ''), JSON.stringify(details || {})).run();
  } catch {}
}

async function health(env) {
  let db = false;
  let files = false;
  try {
    const row = await env.DB.prepare('SELECT 1 AS ok').first();
    db = Number(row?.ok || 0) === 1;
  } catch {}
  if (env.FILES) {
    try {
      await env.FILES.head('__healthcheck__');
      files = true;
    } catch {
      files = true;
    }
  }
  return {ok: db, service:'next-accountant-api', version:'0.1.1', database:db, files};
}

async function listTables(env) {
  const result = await env.DB.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all();
  return (result.results || []).map(r => r.name);
}

async function tableColumns(env, table) {
  cleanIdentifier(table);
  const result = await env.DB.prepare('PRAGMA table_info(' + table + ')').all();
  return (result.results || []).map(r => String(r.name));
}

async function applySchema(request, env, origin) {
  const body = await request.json();
  const sql = String(body?.sql || '');
  if (!sql || sql.length > 250000) return json({error:'Schema SQL is missing or too large.'},400,origin);
  await env.DB.exec(sql);
  const version = Number(body?.sourceSchemaVersion || 0);
  await env.DB.prepare("INSERT OR REPLACE INTO WebMeta(Key,Value,UpdatedAt) VALUES('windows_source_schema_version',?,datetime('now'))")
    .bind(String(version)).run();
  await audit(env,'apply_schema','database','',{sourceSchemaVersion:version,bytes:sql.length});
  return json({ok:true, sourceSchemaVersion:version},200,origin);
}


function decodeSqliteValue(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const keys = Object.keys(value);
    if (keys.length !== 1 || keys[0] !== '$base64' || typeof value.$base64 !== 'string')
      throw new Error('Unsupported structured SQLite value.');
    if (value.$base64.length > 2_500_000) throw new Error('SQLite BLOB exceeds safe import size.');
    const binary = atob(value.$base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    if (bytes.length > 1_800_000) throw new Error('SQLite BLOB exceeds safe D1 value size.');
    return bytes;
  }
  return value ?? null;
}

async function importBatch(request, env, origin) {
  const body = await request.json();
  const table = cleanIdentifier(body?.table);
  const rows = Array.isArray(body?.rows) ? body.rows : [];
  if (!rows.length) return json({ok:true, imported:0},200,origin);
  if (rows.length > 100) return json({error:'Maximum 100 rows per import batch.'},400,origin);

  const allowed = new Set(await tableColumns(env, table));
  if (!allowed.size) return json({error:'Target table does not exist.'},404,origin);

  const statements = [];
  for (const row of rows) {
    if (!row || typeof row !== 'object' || Array.isArray(row)) continue;
    const columns = Object.keys(row).filter(k => allowed.has(k));
    if (!columns.length) continue;
    columns.forEach(cleanIdentifier);
    const marks = columns.map(() => '?').join(',');
    const sql = 'INSERT INTO ' + table + '(' + columns.join(',') + ') VALUES(' + marks + ')';
    statements.push(env.DB.prepare(sql).bind(...columns.map(c => decodeSqliteValue(row[c]))));
  }
  if (!statements.length) return json({ok:true, imported:0},200,origin);
  await env.DB.batch(statements);
  await audit(env,'import_batch',table,'',{rows:statements.length});
  return json({ok:true, imported:statements.length},200,origin);
}

async function exportTable(request, env, origin) {
  const url = new URL(request.url);
  const table = cleanIdentifier(url.searchParams.get('table'));
  const limit = Math.max(1, Math.min(500, Number(url.searchParams.get('limit') || 250)));
  const offset = Math.max(0, Number(url.searchParams.get('offset') || 0));
  const columns = await tableColumns(env, table);
  if (!columns.length) return json({error:'Table does not exist.'},404,origin);
  const result = await env.DB.prepare('SELECT * FROM ' + table + ' LIMIT ? OFFSET ?').bind(limit,offset).all();
  return json({table,limit,offset,rows:result.results || []},200,origin);
}

async function tableCounts(env, origin) {
  const tables = await listTables(env);
  const statements = tables.map(t => env.DB.prepare('SELECT ? AS name, COUNT(*) AS count FROM ' + cleanIdentifier(t)).bind(t));
  const result = statements.length ? await env.DB.batch(statements) : [];
  return json({tables: result.map((x,i) => ({name:tables[i], count:Number(x.results?.[0]?.count || 0)}))},200,origin);
}

function objectKeyFromUrl(url) {
  const prefix = '/api/files/';
  const raw = url.pathname.startsWith(prefix) ? url.pathname.slice(prefix.length) : '';
  const key = decodeURIComponent(raw);
  if (!key || key.startsWith('/') || key.includes('..')) throw new Error('Invalid object key.');
  return key;
}

async function filePut(request, env, origin) {
  if (!env.FILES) return json({error:'Private R2 file storage is not configured yet.'},503,origin);
  if (!env.FILES) return json({error:'Private R2 file storage is not configured yet.'},503,origin);
  const url = new URL(request.url);
  const key = objectKeyFromUrl(url);
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (!bytes.length) return json({error:'Empty file.'},400,origin);
  if (bytes.length > 50 * 1024 * 1024) return json({error:'Maximum file size is 50 MB.'},413,origin);
  const hash = await sha256Hex(bytes);
  const contentType = request.headers.get('Content-Type') || 'application/octet-stream';
  const originalName = request.headers.get('X-File-Name') || key.split('/').pop() || '';
  const category = request.headers.get('X-File-Category') || '';
  const recordType = request.headers.get('X-Record-Type') || '';
  const recordId = request.headers.get('X-Record-Id') || '';
  const entityIdRaw = request.headers.get('X-Entity-Id');
  const entityId = entityIdRaw && /^\d+$/.test(entityIdRaw) ? Number(entityIdRaw) : null;

  await env.FILES.put(key, bytes, {
    httpMetadata:{contentType},
    customMetadata:{originalName,sha256:hash,category,recordType,recordId}
  });
  await env.DB.prepare("INSERT OR REPLACE INTO WebFileIndex(ObjectKey,OriginalName,ContentType,SizeBytes,Sha256,EntityId,Category,RecordType,RecordId,UploadedAt) VALUES(?,?,?,?,?,?,?,?,?,datetime('now'))")
    .bind(key,originalName,contentType,bytes.length,hash,entityId,category,recordType,recordId).run();
  await audit(env,'file_put','r2',key,{bytes:bytes.length,sha256:hash,recordType,recordId});
  return json({ok:true,key,size:bytes.length,sha256:hash},200,origin);
}

async function fileGet(request, env, origin) {
  if (!env.FILES) return json({error:'Private R2 file storage is not configured yet.'},503,origin);
  if (!env.FILES) return json({error:'Private R2 file storage is not configured yet.'},503,origin);
  const key = objectKeyFromUrl(new URL(request.url));
  const object = await env.FILES.get(key);
  if (!object) return json({error:'File not found.'},404,origin);
  const headers = new Headers(cors(origin));
  object.writeHttpMetadata(headers);
  headers.set('ETag',object.httpEtag);
  headers.set('Cache-Control','private, no-store');
  const filename = (object.customMetadata?.originalName || key.split('/').pop() || 'file').replace(/"/g,'');
  headers.set('Content-Disposition','attachment; filename="' + filename + '"');
  return new Response(request.method === 'HEAD' ? null : object.body,{headers});
}

async function fileDelete(request, env, origin) {
  if (!env.FILES) return json({error:'Private R2 file storage is not configured yet.'},503,origin);
  if (!env.FILES) return json({error:'Private R2 file storage is not configured yet.'},503,origin);
  const key = objectKeyFromUrl(new URL(request.url));
  await env.FILES.delete(key);
  await env.DB.prepare('DELETE FROM WebFileIndex WHERE ObjectKey=?').bind(key).run();
  await audit(env,'file_delete','r2',key,{});
  return json({ok:true,key},200,origin);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin') || '';
    if (request.method === 'OPTIONS') return new Response(null,{status:204,headers:cors(origin)});

    if (request.method === 'GET' && url.pathname === '/health') {
      const result = await health(env);
      return json(result,result.ok?200:503,origin);
    }

    const auth = await isAuthorized(request,env);
    if (!auth.ok) return json({error:auth.error},auth.status,origin);

    try {
      if (request.method === 'GET' && url.pathname === '/api/summary') {
        const tables = await listTables(env);
        return json({ok:true,tables:tables.length,aiConfigured:Boolean(env.OPENAI_API_KEY),filesBucket:Boolean(env.FILES)},200,origin);
      }
      if (request.method === 'GET' && url.pathname === '/api/admin/tables') return json({tables:await listTables(env)},200,origin);
      if (request.method === 'GET' && url.pathname === '/api/admin/counts') return await tableCounts(env,origin);
      if (request.method === 'POST' && url.pathname === '/api/admin/apply-schema') return await applySchema(request,env,origin);
      if (request.method === 'POST' && url.pathname === '/api/admin/import-batch') return await importBatch(request,env,origin);
      if (request.method === 'GET' && url.pathname === '/api/admin/export-table') return await exportTable(request,env,origin);
      if (url.pathname.startsWith('/api/files/')) {
        if (request.method === 'PUT') return await filePut(request,env,origin);
        if (request.method === 'GET' || request.method === 'HEAD') return await fileGet(request,env,origin);
        if (request.method === 'DELETE') return await fileDelete(request,env,origin);
      }
      return json({error:'Not found.'},404,origin);
    } catch (error) {
      await audit(env,'error',url.pathname,'',{message:String(error?.message || error)});
      return json({error:'Request failed.',detail:String(error?.message || error)},500,origin);
    }
  }
};
