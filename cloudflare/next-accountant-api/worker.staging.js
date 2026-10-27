import { handleWeb, createWebTicket } from './web-readonly.js';
import { financeFingerprint } from './financial-fingerprint.js';
import { financialBreakdown } from './financial-breakdown.js';
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
    'Access-Control-Allow-Headers': 'Authorization,Content-Type,X-File-Name,X-File-Category,X-Record-Type,X-Record-Id,X-File-Name-Encoded,X-Record-Id-Encoded,X-Entity-Id,X-Expected-Sha256',
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
      // A failed R2 binding must never be reported as healthy.
      files = false;
    }
  }
  return {ok: db && files, service:'next-accountant-api-staging', version:'0.2.0', environment:'staging', database:db, files};
}

async function listTables(env) {
  const result = await env.DB.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT GLOB '_cf_*' ORDER BY name").all();
  return (result.results || []).map(r => r.name);
}

async function tableColumns(env, table) {
  cleanIdentifier(table);
  const result = await env.DB.prepare('PRAGMA table_info(' + table + ')').all();
  return (result.results || []).map(r => String(r.name));
}

// The Windows migrator sends a PRAGMA preamble followed by multiline SQL DDL.
// D1.exec() splits at newlines, including newlines inside CREATE TABLE.
// Parse complete definitions and execute each as a prepared statement instead.
function splitSqlStatements(sql) {
  const result = [];
  let start = 0, quote = '', comment = '';
  for (let i = 0; i < sql.length; i++) {
    const ch = sql[i], next = sql[i + 1];
    if (comment === 'line') {
      if (ch === '\n') comment = '';
      continue;
    }
    if (comment === 'block') {
      if (ch === '*' && next === '/') {comment = ''; i++;}
      continue;
    }
    if (quote) {
      const closer = quote === '[' ? ']' : quote;
      if (ch === closer) {
        if (next === closer) i++;
        else quote = '';
      }
      continue;
    }
    if (ch === '-' && next === '-') {comment = 'line'; i++; continue;}
    if (ch === '/' && next === '*') {comment = 'block'; i++; continue;}
    if (ch === "'" || ch === '"' || ch === '\x60' || ch === '[') {quote = ch; continue;}
    if (ch === ';') {
      const statement = sql.slice(start, i).trim();
      if (statement) result.push(statement);
      start = i + 1;
    }
  }
  if (quote || comment === 'block') throw new Error('SQL definition has an unterminated quote or comment.');
  const remaining = sql.slice(start).trim();
  if (remaining) result.push(remaining);
  return result;
}
function schemaObject(statement) {
  const match = statement.match(/^\s*CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?:IF\s+NOT\s+EXISTS\s+)?("(?:""|[^"])+"|\x60(?:\x60\x60|[^\x60])+\x60|\[(?:\]\]|[^\]])+\]|'(?:''|[^'])+'|[A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|ON\b)/i);
  if (!match) return null;
  const type = match[2].toLowerCase();
  const identifier = match[3];
  const first = identifier[0];
  const name = first === '"' ? identifier.slice(1,-1).replace(/""/g,'"') :
    first === '\x60' ? identifier.slice(1,-1).replace(/\x60\x60/g,'\x60') :
    first === '[' ? identifier.slice(1,-1).replace(/\]\]/g,']') :
    first === "'" ? identifier.slice(1,-1).replace(/''/g,"'") : identifier;
  return name && !name.toLowerCase().startsWith('sqlite_') &&
    !name.toLowerCase().startsWith('_cf_') ? {type,name} : null;
}
function normalizedSourceDdl(value) {
  return String(value || '').trim().replace(/;\s*$/,'')
    .replace(/\bIF\s+NOT\s+EXISTS\b/ig,'').replace(/\s+/g,' ').trim();
}
async function applySchema(request, env, origin) {
  const body = await request.json();
  const sql = String(body?.sql || '');
  if (!sql || sql.length > 250000) return json({error:'Schema SQL is missing or too large.'},400,origin);
  const statements = splitSqlStatements(sql);
  if (!statements.length || !/^\s*PRAGMA\s+foreign_keys\s*=\s*ON\s*$/i.test(statements[0]))
    return json({error:'Expected foreign-key preamble from the verified Windows migrator.'},400,origin);
  const ddl = statements.slice(1);
  if (!ddl.length || ddl.length > 8)
    return json({error:'Expected between one and eight source schema definitions.'},400,origin);
  const objects = ddl.map(schemaObject);
  if (objects.some(x => !x))
    return json({error:'Only CREATE TABLE and CREATE INDEX definitions are permitted.'},400,origin);
  const existing = [];
  for (let i = 0; i < ddl.length; i++) {
    const definition = objects[i];
    const row = await env.DB.prepare(
      "SELECT sql FROM sqlite_master WHERE type=? AND name=?"
    ).bind(definition.type,definition.name).first();
    if (row && normalizedSourceDdl(row.sql) !== normalizedSourceDdl(ddl[i]))
      return json({error:'Conflicting existing staging schema definition; manual review required.',object:definition.name},409,origin);
    existing.push(Boolean(row));
  }
  let created = 0, reused = 0;
  for (let i = 0; i < ddl.length; i++) {
    if (existing[i]) {reused++; continue;}
    await env.DB.prepare(ddl[i]).run();
    created++;
  }
  const version = Number(body?.sourceSchemaVersion || 0);
  await env.DB.prepare("INSERT OR REPLACE INTO WebMeta(Key,Value,UpdatedAt) VALUES('windows_source_schema_version',?,datetime('now'))")
    .bind(String(version)).run();
  await audit(env,'apply_schema','database','',{sourceSchemaVersion:version,statements:ddl.length,created,reused});
  return json({ok:true,sourceSchemaVersion:version,created,reused},200,origin);
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

async function tableCounts(env, origin, url) {
  const tables = await listTables(env);
  const limit = 20;
  const page = Number(url.searchParams.get('page') ?? '0');
  if (!Number.isSafeInteger(page) || page < 0 || page > 100000)
    return json({error:'Invalid page.'},400,origin);
  const selected = tables.slice(page * limit,(page+1)*limit);
  const output=[];
  for (const name of selected) {
    const safe=cleanIdentifier(name);
    try {
      const value = await env.DB.prepare('SELECT COUNT(*) AS total FROM "' + safe + '"').first();
      output.push({name:safe,count:Number(value?.total ?? 0)});
    } catch (error) {
      return json({error:'Count query rejected for table '+safe,detail:String(error?.message || error)},500,origin);
    }
  }
  return json({page,hasMore:(page+1)*limit < tables.length,tables:output},200,origin);
}

function objectKeyFromUrl(url) {
  const prefix = '/api/files/';
  const raw = url.pathname.startsWith(prefix) ? url.pathname.slice(prefix.length) : '';
  const key = decodeURIComponent(raw);
  if (!key || key.startsWith('/') || key.includes('..')) throw new Error('Invalid object key.');
  return key;
}

// The Windows client percent-encodes UTF-8 metadata into ASCII-only HTTP
// headers. Decode only the explicitly marked headers; older callers are unchanged.
function fileMetadataHeader(request, encodedKey, legacyKey, fallback = '') {
  const encoded = request.headers.get(encodedKey);
  if (encoded === null) return request.headers.get(legacyKey) || fallback;
  if (encoded.length > 16000)
    throw new URIError('Encoded file metadata exceeds the safe header size.');
  const decoded = decodeURIComponent(encoded);
  if (/[\u0000-\u001f\u007f]/.test(decoded))
    throw new URIError('File metadata contains forbidden control characters.');
  return decoded;
}

async function filePut(request, env, origin) {
  if (!env.FILES) return json({error:'Private R2 file storage is not configured yet.'},503,origin);
  const url = new URL(request.url);
  const key = objectKeyFromUrl(url);
  const bytes = new Uint8Array(await request.arrayBuffer());
  // Empty files (for example an audit write.lock) are valid V6 backup entries.
  // Require their manifest SHA-256 exactly as for nonempty R2 objects.
  if (bytes.length > 50 * 1024 * 1024) return json({error:'Maximum file size is 50 MB.'},413,origin);
  const hash = await sha256Hex(bytes);
  const expected = request.headers.get('X-Expected-Sha256');
  if (!expected || !/^[a-f0-9]{64}$/i.test(expected) || expected.toLowerCase() !== hash)
    return json({error:'File SHA-256 mismatch or missing expected digest.'},400,origin);
  const existing = await env.FILES.head(key);
  if (existing) {
    if (existing.customMetadata?.sha256 === hash && existing.size === bytes.length) {
      // If R2 upload succeeded but the D1 index insert failed, a safe retry
      // must repair the index rather than silently accepting orphaned storage.
      const indexed = await env.DB.prepare('SELECT Sha256,SizeBytes FROM WebFileIndex WHERE ObjectKey=?').bind(key).first();
      if (indexed && (String(indexed.Sha256).toLowerCase() !== hash ||
          Number(indexed.SizeBytes) !== bytes.length))
        return json({error:'File index conflicts with verified R2 object.'},409,origin);
      if (!indexed) {
        const metadata = existing.customMetadata || {};
        const rawEntityId = request.headers.get('X-Entity-Id');
        const entityId = rawEntityId && /^\d+$/.test(rawEntityId) ? Number(rawEntityId) : null;
        await env.DB.prepare("INSERT OR IGNORE INTO WebFileIndex(ObjectKey,OriginalName,ContentType,SizeBytes,Sha256,EntityId,Category,RecordType,RecordId,UploadedAt) VALUES(?,?,?,?,?,?,?,?,?,datetime('now'))")
          .bind(key,
            metadata.originalName || fileMetadataHeader(request,'X-File-Name-Encoded','X-File-Name',key.split('/').pop() || ''),
            existing.httpMetadata?.contentType || request.headers.get('Content-Type') || 'application/octet-stream',
            bytes.length, hash, entityId,
            metadata.category || request.headers.get('X-File-Category') || '',
            metadata.recordType || request.headers.get('X-Record-Type') || '',
            metadata.recordId || fileMetadataHeader(request,'X-Record-Id-Encoded','X-Record-Id')).run();
        await audit(env,'file_index_repaired','r2',key,{sha256:hash});
      }
      return json({ok:true,unchanged:true,indexRepaired:!indexed,key,size:bytes.length,sha256:hash},200,origin);
    }
    return json({error:'Existing file key has a different payload. Refusing overwrite.'},409,origin);
  }
  const contentType = request.headers.get('Content-Type') || 'application/octet-stream';
  const originalName = fileMetadataHeader(request,'X-File-Name-Encoded','X-File-Name',key.split('/').pop() || '');
  const category = request.headers.get('X-File-Category') || '';
  const recordType = request.headers.get('X-Record-Type') || '';
  const recordId = fileMetadataHeader(request,'X-Record-Id-Encoded','X-Record-Id');
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
  const key = objectKeyFromUrl(new URL(request.url));
  const object = await env.FILES.get(key);
  if (!object) return json({error:'File not found.'},404,origin);
  const headers = new Headers(cors(origin));
  object.writeHttpMetadata(headers);
  headers.set('ETag',object.httpEtag);
  headers.set('Cache-Control','private, no-store');
  headers.set('X-File-Sha256',object.customMetadata?.sha256 || '');
  const filename = (object.customMetadata?.originalName || key.split('/').pop() || 'file').replace(/"/g,'');
  headers.set('Content-Disposition','attachment; filename="' + filename + '"');
  return new Response(request.method === 'HEAD' ? null : object.body,{headers});
}

async function fileDelete(request, env, origin) {
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

    if (env.MIGRATION_ENV !== 'staging') return json({error:'Staging worker configuration missing.'},503,origin);

    // User-facing staging records never use the migration token in the browser.
    // The native Windows app exchanges it for a 90-second, single-use ticket;
    // the browser receives only an HttpOnly read-only session cookie.
    if (url.pathname === '/api/web/session/start') {
      const ownerAuth=await isAuthorized(request,env);
      if (!ownerAuth.ok) return json({error:ownerAuth.error},ownerAuth.status,origin);
      return await createWebTicket(request,env);
    }
    if (url.pathname === '/web' || url.pathname.startsWith('/web/') ||
        url.pathname.startsWith('/api/web/')) {
      return await handleWeb(request,env);
    }
    const auth = await isAuthorized(request,env);
    if (!auth.ok) return json({error:auth.error},auth.status,origin);

    try {
      if (request.method === 'GET' && url.pathname === '/api/summary') {
        const tables = await listTables(env);
        return json({ok:true,tables:tables.length,aiConfigured:Boolean(env.OPENAI_API_KEY),filesBucket:Boolean(env.FILES)},200,origin);
      }
      if (request.method === 'GET' && url.pathname === '/api/admin/financial-breakdown')
        return await financialBreakdown(request,env);
      if (request.method === 'GET' && url.pathname === '/api/admin/financial-fingerprint')
        return await financeFingerprint(request,env);
      if (request.method === 'GET' && url.pathname === '/api/admin/tables') return json({tables:await listTables(env)},200,origin);
      if (request.method === 'GET' && url.pathname === '/api/admin/counts') return await tableCounts(env,origin,url);
      if (request.method === 'POST' && url.pathname === '/api/admin/apply-schema') return await applySchema(request,env,origin);
      if (request.method === 'POST' && url.pathname === '/api/admin/import-batch') return await importBatch(request,env,origin);
      if (request.method === 'GET' && url.pathname === '/api/admin/export-table') return await exportTable(request,env,origin);
      if (url.pathname.startsWith('/api/files/')) {
        if (request.method === 'PUT') return await filePut(request,env,origin);
        if (request.method === 'GET' || request.method === 'HEAD') return await fileGet(request,env,origin);
        if (request.method === 'DELETE') return json({error:'Destructive file operations are disabled for staging imports.'},405,origin);
      }
      return json({error:'Not found.'},404,origin);
    } catch (error) {
      await audit(env,'error',url.pathname,'',{message:String(error?.message || error)});
      return json({error:'Request failed.',detail:String(error?.message || error)},500,origin);
    }
  }
};
