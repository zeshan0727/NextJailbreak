// Next Accountant — private, staging-only web interface assets.
// This file contains NO business data, credentials or private identifiers.
const HTML = String.raw`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex,nofollow,noarchive">
<meta name="theme-color" content="#f7f8fb">
<title>Next Accountant | Secure Staging</title>
<link rel="stylesheet" href="/web/app.css">
<script defer src="/web/app.js"></script>
</head>
<body>
<div class="layout">
  <aside class="sidebar" id="sidebar">
    <div class="brand"><div class="brand-symbol">N</div>
      <div><strong>Next Accountant</strong><small>STAGING · READ ONLY</small></div></div>
    <div class="nav-label">WORKSPACE</div>
    <nav id="main-nav" aria-label="Workspace navigation"></nav>
    <div class="sidebar-foot"><span class="status-dot"></span> Private Cloudflare D1
      <div class="side-caption">Windows ACCOUNTANTS remains authoritative.</div></div>
  </aside>
  <main class="main">
    <header class="topbar">
      <div class="top-left"><button id="mobile-menu" class="icon-button" aria-label="Toggle navigation">☰</button>
        <div><div class="eyebrow">NEXT ACCOUNTANT / PRIVATE PREVIEW</div><h1 id="page-title">Overview</h1></div>
      </div>
      <div class="top-right"><span class="read-tag">READ ONLY</span><button class="outline-button" id="logout">Sign out</button></div>
    </header>
    <section class="safety-strip"><span class="safety-icon">◎</span>
      <span>Verified staging copy • 109 source tables • 11,913 records • 909 indexed files.
      Monetary and report-format reconciliation is still required. No changes to Windows data.</span></section>
    <div class="page-content">
      <div id="error" role="alert" hidden></div>
      <div class="control-bar">
        <label class="field-label">Company
        <select id="entity-picker" aria-label="Choose company"></select></label>
        <span class="pill">Seven managed companies only</span>
        <button id="refresh" class="outline-button">Refresh</button>
      </div>
      <section id="summary"></section>
      <section id="workspace" aria-live="polite"></section>
      <footer>Secure staging read-only workspace · Source ledger: ACCOUNTANTS V6 · Final reports remain Windows-format until validated.</footer>
    </div>
  </main>
</div>
</body></html>`;

const CSS = String.raw`:root{font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#152238;background:#f5f7fb;font-synthesis:none}
*{box-sizing:border-box}body{margin:0}.layout{min-height:100vh;display:grid;grid-template-columns:252px minmax(0,1fr)}
.sidebar{background:#111e32;color:#e2e9f4;display:flex;flex-direction:column;padding:28px 16px 20px;gap:24px}
.brand{display:flex;align-items:center;gap:12px;padding:0 12px}.brand-symbol{display:grid;place-items:center;background:linear-gradient(145deg,#d6a65d,#bc8434);color:#172337;width:43px;height:43px;border-radius:14px;font-size:25px;font-weight:900}
.brand strong{font-size:15px;letter-spacing:-.02em;display:block}.brand small{display:block;font-size:10px;color:#b9c6d9;margin-top:4px;letter-spacing:.08em}
.nav-label{font-size:10px;font-weight:750;letter-spacing:.16em;color:#7d8da5;padding:0 13px;margin-top:7px}
#main-nav{display:flex;flex-direction:column;gap:5px}
.nav-btn{border:0;text-align:left;background:transparent;color:#b8c6d8;font:inherit;font-size:13px;padding:12px 14px;border-radius:10px;cursor:pointer;display:flex;justify-content:space-between}
.nav-btn:hover{background:#22344f;color:#fff}.nav-btn.active{background:#263a56;color:#fff;font-weight:700;box-shadow:inset 3px 0 #d5ab6a}
.sidebar-foot{margin-top:auto;border-top:1px solid #293a52;padding:18px 12px 0;color:#dce9f7;font-size:12px}.side-caption{color:#8497b1;line-height:1.5;margin-top:9px;font-size:11px}
.status-dot{display:inline-block;background:#64d2a1;width:8px;height:8px;border-radius:50%;margin-right:5px}
.main{min-width:0}.topbar{display:flex;align-items:center;justify-content:space-between;gap:18px;min-height:100px;padding:20px 30px;background:#fff;border-bottom:1px solid #e7ecf4}
.top-left,.top-right{display:flex;align-items:center;gap:15px}.eyebrow{font-size:10px;letter-spacing:.13em;font-weight:750;color:#8c9cb2}h1{font-size:25px;margin:5px 0 0;letter-spacing:-.03em}
.read-tag{border:1px solid #c5dbce;background:#ecf7f0;color:#286a48;padding:7px 10px;border-radius:99px;font-weight:750;font-size:10px;letter-spacing:.06em}
button{font:inherit;cursor:pointer}.outline-button,.icon-button{border:1px solid #dbe3ef;background:#fff;border-radius:9px;padding:9px 13px;color:#243750;font-weight:650;font-size:12px}
.outline-button:hover,.icon-button:hover{background:#f4f7fb}.icon-button{display:none}
.safety-strip{margin:18px 30px 0;padding:13px 17px;background:#fffaf0;border:1px solid #f1dfb8;border-radius:11px;color:#785720;display:flex;gap:9px;font-size:12px;line-height:1.65}
.safety-icon{font-weight:bold;font-size:17px}.page-content{padding:24px 30px 38px;max-width:1620px}
.control-bar{display:flex;align-items:end;gap:15px;flex-wrap:wrap;margin-bottom:20px}
.field-label{display:flex;flex-direction:column;gap:7px;color:#7e8a9f;font-size:11px;font-weight:750}
select{background:white;color:#21344f;border:1px solid #dbe3ef;padding:12px 13px;border-radius:10px;min-width:285px;max-width:100%;font:inherit;font-size:13px}
.inline-check{display:flex;gap:9px;align-items:center;font-size:12px;color:#62748d;margin-bottom:12px}
.inline-check input{accent-color:#223e62}.control-bar>.outline-button{margin-bottom:0}
.metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:13px;margin-bottom:20px}
.metric-card,.panel{background:#fff;border:1px solid #e4eaf2;border-radius:14px;box-shadow:0 4px 18px rgba(25,43,70,.035)}
.metric-card{padding:21px;min-width:0}.metric-label{color:#778aa3;font-size:11px;font-weight:700;line-height:1.5}.metric-value{font-weight:780;font-size:26px;letter-spacing:-.03em;line-height:1.4;color:#203754;margin-top:8px}
.metric-sub{color:#96a1b0;font-size:11px;margin-top:7px}.panel{padding:21px;margin-bottom:19px}.panel-head{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:18px}
.panel h2{font-size:17px;letter-spacing:-.02em;margin:0}.muted{font-size:12px;color:#8190a4;line-height:1.6}
.panel p{margin:8px 0;color:#73849a;font-size:13px;line-height:1.6}.data-scroll{overflow:auto;border:1px solid #edf0f5;border-radius:10px}
table{width:100%;border-collapse:collapse;white-space:nowrap;font-size:12px}td,th{border-bottom:1px solid #ecf0f5;text-align:left;padding:12px 13px}
tr:last-child td{border-bottom:0}th{background:#f8fafd;color:#70839d;font-size:10px;letter-spacing:.07em;text-transform:uppercase;position:sticky;top:0}td{color:#30445e}
.row-actions{display:flex;gap:8px;align-items:center;margin-top:15px}.pill{display:inline-flex;border-radius:99px;padding:6px 10px;background:#f0f4f9;color:#61748b;font-size:11px;font-weight:650}
.empty{padding:37px 18px;text-align:center;color:#8795a9;font-size:13px}.loading{min-height:110px;display:grid;place-items:center;color:#8498b3}
#error{border:1px solid #ebc7c3;background:#fff1ef;border-radius:9px;color:#a4433c;padding:14px;margin-bottom:16px;font-size:13px}
button:disabled{opacity:.4;cursor:not-allowed}footer{border-top:1px solid #e7ebf2;padding-top:19px;color:#9ba8bb;font-size:11px;line-height:1.6}
@media(max-width:1080px){.metrics{grid-template-columns:repeat(2,1fr)}}
@media(max-width:760px){.layout{grid-template-columns:1fr}.sidebar{display:none;position:fixed;z-index:30;top:0;bottom:0;left:0;width:252px}.sidebar.open{display:flex}.icon-button{display:inline-flex}.topbar{padding:15px 18px;min-height:75px}.page-content{padding:17px}.safety-strip{margin:16px}.metrics{grid-template-columns:1fr 1fr}.metric-card{padding:15px}.metric-value{font-size:20px}select{min-width:215px}.read-tag{display:none}.panel{padding:15px}}
`;

const JS = String.raw`(function () {
  "use strict";
  const defs=[
    {id:"Overview",label:"Overview"},
    {id:"Projects",label:"Projects & contracts"},
    {id:"Payments",label:"Project receipts"},
    {id:"Plans",label:"Payment plans"},
    {id:"Allocations",label:"Receipt allocations"},
    {id:"Invoices",label:"Sales invoices"},
    {id:"PaymentVouchers",label:"Payment vouchers"},
    {id:"ReceiptVouchers",label:"Receipt vouchers"},
    {id:"Customers",label:"Customers"},
    {id:"ManagerReports",label:"Manager reports"}
  ];
  const byId=id=>document.getElementById(id);
  const el=(tag,txt,cls)=>{
    const node=document.createElement(tag);
    if(txt!==undefined && txt!==null)node.textContent=String(txt);
    if(cls)node.className=cls;
    return node;
  };
  const state={tab:"Overview",entity:null,entities:[],page:0,records:null,summary:null,loading:false};
  const amount=n=>new Intl.NumberFormat("en-QA",{style:"currency",currency:"QAR",maximumFractionDigits:2}).format(Number(n)||0);
  const num=n=>new Intl.NumberFormat("en-QA").format(Number(n)||0);
  function showError(message){
    const node=byId("error");node.textContent=message||"";node.hidden=!message;
  }
  async function api(path){
    const response=await fetch(path,{credentials:"same-origin",cache:"no-store"});
    if(response.status===401){location.replace("/web");throw Error("Session expired. Open the Windows launcher again.");}
    if(!response.ok)throw Error("Staging read error ("+response.status+"). The source data was not changed.");
    return response.json();
  }
  function drawNav(){
    const nav=byId("main-nav");nav.replaceChildren();
    defs.forEach(def=>{
      const b=el("button",def.label,"nav-btn"+(state.tab===def.id?" active":""));
      b.type="button";
      b.onclick=()=>{state.tab=def.id;state.page=0;byId("page-title").textContent=def.label;drawNav();loadRecords();byId("sidebar").classList.remove("open");};
      nav.appendChild(b);
    });
  }
  function fillEntities(){
    const picker=byId("entity-picker");
    const eligible=state.entities;
    picker.replaceChildren();
    for(const item of eligible){
      const option=el("option",item.Name+(item.Code?" · "+item.Code:""));
      option.value=String(item.Id);picker.appendChild(option);
    }
    if(!eligible.some(x=>String(x.Id)===String(state.entity)))state.entity=eligible[0]?.Id??null;
    if(state.entity!==null)picker.value=String(state.entity);
  }
  function metric(label,value,sub){
    const card=el("div",null,"metric-card");
    card.append(el("div",label,"metric-label"),el("div",value,"metric-value"),el("div",sub,"metric-sub"));
    return card;
  }
  function drawSummary(){
    const node=byId("summary");node.replaceChildren();
    if(!state.summary)return;
    const x=state.summary,box=el("div",null,"metrics");
    box.append(
      metric("Sales invoices",num(x.invoiceCount),"Non-cancelled invoice records"),
      metric("Invoiced total",amount(x.invoiceAmount),"Recorded invoices · not revenue"),
      metric("Payment vouchers",num(x.paymentCount),amount(x.paymentAmount)+" total"),
      metric("Receipt vouchers",num(x.receiptCount),amount(x.receiptAmount)+" total")
    );
    node.appendChild(box);
  }
  function panel(title,description){
    const wrapper=el("section",null,"panel");
    const head=el("div",null,"panel-head");
    head.append(el("h2",title),el("span","STAGING DATA · READ ONLY","pill"));
    wrapper.append(head,el("p",description));
    return wrapper;
  }
  function renderTable(data){
    const container=el("div",null,"data-scroll"),table=el("table");
    const thead=el("thead"),hrow=el("tr"),tbody=el("tbody");
    const cols=data.columns||[];
    cols.forEach(col=>hrow.appendChild(el("th",col.label)));
    thead.appendChild(hrow);
    (data.rows||[]).forEach(item=>{
      const tr=el("tr");
      for(const col of cols){
        const value=item[col.key];
        const display=col.money?amount(value):value==null?"—":value;
        tr.appendChild(el("td",display));
      }
      tbody.appendChild(tr);
    });
    table.append(thead,tbody);container.append(table);return container;
  }
  function recordPanel(data){
    const title=defs.find(x=>x.id===state.tab)?.label||"Records";
    const p=panel(title,"These entries are read directly from the verified V6 staging copy. Editing and official exports remain disabled.");
    if(!(data.rows||[]).length)p.appendChild(el("div","No records in this company / section.","empty"));
    else p.appendChild(renderTable(data));
    const foot=el("div",null,"row-actions");
    const back=el("button","Previous","outline-button"),next=el("button","Next","outline-button");
    back.disabled=state.page===0;next.disabled=(state.page+1)*data.pageSize>=data.total;
    back.onclick=()=>{state.page--;loadRecords();};
    next.onclick=()=>{state.page++;loadRecords();};
    foot.append(back,el("span",num(data.total)+" records · page "+(state.page+1),"muted"),next);
    p.append(foot);return p;
  }
  async function loadRecords(){
    showError(null);
    if(state.entity===null)return;
    const work=byId("workspace");work.replaceChildren(el("div","Reading private staging records…","loading"));
    try {
      const id=encodeURIComponent(state.entity);
      const summary=await api("/api/web/overview?entityId="+id);
      state.summary=summary;
      drawSummary();
      work.replaceChildren();
      if(state.tab==="Overview"){
        const stats=await api("/api/web/contracts?entityId="+id);
        const p=panel("Project contract overview","Contract milestones, customer payments and allocated receipts shown separately. These are not journal balances.");
        if(!stats.projects.length)p.appendChild(el("div","No project contracts are registered for this company.","empty"));
        else{
          p.appendChild(renderTable({columns:[
            {key:"ProjectName",label:"Project"}, {key:"CustomerName",label:"Customer"},
            {key:"Planned",label:"Contract plan",money:true},
            {key:"Received",label:"Recorded payments",money:true},
            {key:"Allocated",label:"Allocated",money:true}
          ],rows:stats.projects}));
        }
        work.append(p);
        const note=panel("Accounting integrity","Structural migration passed. The following still require financial tie-out against Windows: invoice totals, opening balances, aged receivables, manager-report worksheets and every entity's trial balance.");
        work.append(note);
      }else{
        const data=await api("/api/web/records?type="+encodeURIComponent(state.tab)+"&entityId="+id+"&page="+state.page);
        work.appendChild(recordPanel(data));
      }
    }catch(err){work.replaceChildren();showError(err.message||"Cannot read staging records.");}
  }
  async function start(){
    drawNav();
    byId("mobile-menu").onclick=()=>byId("sidebar").classList.toggle("open");
    byId("refresh").onclick=()=>{state.page=0;loadRecords();};
    byId("logout").onclick=async ()=>{
      try{await fetch("/api/web/logout",{method:"POST",credentials:"same-origin",cache:"no-store"});}
      finally{location.replace("/web");}
    };
    byId("entity-picker").onchange=e=>{state.entity=e.target.value;state.page=0;loadRecords();};
    try{
      const data=await api("/api/web/entities");
      state.entities=data.entities||[];
      fillEntities();
      if(!state.entities.length){showError("No source entities found in staging.");return;}
      await loadRecords();
    }catch(err){showError(err.message);}
  }
  start();
})();
`;

export function webAsset(path) {
  if (path === "/web") return {body:HTML,type:"text/html; charset=utf-8"};
  if (path === "/web/app.css") return {body:CSS,type:"text/css; charset=utf-8"};
  if (path === "/web/app.js") return {body:JS,type:"application/javascript; charset=utf-8"};
  return null;
}
