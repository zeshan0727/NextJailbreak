const KEY="next-accountant-free-preview-v1";
const API_BASE="https://accounts-api.nextjailbreak.com";
let backend={checked:false,online:false,database:false,files:false,version:""};
const initialState={version:"0.1.0",entities:[],activeEntityId:null,lastUpdated:null};
let state=load();
let activePage="Dashboard";

const modules=["Dashboard","Project Management","Payments / Receipts","Manager Reporting","Tasks","HR / Payroll","Settings"];
const nav=document.getElementById("nav");
const view=document.getElementById("view");
const pageTitle=document.getElementById("pageTitle");

function load(){
  try{const raw=localStorage.getItem(KEY);return raw?{...initialState,...JSON.parse(raw)}:{...initialState};}
  catch{return {...initialState};}
}
function save(){state.lastUpdated=new Date().toISOString();localStorage.setItem(KEY,JSON.stringify(state));}
function esc(v){return String(v??"").replace(/[&<>"']/g,m=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#039;"}[m]));}
function money(v=0){return new Intl.NumberFormat("en-QA",{style:"currency",currency:"QAR"}).format(Number(v)||0);}
function activeEntity(){return state.entities.find(x=>x.id===state.activeEntityId)||null;}

function renderNav(){
  nav.innerHTML=modules.map(m=>`<button class="nav-btn ${m===activePage?"active":""}" data-page="${m}">${m}</button>`).join("");
  nav.querySelectorAll("button").forEach(b=>b.onclick=()=>{activePage=b.dataset.page;render();});
}
function render(){
  renderNav();pageTitle.textContent=activePage;
  if(activePage==="Dashboard")return dashboard();
  if(activePage==="Settings")return settings();
  return modulePage(activePage);
}
function dashboard(){
  const e=activeEntity();
  view.innerHTML=`
    <div class="cards">
      <div class="card"><div class="metric-label">Entities</div><div class="metric">${state.entities.length}</div></div>
      <div class="card"><div class="metric-label">Active Entity</div><div class="metric" style="font-size:18px">${e?esc(e.name):"None"}</div></div>
      <div class="card"><div class="metric-label">Mode</div><div class="metric" style="font-size:18px">Local</div></div>
      <div class="card"><div class="metric-label">Server Cost</div><div class="metric">QAR 0</div></div>
    </div>
    <div class="panel">
      <div class="panel-head">
        <div><h2>Test entities</h2><div class="muted">Stored only in this browser.</div></div>
        <button id="addEntity">+ Add Test Entity</button>
      </div>
      ${state.entities.length?entityTable():'<div class="empty">No test entities yet. The public preview starts empty intentionally.</div>'}
    </div>
    <div class="panel">
      <div class="panel-head"><div><h2>Free-phase boundaries</h2><div class="muted">Designed so the paid backend can be added later without changing the user workflow.</div></div></div>
      <div class="status-list">
        <div class="status-item"><span>Responsive web interface</span><span class="good">Enabled</span></div>
        <div class="status-item"><span>Browser-local test storage</span><span class="good">Enabled</span></div>
        <div class="status-item"><span>Real company database / multi-device sync</span><span class="warn">Deferred</span></div>
        <div class="status-item"><span>OpenAI document reading</span><span class="warn">Disabled until secure backend</span></div>
        <div class="status-item"><span>Private document storage</span><span class="warn">Deferred</span></div>
      </div>
    </div>`;
  document.getElementById("addEntity").onclick=()=>document.getElementById("entityDialog").showModal();
  bindEntityRows();
}
function entityTable(){
  return `<table><thead><tr><th>Entity</th><th>Status</th><th></th></tr></thead><tbody>${state.entities.map(e=>`<tr><td>${esc(e.name)}</td><td><span class="pill">${e.id===state.activeEntityId?"Active":"Available"}</span></td><td><button class="secondary use-entity" data-id="${e.id}">Use</button></td></tr>`).join("")}</tbody></table>`;
}
function bindEntityRows(){document.querySelectorAll(".use-entity").forEach(b=>b.onclick=()=>{state.activeEntityId=b.dataset.id;save();dashboard();});}
function modulePage(name){
  const desc={
    "Project Management":"Customers, projects, contracts, payment plans, invoices, receipts and SOA will be migrated here first.",
    "Payments / Receipts":"Receipt creation, allocation, optional proof and project/payment-plan assignment will be reproduced here.",
    "Manager Reporting":"Income statement, balance sheet and manager reports will use the same accounting rules as Windows after reconciliation.",
    "Tasks":"Daily task tracking and reminders will be added after the core accounting migration.",
    "HR / Payroll":"Payroll, leave settlement, SIF and HR controls remain on Windows until the web accounting core is verified."
  }[name]||"Module preparation.";
  view.innerHTML=`<div class="panel"><div class="panel-head"><div><h2>${esc(name)}</h2><div class="muted">Preparation shell</div></div><span class="pill">Not connected to live data</span></div><div class="module-grid"><div class="card module"><h3>Purpose</h3><p>${esc(desc)}</p></div><div class="card module"><h3>Current phase</h3><p>UI/workflow preparation using GitHub Pages only. No business writes are performed.</p></div><div class="card module"><h3>Migration rule</h3><p>Windows remains authoritative until record counts, totals, balances and reports reconcile exactly.</p></div></div></div>`;
}
function settings(){
  view.innerHTML=`
    <div class="panel">
      <div class="panel-head"><div><h2>Local preview settings</h2><div class="muted">Nothing here changes the Windows ACCOUNTANTS application.</div></div></div>
      <div class="status-list">
        <div class="status-item"><span>Preview version</span><strong>${esc(state.version)}</strong></div>
        <div class="status-item"><span>Storage</span><strong>This browser only</strong></div>
        <div class="status-item"><span>Production hostname later</span><strong>accounts.nextjailbreak.com</strong></div>
      </div>
      <div class="row" style="margin-top:16px"><button class="secondary" id="clearLocal">Clear Local Test Data</button></div>
    </div>`;
  document.getElementById("clearLocal").onclick=()=>{if(confirm("Clear only this browser's Next Accountant preview data?")){localStorage.removeItem(KEY);state={...initialState};render();}};
}

document.getElementById("entityForm").addEventListener("submit",e=>{
  if(e.submitter?.value==="cancel")return;
  e.preventDefault();
  const input=document.getElementById("entityName");
  const name=input.value.trim();if(!name)return;
  const id=crypto.randomUUID?crypto.randomUUID():String(Date.now());
  state.entities.push({id,name});
  if(!state.activeEntityId)state.activeEntityId=id;
  save();input.value="";document.getElementById("entityDialog").close();dashboard();
});

document.getElementById("exportBtn").onclick=()=>{
  const blob=new Blob([JSON.stringify(state,null,2)],{type:"application/json"});
  const a=document.createElement("a");a.href=URL.createObjectURL(blob);
  a.download=`next-accountant-local-backup-${new Date().toISOString().slice(0,10)}.json`;a.click();URL.revokeObjectURL(a.href);
};
document.getElementById("importFile").onchange=async e=>{
  const file=e.target.files?.[0];if(!file)return;
  try{
    const imported=JSON.parse(await file.text());
    if(!Array.isArray(imported.entities))throw new Error("Invalid backup");
    state={...initialState,...imported};save();render();alert("Local preview backup imported.");
  }catch{alert("This is not a valid Next Accountant local preview backup.");}
  e.target.value="";
};

render();
