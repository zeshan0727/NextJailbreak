
/* Next Accountant Web — ISOLATED browser-only project workflow test.
   No real business records, no remote writes. */
(function () {
  "use strict";
  const SESSION_PREFIX="next-accountant-demo-project:";
  const KEY_TYPES=["Bank Transfer","Cash","Cheque","Card / POS","Other"];
  const cents=value=>{
    const number=Number(value);
    if(!Number.isFinite(number)||number<=0)throw new Error("Amount must be greater than zero.");
    return Math.round(number*100);
  };
  const fmt=n=>money((n||0)/100);
  const uid=()=>typeof crypto.randomUUID==="function"?crypto.randomUUID():"demo-"+Date.now()+"-"+Math.random().toString(36).slice(2);
  const safe=val=>esc(val??"");
  const amount=val=>Number(val||0);
  const pm=()=>{
    if(!state.pmDemo)state.pmDemo={customers:[],projects:[],plans:[],payments:[],allocations:[]};
    return state.pmDemo;
  };
  function projects(){
    const e=activeEntity();
    return e?pm().projects.filter(x=>x.entityId===e.id):[];
  }
  function customer(id){return pm().customers.find(x=>x.id===id);}
  function project(id){return pm().projects.find(x=>x.id===id);}
  function plan(id){return pm().plans.find(x=>x.id===id);}
  function payment(id){return pm().payments.find(x=>x.id===id);}
  function allocationsForReceipt(id){return pm().allocations.filter(x=>x.paymentId===id);}
  function allocationsForPlan(id){return pm().allocations.filter(x=>x.planId===id);}
  function allocatedReceipt(id){return allocationsForReceipt(id).reduce((n,a)=>n+a.amountCents,0);}
  function allocatedPlan(id){return allocationsForPlan(id).reduce((n,a)=>n+a.amountCents,0);}
  function sum(list,key){return list.reduce((n,x)=>n+(x[key]||0),0);}
  function selectedProject(){
    const e=activeEntity();if(!e)return null;
    const list=projects(),key=SESSION_PREFIX+e.id;
    let chosen=sessionStorage.getItem(key);
    if(chosen==="")return null;
    if(!list.some(p=>p.id===chosen)){
      chosen=list[0]?.id||"";
      if(chosen)sessionStorage.setItem(key,chosen);
    }
    return project(chosen);
  }
  function projectSelect(selected,options){
    const list=options||projects();
    return list.map(x=>`<option value="${safe(x.id)}" ${x.id===selected?"selected":""}>${safe(x.name)}</option>`).join("");
  }
  function customerSelect(selected,options){
    const e=activeEntity(), list=options||pm().customers.filter(c=>c.entityId===e?.id);
    return list.map(x=>`<option value="${safe(x.id)}" ${x.id===selected?"selected":""}>${safe(x.name)}</option>`).join("");
  }
  const notice=`<div class="demo-warning">DEMO WORKSPACE — all values stay in this browser. No connection to the Windows ledger or cloud business data.</div>`;
  function openForm(title,html,onSubmit){
    const dialog=document.getElementById("pmDialog");
    dialog.innerHTML=`<form class="pm-form" id="pmForm"><header><h2>${safe(title)}</h2><button type="button" class="secondary" id="pmCancel">Close</button></header>${html}<div class="dialog-actions"><button type="submit">Save</button></div></form>`;
    dialog.querySelector("#pmCancel").onclick=()=>dialog.close();
    dialog.querySelector("#pmForm").onsubmit=e=>{
      e.preventDefault();
      try{onSubmit(new FormData(e.currentTarget));save();dialog.close();demoModule(activePage);}
      catch(error){alert(error.message||"Could not save.");}
    };
    dialog.showModal();
    return dialog;
  }
  const field=(label,name,type="text",value="",extra="")=>`<label class="pm-field">${safe(label)}<input name="${safe(name)}" type="${type}" value="${safe(value)}" ${extra} required></label>`;
  function addCustomer(){
    openForm("New test customer",field("Customer name","name","text","","maxlength='120'"),f=>{
      const name=String(f.get("name")||"").trim();
      if(!name)throw Error("Customer name is required.");
      pm().customers.push({id:uid(),entityId:activeEntity().id,name});
    });
  }
  function addProject(){
    const data=pm(),e=activeEntity(),customers=data.customers.filter(c=>c.entityId===e.id);
    if(!customers.length)return alert("Add a test customer first.");
    const html=`<label class="pm-field">Customer<select name="customerId" required>${customerSelect()}</select></label>`+field("Project / contract name","name");
    openForm("New project",html,f=>{
      const customerId=String(f.get("customerId"));
      if(!customers.some(c=>c.id===customerId))throw Error("Select a valid customer.");
      const id=uid();
      data.projects.push({id,entityId:e.id,customerId,name:String(f.get("name")||"").trim()});
      sessionStorage.setItem(SESSION_PREFIX+e.id,id);
    });
  }
  function addPlan(){
    const proj=selectedProject();
    if(!proj)return alert("Add a project first.");
    const html=field("Installment / milestone","label")+
      field("Amount (QAR)","amount","number","","min='0.01' step='0.01'")+
      field("Due date","dueDate","date",new Date().toISOString().slice(0,10));
    openForm("Add contract installment",html,f=>{
      const value=cents(f.get("amount")),label=String(f.get("label")||"").trim();
      if(!label)throw Error("Installment name is required.");
      pm().plans.push({id:uid(),projectId:proj.id,label,amountCents:value,dueDate:String(f.get("dueDate"))});
    });
  }
  function recordPayment(){
    const e=activeEntity(),data=pm(),customers=data.customers.filter(c=>c.entityId===e?.id);
    if(!customers.length)return alert("Add a test customer and project first.");
    const selected=selectedProject();
    const html=`<label class="pm-field">Customer<select name="customerId" required>${customerSelect(selected?.customerId)}</select></label>`+
      field("Unique receipt reference","reference")+
      field("Received amount (QAR)","amount","number","","min='0.01' step='0.01'")+
      field("Payment date","date","date",new Date().toISOString().slice(0,10))+
      `<label class="pm-field">Payment method<select name="method">${KEY_TYPES.map(s=>`<option>${safe(s)}</option>`).join("")}</select></label>`;
    openForm("Record customer payment",html,f=>{
      const reference=String(f.get("reference")||"").trim(),customerId=String(f.get("customerId")||"");
      if(!reference)throw Error("Payment reference is required.");
      if(data.payments.some(x=>x.reference.toLowerCase()===reference.toLowerCase()))
        throw Error("This payment reference already exists. Enter a unique reference.");
      data.payments.push({id:uid(),entityId:e.id,customerId,reference,amountCents:cents(f.get("amount")),
        date:String(f.get("date")),method:String(f.get("method")),receiptGenerated:false});
    });
  }
  function editPayment(id){
    const p=payment(id);if(!p)return;
    const allocated=allocatedReceipt(id);
    const html=field("Receipt reference","reference","text",p.reference)+
      field("Received amount (QAR)","amount","number",(p.amountCents/100).toFixed(2),"min='0.01' step='0.01'")+
      field("Payment date","date","date",p.date)+
      `<label class="pm-field">Payment method<select name="method">${KEY_TYPES.map(s=>`<option ${s===p.method?"selected":""}>${safe(s)}</option>`).join("")}</select></label>`;
    openForm("Edit payment",html,f=>{
      const reference=String(f.get("reference")||"").trim();
      if(!reference)throw Error("Reference cannot be blank.");
      if(pm().payments.some(x=>x.id!==id&&x.reference.toLowerCase()===reference.toLowerCase()))throw Error("Duplicate receipt reference.");
      const newAmt=cents(f.get("amount"));
      if(newAmt<allocated)throw Error("Cannot reduce received amount below "+fmt(allocated)+" already assigned. Unassign first.");
      p.reference=reference;p.amountCents=newAmt;p.date=String(f.get("date"));p.method=String(f.get("method"));
    });
  }
  function deletePayment(id){
    const p=payment(id);if(!p)return;
    if(!confirm("Delete test payment "+p.reference+" and all of its installment assignments? This does not affect Windows ACCOUNTANTS."))return;
    const data=pm();
    data.allocations=data.allocations.filter(a=>a.paymentId!==id);
    data.payments=data.payments.filter(x=>x.id!==id);
    save();demoModule(activePage);
  }
  function receipt(id){
    const p=payment(id);if(!p)return;
    if(!p.receiptGenerated){p.receiptGenerated=true;save();demoModule(activePage);}
    const c=customer(p.customerId);
    const dialog=document.getElementById("pmDialog");
    dialog.innerHTML=`<section class="pm-receipt"><header><h2>PAYMENT RECEIPT</h2><button class="secondary" id="pmCancel">Close</button></header>
      <div class="pm-receipt-row"><span>Receipt No.</span><strong>${safe(p.reference)}</strong></div>
      <div class="pm-receipt-row"><span>Received From</span><strong>${safe(c?.name||"")}</strong></div>
      <div class="pm-receipt-row"><span>Amount</span><strong>${fmt(p.amountCents)}</strong></div>
      <div class="pm-receipt-row"><span>Payment Method</span><strong>${safe(p.method)}</strong></div>
      <div class="pm-receipt-row"><span>Receipt Date</span><strong>${safe(p.date)}</strong></div>
      <p class="muted">Browser preview only. Official PDFs remain generated by Windows until report parity is verified. Payment proof is optional and does not block allocation.</p>
      </section>`;
    dialog.querySelector("#pmCancel").onclick=()=>dialog.close();
    dialog.showModal();
  }
  function assignmentDialog(id){
    const p=payment(id),data=pm();if(!p)return;
    if(!p.receiptGenerated)return alert("Create the payment receipt before assigning it.");
    const available=data.projects.filter(x=>x.entityId===p.entityId&&x.customerId===p.customerId);
    if(!available.length)return alert("This customer has no eligible project. Create its project first.");
    const select=selectedProject();
    let projectId=available.some(x=>x.id===select?.id)?select.id:available[0].id;
    const remaining=p.amountCents-allocatedReceipt(p.id);
    const existing=allocationsForReceipt(id);
    const dialog=document.getElementById("pmDialog");
    function renderContents(){
      const possiblePlans=data.plans.filter(x=>x.projectId===projectId);
      const availablePlans=possiblePlans.filter(x=>x.amountCents>allocatedPlan(x.id));
      dialog.innerHTML=`<section class="pm-form">
        <header><h2>Assign receipt ${safe(p.reference)}</h2><button type="button" class="secondary" id="pmCancel">Close</button></header>
        <p class="muted">Select the customer's project, its contract installment, and the amount to allocate. Multiple receipts may fund one installment.</p>
        <div class="pm-receipt-row"><span>Received</span><strong>${fmt(p.amountCents)}</strong></div>
        <div class="pm-receipt-row"><span>Unassigned balance</span><strong>${fmt(remaining)}</strong></div>
        <form id="allocationForm">
        <label class="pm-field">Customer project<select id="assignProject">${projectSelect(projectId,available)}</select></label>
        <label class="pm-field">Contract payment plan<select name="planId" required>${availablePlans.map(x=>`<option value="${safe(x.id)}">${safe(x.label)} — remaining ${fmt(x.amountCents-allocatedPlan(x.id))}</option>`).join("")}</select></label>
        ${field("Assign amount (QAR)","amount","number",Math.max(remaining/100,0).toFixed(2),"min='0.01' step='0.01'")}
        <div class="dialog-actions"><button type="submit" ${remaining<=0||!availablePlans.length?"disabled":""}>Assign amount</button></div></form>
        <h3>Existing assignments</h3>
        ${existing.length?`<table><thead><tr><th>Project / installment</th><th>Allocated</th><th></th></tr></thead>
        <tbody>${existing.map(a=>{const pl=plan(a.planId),pj=project(pl?.projectId);return `<tr><td>${safe(pj?.name||"")} / ${safe(pl?.label||"")}</td><td>${fmt(a.amountCents)}</td><td><button class="secondary unassign" data-id="${safe(a.id)}">Unassign</button></td></tr>`;}).join("")}</tbody></table>`:`<p class="muted">No installment assigned yet.</p>`}
        </section>`;
      dialog.querySelector("#pmCancel").onclick=()=>dialog.close();
      dialog.querySelector("#assignProject").onchange=e=>{
        projectId=e.target.value;
        /* User selection remains in force for this assignment dialog only. */
        renderContents();
      };
      dialog.querySelectorAll(".unassign").forEach(b=>b.onclick=()=>{
        if(!confirm("Unassign this test receipt amount from its installment?"))return;
        data.allocations=data.allocations.filter(a=>a.id!==b.dataset.id);
        save();dialog.close();demoModule(activePage);assignmentDialog(id);
      });
      dialog.querySelector("#allocationForm").onsubmit=e=>{
        e.preventDefault();
        try{
          const f=new FormData(e.target),planId=String(f.get("planId")||""),target=plan(planId);
          const n=cents(f.get("amount"));
          if(!target||target.projectId!==projectId)throw Error("Invalid project/installment selection.");
          if(n>p.amountCents-allocatedReceipt(id))throw Error("Assignment exceeds the receipt's remaining amount.");
          if(n>target.amountCents-allocatedPlan(planId))throw Error("Assignment exceeds the installment's outstanding amount.");
          data.allocations.push({id:uid(),paymentId:id,planId,amountCents:n});
          save();dialog.close();demoModule(activePage);assignmentDialog(id);
        }catch(err){alert(err.message);}
      };
    }
    renderContents();dialog.showModal();
  }
  function renderPlanRows(prj){
    const list=pm().plans.filter(p=>p.projectId===prj.id);
    if(!list.length)return `<div class="empty">No contract installments added yet.</div>`;
    return `<div class="pm-scroll"><table><thead><tr><th>Contract installment</th><th>Due</th><th>Plan amount</th><th>Received</th><th>Remaining</th><th>Receipts</th></tr></thead><tbody>
    ${list.map(p=>{
      const allocated=allocatedPlan(p.id),allocs=allocationsForPlan(p.id);
      return `<tr><td><strong>${safe(p.label)}</strong></td><td>${safe(p.dueDate)}</td><td>${fmt(p.amountCents)}</td>
        <td>${fmt(allocated)}</td><td>${fmt(Math.max(0,p.amountCents-allocated))}</td>
        <td>${allocs.length}${allocs.length?`<div class="muted">${allocs.map(a=>safe(payment(a.paymentId)?.reference)).join(", ")}</div>`:""}</td></tr>`;
    }).join("")}</tbody></table></div>`;
  }
  function dashboard(prj, payments){
    const data=pm(),plans=prj?data.plans.filter(x=>x.projectId===prj.id):[];
    const allocated=sum(plans.map(x=>({amountCents:allocatedPlan(x.id)})),"amountCents");
    return `<div class="cards">
      <div class="card"><div class="metric-label">Contract amount</div><div class="metric">${fmt(sum(plans,"amountCents"))}</div></div>
      <div class="card"><div class="metric-label">Assigned receipts</div><div class="metric">${fmt(allocated)}</div></div>
      <div class="card"><div class="metric-label">Unallocated receipts</div><div class="metric">${fmt(payments.reduce((n,x)=>n+x.amountCents-allocatedReceipt(x.id),0))}</div></div>
      <div class="card"><div class="metric-label">Customer payments</div><div class="metric">${payments.length}</div></div>
    </div>`;
  }
  function projectPage(prj,payments){
    const data=pm(),e=activeEntity(),customers=data.customers.filter(x=>x.entityId===e.id);
    return dashboard(prj,payments)+`<div class="panel">
      <div class="panel-head"><div><h2>Contract payment plan</h2><div class="muted">Choose a project; your selection is preserved during this browser session.</div></div>
        <div class="row"><button class="secondary" id="addCustomer">+ Customer</button><button class="secondary" id="addProject">+ Project</button><button id="addInstallment">+ Installment</button></div></div>
      ${prj?`<div class="pm-meta"><strong>${safe(prj.name)}</strong><span>Customer: ${safe(customer(prj.customerId)?.name||"")}</span></div>${renderPlanRows(prj)}`:
        `<div class="empty">Start by adding a test customer and project.</div>`}
    </div>
    <div class="panel"><div class="panel-head"><h2>Entity customers</h2></div>
    ${customers.length?`<div class="pm-scroll"><table><thead><tr><th>Customer</th><th>Projects</th></tr></thead><tbody>
    ${customers.map(c=>`<tr><td>${safe(c.name)}</td><td>${data.projects.filter(x=>x.customerId===c.id).length}</td></tr>`).join("")}</tbody></table></div>`:
      `<div class="empty">No customers in this test entity.</div>`}</div>`;
  }
  function paymentPage(prj,payments){
    return dashboard(prj,payments)+`<div class="panel">
      <div class="panel-head"><div><h2>Payments & receipts</h2><div class="muted">Record a payment, create its receipt, then assign or unassign against contract installments.</div></div>
      <button id="recordPayment">+ Record payment</button></div>
      ${payments.length?`<div class="pm-scroll"><table><thead><tr><th>Reference / Receipt No.</th><th>Customer</th><th>Received</th><th>Method</th><th>Assigned</th><th>Remaining</th><th>Actions</th></tr></thead><tbody>
      ${payments.map(p=>`<tr><td><strong>${safe(p.reference)}</strong><div class="muted">${safe(p.date)}</div></td>
        <td>${safe(customer(p.customerId)?.name||"")}</td><td>${fmt(p.amountCents)}</td><td>${safe(p.method)}</td>
        <td>${fmt(allocatedReceipt(p.id))}</td><td>${fmt(Math.max(0,p.amountCents-allocatedReceipt(p.id)))}</td>
        <td><div class="row">
          <button class="secondary receipt-btn" data-id="${safe(p.id)}">${p.receiptGenerated?"Open receipt":"Create receipt"}</button>
          <button class="secondary assign-btn" data-id="${safe(p.id)}" ${p.receiptGenerated?"":"disabled"}>Assign / Unassign</button>
          <button class="secondary edit-btn" data-id="${safe(p.id)}">Edit</button>
          <button class="secondary delete-btn" data-id="${safe(p.id)}">Delete</button>
        </div></td></tr>`).join("")}</tbody></table></div>`:
        `<div class="empty">No customer payments recorded in this test entity.</div>`}</div>`;
  }
  window.demoModule=function (tab){
    const e=activeEntity();
    if(!e){
      view.innerHTML=notice+`<div class="panel"><h2>Select a test entity first</h2><p class="muted">Go to Dashboard, add an entity and make it active.</p><button id="demoDashboard">Open Dashboard</button></div>`;
      document.getElementById("demoDashboard").onclick=()=>{activePage="Dashboard";render();};
      return;
    }
    const data=pm(),prj=selectedProject(),payments=data.payments.filter(p=>p.entityId===e.id);
    view.innerHTML=notice+`<div class="panel pm-toolbar"><div class="row"><strong>${safe(e.name)}</strong>
      <span class="muted">Active project</span>
      <select id="demoProjectChoice" aria-label="Project for current session"><option value="">No project</option>${projectSelect(prj?.id)}</select></div>
      <span class="pill">Browser-only test • no cloud writes</span></div>`+
      (tab==="Project Management"?projectPage(prj,payments):paymentPage(prj,payments))+
      `<dialog id="pmDialog"></dialog>`;
    document.getElementById("demoProjectChoice").onchange=ev=>{
      sessionStorage.setItem(SESSION_PREFIX+e.id,ev.target.value);demoModule(tab);
    };
    if(tab==="Project Management"){
      document.getElementById("addCustomer").onclick=addCustomer;
      document.getElementById("addProject").onclick=addProject;
      document.getElementById("addInstallment").onclick=addPlan;
    } else {
      document.getElementById("recordPayment").onclick=recordPayment;
      document.querySelectorAll(".receipt-btn").forEach(b=>b.onclick=()=>{receipt(b.dataset.id);save();});
      document.querySelectorAll(".assign-btn").forEach(b=>b.onclick=()=>assignmentDialog(b.dataset.id));
      document.querySelectorAll(".edit-btn").forEach(b=>b.onclick=()=>editPayment(b.dataset.id));
      document.querySelectorAll(".delete-btn").forEach(b=>b.onclick=()=>deletePayment(b.dataset.id));
    }
  };
})();
