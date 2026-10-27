// Browse/download original migrated Windows manager-report files only.
// All prefixes are derived server-side from one of the seven managed entities.
function reply(data,status=200) {
  return new Response(JSON.stringify(data),{status,headers:{
    'Content-Type':'application/json; charset=utf-8',
    'Cache-Control':'private, no-store',
    'X-Content-Type-Options':'nosniff'
  }});
}
function managedReportPrefix(name) {
  const s=String(name||'').toLowerCase();
  let folder='';
  if(s.includes('stone'))folder='Stone_Cafe';
  else if(s.includes('graphitees'))folder='The_Graphitees';
  else if(s.includes('barjous'))folder='Barjous';
  else if(s.includes('levante')&&s.includes('bags'))folder='Levante_Bags';
  else if(s.includes('atelier'))folder='Atelier_Home';
  else if(s.includes('erada'))folder='Erada_Fitness';
  else if(s.includes('north sports'))folder='North_Sports';
  if(!folder)return null;
  return 'business/Audit/LegacyImported/Reports/Manager/'+folder+'/';
}
async function entityReportPrefix(env,entityId) {
  const r=await env.DB.prepare("SELECT Name FROM Entities WHERE Id=?")
    .bind(entityId).first();
  return managedReportPrefix(r?.Name);
}
export async function listWindowsReports(env,entityId) {
  const prefix=await entityReportPrefix(env,entityId);
  if(!prefix)return reply({error:'Company report archive is not configured.'},404);
  const result=await env.DB.prepare(
    "SELECT ObjectKey,OriginalName,ContentType,SizeBytes,Sha256 FROM WebFileIndex "+
    "WHERE substr(ObjectKey,1,length(?))=? AND Category='V6BusinessBackup' "+
    "ORDER BY ObjectKey DESC LIMIT 250"
  ).bind(prefix,prefix).all();
  return reply({files:result.results||[],source:'Original Windows V6 backup',
    regenerated:false,approvedFinancialReport:false});
}
export async function downloadWindowsReport(env,entityId,key) {
  if(typeof key!=='string'||key.length>1800||!env.FILES)
    return reply({error:'Invalid report request.'},400);
  const prefix=await entityReportPrefix(env,entityId);
  if(!prefix||!key.startsWith(prefix))
    return reply({error:'Report is not accessible for this company.'},404);
  const doc=await env.DB.prepare(
    "SELECT ObjectKey,OriginalName,ContentType,SizeBytes,Sha256 FROM WebFileIndex "+
    "WHERE ObjectKey=? AND Category='V6BusinessBackup'"
  ).bind(key).first();
  if(!doc)return reply({error:'Report file not found.'},404);
  const object=await env.FILES.get(key);
  if(!object || object.customMetadata?.sha256?.toLowerCase()!==String(doc.Sha256).toLowerCase() ||
     object.size!==doc.SizeBytes)
    return reply({error:'Stored original report failed integrity check.'},409);
  const safeName=String(doc.OriginalName||'report')
    .replace(/[^\x20-\x7e]/g,'_').replace(/["\\]/g,'_');
  const original=String(doc.OriginalName||'report');
  const encoded=encodeURIComponent(original);
  return new Response(object.body,{headers:{
    'Content-Type':doc.ContentType||'application/octet-stream',
    'Content-Disposition':'attachment; filename="'+safeName+'"; filename*=UTF-8'+String.fromCharCode(39,39)+encoded,
    'Cache-Control':'private, no-store',
    'X-Content-Type-Options':'nosniff',
    'X-Frame-Options':'DENY',
    'X-Report-Sha256':String(doc.Sha256)
  }});
}
