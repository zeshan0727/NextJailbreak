// Private ACCOUNTANTS V6 historical manager-report snapshot explorer.
// All source data is read-only. This is NOT new income statement preparation.
// Only called by already-authenticated, server-validated seven-company routes.

const companyMasks=[
  ['levante','%levante%bags%'],['north sports','%north%sports%'],
  ['graphitees','%graphitees%'],['barjous','%barjous%'],
  ['atelier','%atelier%'],['erada','%erada%'],
  ['stone','%stone%']
];
function response(body,status=200){
  return new Response(JSON.stringify(body),{status,headers:{
    'Content-Type':'application/json; charset=utf-8',
    'Cache-Control':'private, no-store',
    'X-Content-Type-Options':'nosniff',
    'Referrer-Policy':'no-referrer'
  }});
}
async function companyMask(env,entityId){
  const entity=await env.DB.prepare("SELECT Name FROM Entities WHERE Id=?").bind(entityId).first();
  if(!entity)return null;
  const name=String(entity.Name||'').toLowerCase();
  const group=companyMasks.find(([marker])=>name.includes(marker));
  if(!group)return null;
  return group[1];
}
function snapshotRef(url){
  const id=url.searchParams.get('snapshotId')||'';
  return id && id.length<=250 && !/[\u0000-\u001f\u007f]/.test(id) ? id : null;
}
function pageIndex(url){
  const raw=url.searchParams.get('page')||'0';
  return /^\d{1,5}$/.test(raw) && Number(raw)<=1000 ? Number(raw) : null;
}
export async function managerSnapshots(env,entityId){
  const pattern=await companyMask(env,entityId);
  if(!pattern)return response({error:'Company report mapping is unavailable.'},404);
  const result=await env.DB.prepare(
    "SELECT SnapshotId,Company,SnapshotDate,Version,AccountCount,PeriodCount,"+
    "Balanced,UnmappedCount,Active,FinalLocked "+
    "FROM ManagerReportTbSnapshotsV6A WHERE lower(Company) LIKE ? "+
    "ORDER BY SnapshotDate DESC,SnapshotId DESC LIMIT 100"
  ).bind(pattern).all();
  return response({snapshots:result.results||[],readOnly:true,
    source:'Original Windows V6 manager-report trial balance snapshots',
    financialStatementsCertified:false});
}
export async function managerAccounts(env,entityId,url){
  const mask=await companyMask(env,entityId);
  const snapshotId=snapshotRef(url);
  const page=pageIndex(url);
  if(!mask||!snapshotId||page===null)return response({error:'Invalid source snapshot request.'},400);
  // Validate selected company's original snapshot BEFORE fetching account data.
  const snap=await env.DB.prepare(
    "SELECT SnapshotId,Company,SnapshotDate,Version,AccountCount,PeriodCount,"+
    "Balanced,UnmappedCount,FinalLocked "+
    "FROM ManagerReportTbSnapshotsV6A WHERE SnapshotId=? AND lower(Company) LIKE ?"
  ).bind(snapshotId,mask).first();
  if(!snap)return response({error:'Snapshot not available for this company.'},404);
  const meta=await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM ManagerReportAccountsV6A WHERE SnapshotId=?"
  ).bind(snapshotId).first();
  const data=await env.DB.prepare(
    "SELECT AccountCode,AccountName,AccountType,Element,DebitYtd,CreditYtd,CurrentBalance "+
    "FROM ManagerReportAccountsV6A WHERE SnapshotId=? "+
    "ORDER BY Element,AccountCode,AccountKey LIMIT 100 OFFSET ?"
  ).bind(snapshotId,page*100).all();
  return response({snapshot:snap,rows:data.results||[],total:Number(meta?.n||0),
    page,pageSize:100,readOnly:true,
    note:'Source account balances only. No report recalculation or sign inversion has been applied.'});
}
export async function managerMappings(env,entityId,url){
  const mask=await companyMask(env,entityId);
  const page=pageIndex(url);
  if(!mask||page===null)return response({error:'Invalid report-mapping request.'},400);
  const meta=await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM ManagerReportMappingsV6A WHERE lower(Company) LIKE ?"
  ).bind(mask).first();
  const result=await env.DB.prepare(
    "SELECT AccountCode,AccountName,SourceType,SubMapping,StatementType,"+
    "TemplateCode,TemplateRow,TemplateOrder,SourceKind "+
    "FROM ManagerReportMappingsV6A WHERE lower(Company) LIKE ? "+
    "ORDER BY TemplateOrder,TemplateRow,MappingKey LIMIT 100 OFFSET ?"
  ).bind(mask,page*100).all();
  return response({rows:result.results||[],total:Number(meta?.n||0),
    page,pageSize:100,readOnly:true,
    note:'Original Windows report mappings, not newly generated Income Statement or Balance Sheet totals.'});
}
