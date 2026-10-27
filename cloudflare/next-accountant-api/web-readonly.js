// Private staging-only web access for ACCOUNTANTS V6 imported data.
// Never re-use this session cookie as a migration/administrator credential.
// All business SELECTs are explicitly allowlisted; no browser mutation exists.
import { webAsset } from './web-view.js';

const COOKIE = '__Host-na-staging';
const MAX_AGE = 8 * 60 * 60;
const CODE_AGE = 90;
const enc = new TextEncoder();
// Only seven user-managed entities may be read through private web sessions.
// Mapping was checked against private staging with exactly one entity per
// expected company. It applies in the API, not just the frontend selector.
const MANAGED_SQL = [
  "lower(Name) LIKE '%stone%'",
  "lower(Name) LIKE '%graphitees%'",
  "lower(Name) LIKE '%barjous%'",
  "lower(Name) LIKE '%levante%bags%'",
  "lower(Name) LIKE '%atelier%'",
  "lower(Name) LIKE '%erada%'",
  "lower(Name) LIKE '%north sports%'"
].join(' OR ');


function json(payload, status=200, headers={}) {
  return new Response(JSON.stringify(payload), {
    status, headers:{
      'Content-Type':'application/json; charset=utf-8',
      'Cache-Control':'private, no-store',
      'X-Content-Type-Options':'nosniff',
      'Referrer-Policy':'no-referrer',
      ...headers
    }
  });
}
function secureHeaders(type) {
  const headers = {
    'Content-Type':type,
    'Cache-Control':'private, no-store',
    'X-Content-Type-Options':'nosniff',
    'Referrer-Policy':'no-referrer',
    'X-Frame-Options':'DENY',
    'Strict-Transport-Security':'max-age=31536000'
  };
  if (type.startsWith('text/html')) headers['Content-Security-Policy'] =
    "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'none'; form-action 'none'; frame-ancestors 'none'; base-uri 'none'";
  return headers;
}
function randomToken(){
  const raw=crypto.getRandomValues(new Uint8Array(32));
  return [...raw].map(v=>v.toString(16).padStart(2,'0')).join('');
}
async function hashToken(token) {
  const output=await crypto.subtle.digest('SHA-256',enc.encode(token));
  return [...new Uint8Array(output)].map(v=>v.toString(16).padStart(2,'0')).join('');
}
function baseUrl(request) {
  const url=new URL(request.url);
  return url.origin;
}
function getCookie(request) {
  const found=(request.headers.get('Cookie')||'').split(';')
    .map(x=>x.trim()).find(x=>x.startsWith(COOKIE+'='));
  const value=found ? found.slice(COOKIE.length+1) : '';
  return /^[0-9a-f]{64}$/.test(value) ? value : '';
}
async function isViewer(request,env){
  const token=getCookie(request);
  if(!token)return false;
  const hash=await hashToken(token);
  const row=await env.DB.prepare(
    "SELECT Hash FROM WebReadSessions WHERE Hash=? AND ExpiresAt>?"
  ).bind(hash,Date.now()).first();
  return Boolean(row);
}
function cookie(value,maxAge) {
  return COOKIE+'='+value+'; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age='+maxAge;
}
function denied() {
  return json({error:'Private staging access required. Start from the Windows OPEN_STAGING_WEB launcher.'},401);
}
function tableConfig(type){
  // Labels and projections are static: never interpolate client-supplied SQL.
  const base = {
    Invoices:{
      from:'SalesInvoices x',where:'x.EntityId=?',sort:'x.Id DESC',
      fields:[['Id','ID'],['InvoiceNumber','Invoice'],['InvoiceDate','Date'],
        ['CustomerName','Customer'],['Amount','Amount',true],['Year','Year'],['Month','Month'],['IsCancelled','Cancelled']]
    },
    PaymentVouchers:{
      from:'PaymentVouchers x',where:'x.EntityId=?',sort:'x.Id DESC',
      fields:[['Id','ID'],['VoucherNo','PV No.'],['VoucherDate','Date'],
        ['Payee','Payee'],['Amount','Amount',true],['Currency','Currency'],['Category','Category'],['PaymentMode','Method'],['Purpose','Purpose']]
    },
    ReceiptVouchers:{
      from:'ReceiptVouchers x',where:'x.EntityId=?',sort:'x.Id DESC',
      fields:[['Id','ID'],['ReceiptNo','Receipt No.'],['ReceiptDate','Date'],
        ['ReceivedFrom','Received from'],['Amount','Amount',true],['Currency','Currency'],['ReceiptType','Type'],['ReferenceNo','Reference']]
    },
    Customers:{
      from:'Customers x',where:'x.EntityId=?',sort:'x.Id DESC',
      fields:[['Id','ID'],['Reference','Reference'],['ContactName','Contact'],['NeedsReview','Needs review']]
    },
    Projects:{
      from:'PMProjects x JOIN PMCustomers c ON x.CustomerId=c.Id',where:'c.EntityId=?',sort:'x.Id DESC',
      fields:[['Id','ID'],['ProjectCode','Project code'],['ProjectName','Project'],['Status','Status'],['CreatedAt','Created']]
    },
    Payments:{
      from:'PMPayments x JOIN PMCustomers c ON x.CustomerId=c.Id',where:'c.EntityId=?',sort:'x.Id DESC',
      fields:[['Id','ID'],['PaymentDate','Date'],['Reference','Reference'],
        ['Amount','Amount',true],['PaymentMethod','Method'],['IsAdvance','Advance'],['ProjectId','Project ID']]
    },
    Plans:{
      from:'PMPaymentPlan x JOIN PMProjects p ON x.ProjectId=p.Id JOIN PMCustomers c ON p.CustomerId=c.Id',
      where:'c.EntityId=?',sort:'x.Id DESC',
      fields:[['Id','ID'],['ProjectId','Project ID'],['SequenceNo','Installment'],
        ['Title','Milestone'],['DueDate','Due date'],['Percentage','Percent'],['Amount','Amount',true],['Currency','Currency']]
    },
    Allocations:{
      from:'PMPaymentPlanAllocations x JOIN PMPayments p ON x.PaymentId=p.Id JOIN PMCustomers c ON p.CustomerId=c.Id',
      where:'c.EntityId=?',sort:'x.Id DESC',
      fields:[['Id','ID'],['PaymentId','Payment ID'],['PaymentPlanId','Installment ID'],
        ['ReceivedDate','Received'],['Amount','Allocated amount',true]]
    }
  };
  return base[type]||null;
}
function queryId(url){
  const raw=url.searchParams.get('entityId');
  if(!/^[1-9]\d{0,9}$/.test(raw||''))return null;
  return Number(raw);
}
async function ensureEntity(env,id){
  return Boolean(await env.DB.prepare(
    'SELECT Id FROM Entities WHERE Id=? AND ('+MANAGED_SQL+')'
  ).bind(id).first());
}
async function overview(env,id){
  const r=await env.DB.prepare(
    "SELECT " +
    "(SELECT COUNT(*) FROM SalesInvoices WHERE EntityId=? AND IsCancelled=0) invoiceCount," +
    "(SELECT COALESCE(SUM(Amount),0) FROM SalesInvoices WHERE EntityId=? AND IsCancelled=0) invoiceAmount," +
    "(SELECT COUNT(*) FROM PaymentVouchers WHERE EntityId=?) paymentCount," +
    "(SELECT COALESCE(SUM(Amount),0) FROM PaymentVouchers WHERE EntityId=?) paymentAmount," +
    "(SELECT COUNT(*) FROM ReceiptVouchers WHERE EntityId=?) receiptCount," +
    "(SELECT COALESCE(SUM(Amount),0) FROM ReceiptVouchers WHERE EntityId=?) receiptAmount"
  ).bind(id,id,id,id,id,id).first();
  return json(r||{});
}
async function contracts(env,id){
  const q=await env.DB.prepare(
    "SELECT p.Id,p.ProjectCode,p.ProjectName,c.CustomerName,p.Status," +
    "COALESCE((SELECT SUM(x.Amount) FROM PMPaymentPlan x WHERE x.ProjectId=p.Id),0) Planned," +
    "COALESCE((SELECT SUM(x.Amount) FROM PMPayments x WHERE x.ProjectId=p.Id),0) Received," +
    "COALESCE((SELECT SUM(a.Amount) FROM PMPaymentPlanAllocations a " +
      "JOIN PMPaymentPlan pl ON a.PaymentPlanId=pl.Id WHERE pl.ProjectId=p.Id),0) Allocated " +
    "FROM PMProjects p JOIN PMCustomers c ON c.Id=p.CustomerId " +
    "WHERE c.EntityId=? ORDER BY p.Id DESC LIMIT 100"
  ).bind(id).all();
  return json({projects:q.results||[]});
}
async function records(env,id,url) {
  const type=url.searchParams.get('type')||'';
  if(type==='ManagerReports') {
    // ManagerReportHistoryV6A is company-name based (not EntityId based).
    // Until precise mapping is validated, avoid guessing and misattributing
    // one company's financial report to another company.
    return json({columns:[{key:'Status',label:'Status'}],
      rows:[{Status:'Report file references imported; company mapping and Windows-format exports await reconciliation.'}],
      page:0,pageSize:50,total:1,mappingPending:true});
  }
  const cfg=tableConfig(type);
  if(!cfg)return json({error:'Unknown read-only report type.'},400);
  const pg=Number(url.searchParams.get('page')||0);
  if(!Number.isSafeInteger(pg)||pg<0||pg>10000)return json({error:'Invalid page.'},400);
  const select=cfg.fields.map(f=>'x."'+f[0]+'"').join(',');
  const where=' WHERE '+cfg.where;
  const count=await env.DB.prepare('SELECT COUNT(*) AS total FROM '+cfg.from+where).bind(id).first();
  const data=await env.DB.prepare('SELECT '+select+' FROM '+cfg.from+where+
    ' ORDER BY '+cfg.sort+' LIMIT ? OFFSET ?').bind(id,50,pg*50).all();
  return json({
    type,columns:cfg.fields.map(f=>({key:f[0],label:f[1],money:Boolean(f[2])})),
    rows:data.results||[],total:Number(count?.total||0),page:pg,pageSize:50
  });
}

export async function createWebTicket(request,env) {
  if(env.MIGRATION_ENV!=='staging')return json({error:'Staging only.'},503);
  if(request.method!=='POST')return json({error:'POST required.'},405);
  const ticket=randomToken();
  const hash=await hashToken(ticket);
  const now=Date.now();
  await env.DB.prepare("DELETE FROM WebReadTickets WHERE ExpiresAt<?").bind(now).run();
  await env.DB.prepare("INSERT INTO WebReadTickets(Hash,ExpiresAt) VALUES(?,?)")
    .bind(hash,now+CODE_AGE*1000).run();
  return json({ok:true,launchUrl:baseUrl(request)+'/web/activate?ticket='+ticket,
    expiresInSeconds:CODE_AGE});
}
async function activate(request,env,url){
  const ticket=url.searchParams.get('ticket')||'';
  if(!/^[0-9a-f]{64}$/.test(ticket))return denied();
  const hash=await hashToken(ticket);
  const now=Date.now();
  const used=await env.DB.prepare("DELETE FROM WebReadTickets WHERE Hash=? AND ExpiresAt>?")
    .bind(hash,now).run();
  if(Number(used.meta?.changes||0)!==1)return denied();
  const token=randomToken(),sessionHash=await hashToken(token);
  await env.DB.prepare("INSERT INTO WebReadSessions(Hash,CreatedAt,ExpiresAt) VALUES(?,?,?)")
    .bind(sessionHash,now,now+MAX_AGE*1000).run();
  return new Response(null,{status:303,headers:{
    ...secureHeaders('text/plain; charset=utf-8'),
    'Location':'/web','Set-Cookie':cookie(token,MAX_AGE)
  }});
}
export async function handleWeb(request,env) {
  if(env.MIGRATION_ENV!=='staging')return json({error:'Staging only.'},503);
  const url=new URL(request.url);
  try {
    if(request.method==='GET'&&url.pathname==='/web/activate')
      return await activate(request,env,url);
    if(url.pathname==='/api/web/logout'){
      if(request.method!=='POST')return json({error:'POST required.'},405);
      const origin=request.headers.get('Origin');
      if(origin && origin!==url.origin)return json({error:'Origin rejected.'},403);
      const token=getCookie(request);
      if(token)await env.DB.prepare("DELETE FROM WebReadSessions WHERE Hash=?")
        .bind(await hashToken(token)).run();
      return new Response(null,{status:204,headers:{
        ...secureHeaders('text/plain; charset=utf-8'), 'Set-Cookie':cookie('',0)
      }});
    }
    if(request.method!=='GET')return json({error:'Read-only staging web. Writes are disabled.'},405);
    if(url.pathname==='/web/app.css'||url.pathname==='/web/app.js'){
      const asset=webAsset(url.pathname);
      return new Response(asset.body,{headers:secureHeaders(asset.type)});
    }
    const authenticated=await isViewer(request,env);
    if(!authenticated){
      if(url.pathname==='/web')return new Response(
        '<!doctype html><html lang="en"><meta charset="utf-8"><title>Private staging</title>'+
        '<body style="font:16px system-ui;margin:10vh auto;max-width:600px;line-height:1.8">'+
        '<h1>Private Next Accountant staging</h1>'+
        '<p>Access requires the Windows <strong>OPEN_STAGING_WEB.bat</strong> launcher.</p>'+
        '<p>Your accounting records are never accessible through this public address without a valid session.</p></body></html>',
        {status:401,headers:secureHeaders('text/html; charset=utf-8')}
      );
      return denied();
    }
    if(url.pathname==='/web') {
      const asset=webAsset('/web');
      return new Response(asset.body,{headers:secureHeaders(asset.type)});
    }
    if(url.pathname==='/api/web/entities') {
      const result=await env.DB.prepare(
        'SELECT Id,Name,Code,IsActive FROM Entities WHERE ('+MANAGED_SQL+') ORDER BY Name LIMIT 7'
      ).all();
      return json({entities:result.results||[]});
    }
    if(url.pathname==='/api/web/overview'||url.pathname==='/api/web/contracts'||
       url.pathname==='/api/web/records') {
      const id=queryId(url);
      if(!id)return json({error:'Select a valid entity.'},400);
      if(!await ensureEntity(env,id))return json({error:'Company not accessible in this private workspace.'},404);
      if(url.pathname==='/api/web/overview')return await overview(env,id);
      if(url.pathname==='/api/web/contracts')return await contracts(env,id);
      return await records(env,id,url);
    }
    return json({error:'Not found.'},404);
  }catch(error){
    // Do not send confidential database query details to the browser.
    return json({error:'Staging read service unavailable. Check application logs.'},503);
  }
}
