// Staging-only voucher DRAFTS. Never writes imported Windows V6 source tables.
const ALLOWED_TYPES=new Map([
  ['application/pdf','.pdf'],['image/jpeg','.jpg'],['image/png','.png'],
  ['image/heic','.heic'],['image/heif','.heif'],['image/webp','.webp']
]);
function response(data,status=200){
  return new Response(JSON.stringify(data),{
    status,headers:{
      'Content-Type':'application/json; charset=utf-8',
      'Cache-Control':'private, no-store',
      'X-Content-Type-Options':'nosniff'
    }
  });
}
async function digest(bytes){
  const sum=await crypto.subtle.digest('SHA-256',bytes);
  return [...new Uint8Array(sum)].map(x=>x.toString(16).padStart(2,'0')).join('');
}
function validDate(value){
  if(!/^\d{4}-\d\d-\d\d$/.test(value||''))return false;
  const parsed=new Date(value+'T00:00:00Z');
  return !Number.isNaN(parsed.getTime())&&
     parsed.toISOString().slice(0,10)===value &&
     value>='2020-01-01'&&value<='2100-12-31';
}
function limited(value,max) {
  return typeof value==='string' && value.length<=max &&
    !/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/.test(value);
}
async function getDraft(env,id) {
  return env.DB.prepare(
    "SELECT Id,EntityId,Kind,Status,TransactionDate,Currency,AmountMinor,"+
    "Counterparty,Narrative,Reference,AttachmentKey,AttachmentName,AttachmentSha256,"+
    "AttachmentBytes,AttachmentType,CreatedAt FROM WebVoucherDrafts WHERE Id=?"
  ).bind(id).first();
}
export async function listDrafts(env,entityId) {
  const rows=await env.DB.prepare(
    "SELECT Id,Kind,Status,TransactionDate,Currency,AmountMinor,"+
    "Counterparty,Narrative,Reference,AttachmentName,AttachmentSha256,AttachmentBytes,CreatedAt "+
    "FROM WebVoucherDrafts WHERE EntityId=? ORDER BY CreatedAt DESC,Id DESC LIMIT 200"
  ).bind(entityId).all();
  return response({records:rows.results||[],postedToWindows:false});
}
export async function createDraft(request,env,isAllowedEntity) {
  if((request.headers.get('Content-Type')||'').split(';')[0].trim()!=='application/json')
    return response({error:'Expected application/json.'},415);
  const source=await request.text();
  if(source.length>12000)return response({error:'Draft data too large.'},413);
  let data;
  try{data=JSON.parse(source);}catch{return response({error:'Invalid JSON.'},400);}
  const entityId=data?.entityId;
  if(!Number.isSafeInteger(entityId)||entityId<1||
    !await isAllowedEntity(env,entityId))
    return response({error:'Company not available.'},404);
  const kind=data?.kind,date=data?.date,amount=data?.amountMinor;
  if(!['PV','RV'].includes(kind) || !validDate(date) ||
     !Number.isSafeInteger(amount) || amount<1 || amount>100000000000)
    return response({error:'Invalid voucher type, date or amount.'},400);
  const currency=typeof data.currency==='string'?data.currency.toUpperCase():'';
  if(!['QAR','USD','EUR','GBP','PKR','JPY','AED'].includes(currency))
    return response({error:'Unsupported currency.'},400);
  const counterparty=String(data.counterparty||'').trim();
  const narrative=String(data.narrative||'').trim();
  const reference=String(data.reference||'').trim();
  if(!counterparty || !limited(counterparty,160) ||
    !limited(narrative,1200) || !limited(reference,100))
    return response({error:'Counterparty, description or reference invalid.'},400);
  const current=await env.DB.prepare(
    'SELECT COUNT(*) AS n FROM WebVoucherDrafts WHERE EntityId=?'
  ).bind(entityId).first();
  if(Number(current?.n||0)>=200)
    return response({error:'Draft preview limit reached for this entity.'},409);
  const id=crypto.randomUUID();
  await env.DB.prepare(
    "INSERT INTO WebVoucherDrafts(Id,EntityId,Kind,TransactionDate,Currency,"+
    "AmountMinor,Counterparty,Narrative,Reference) VALUES(?,?,?,?,?,?,?,?,?)"
  ).bind(id,entityId,kind,date,currency,amount,counterparty,narrative,reference).run();
  await env.DB.prepare(
    "INSERT INTO WebVoucherDraftAudit(DraftId,Action) VALUES(?,'CREATED')"
  ).bind(id).run();
  return response({ok:true,id,status:'DRAFT',postedToWindows:false},201);
}
export async function attachDraft(request,env,id) {
  if(!env.FILES)return response({error:'Private file storage unavailable.'},503);
  const draft=await getDraft(env,id);
  if(!draft)return response({error:'Draft not found.'},404);
  const type=(request.headers.get('Content-Type')||'').split(';')[0].trim().toLowerCase();
  const ext=ALLOWED_TYPES.get(type);
  if(!ext)return response({error:'Only PDF, JPEG and PNG are supported.'},415);
  const original=request.headers.get('X-File-Name-Encoded')||'';
  if(original.length>2048)return response({error:'Filename too long.'},400);
  let name;
  try{name=decodeURIComponent(original);}catch{return response({error:'Invalid filename.'},400);}
  name=name.trim();
  if(!name||!limited(name,200)||/[/\\]/.test(name))
    return response({error:'Invalid document name.'},400);
  const bytes=await request.arrayBuffer();
  if(!bytes.byteLength || bytes.byteLength>12*1024*1024)
    return response({error:'Document must be between 1 byte and 12 MB.'},413);
  const sha=await digest(bytes);
  if(draft.AttachmentKey) {
    if(draft.AttachmentSha256===sha && Number(draft.AttachmentBytes)===bytes.byteLength)
      return response({ok:true,unchanged:true,sha256:sha,postedToWindows:false});
    return response({error:'A different document is already attached. Drafts are immutable.'},409);
  }
  const key='web-drafts/'+id+'/'+sha+ext;
  const existing=await env.FILES.head(key);
  if(!existing)
    await env.FILES.put(key,bytes,{
      httpMetadata:{contentType:type},
      customMetadata:{sha256:sha,originalName:name,category:'WebVoucherDraft'}
    });
  else if(existing.customMetadata?.sha256!==sha || existing.size!==bytes.byteLength)
    return response({error:'Private document storage conflict.'},409);
  const written=await env.DB.prepare(
    "UPDATE WebVoucherDrafts SET AttachmentKey=?,AttachmentName=?,"+
    "AttachmentSha256=?,AttachmentBytes=?,AttachmentType=? "+
    "WHERE Id=? AND AttachmentKey IS NULL"
  ).bind(key,name,sha,bytes.byteLength,type,id).run();
  if(Number(written.meta?.changes||0)!==1)
    return response({error:'Draft attachment changed concurrently; retry with review.'},409);
  await env.DB.prepare(
    "INSERT INTO WebVoucherDraftAudit(DraftId,Action) VALUES(?,'DOCUMENT_ATTACHED')"
  ).bind(id).run();
  return response({ok:true,sha256:sha,postedToWindows:false});
}
export async function downloadDraft(env,id){
  const draft=await getDraft(env,id);
  if(!draft || !draft.AttachmentKey)return response({error:'Document not found.'},404);
  const object=await env.FILES.get(draft.AttachmentKey);
  if(!object || object.customMetadata?.sha256!==draft.AttachmentSha256)
    return response({error:'Document integrity check failed.'},409);
  // Use inline rendering for approved types and a generic ASCII filename,
  // avoiding header encoding errors from Unicode source document names.
  return new Response(object.body,{headers:{
    'Content-Type':draft.AttachmentType||'application/octet-stream',
    'Content-Disposition':'attachment; filename="staging-draft-document"',
    'Cache-Control':'private, no-store',
    'X-Content-Type-Options':'nosniff',
    'X-Frame-Options':'DENY',
    'X-Document-Sha256':draft.AttachmentSha256
  }});
}
