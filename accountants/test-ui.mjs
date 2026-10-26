import {readFileSync} from "node:fs";
import {JSDOM} from "jsdom";
import {strict as assert} from "node:assert";

const html=readFileSync("accountants/index.html","utf8");
const app=readFileSync("accountants/app.js","utf8");
const pm=readFileSync("accountants/project-demo.js","utf8");
const dom=new JSDOM(html,{url:"https://nextjailbreak.com/accountants/",runScripts:"dangerously"});
const {window:w}=dom;
w.HTMLDialogElement.prototype.showModal=function(){this.open=true;};
w.HTMLDialogElement.prototype.close=function(){this.open=false;};
w.confirm=()=>true;
const alerts=[];
w.alert=message=>alerts.push(message);
for (const source of [pm,app]) {
  const script=w.document.createElement("script");
  script.textContent=source;
  w.document.body.appendChild(script);
}
const d=w.document;
const $=selector=>{const n=d.querySelector(selector);assert.ok(n, "Missing element: "+selector);return n;};
const click=selector=>$(selector).click();
const fill=(selector,value)=>{
  const element=$(selector);
  element.value=value;
  element.dispatchEvent(new w.Event("change",{bubbles:true}));
};
const submit=selector=>{
  const form=$(selector);
  form.dispatchEvent(new w.Event("submit",{bubbles:true,cancelable:true}));
};
const nav=name=>{
  const item=[...d.querySelectorAll(".nav-btn")].find(x=>x.dataset.page===name);
  assert.ok(item,"Missing nav item: "+name);
  item.click();
};
const close=()=>{if(d.querySelector("#pmCancel"))click("#pmCancel");};
const state=()=>JSON.parse(w.localStorage.getItem("next-accountant-free-preview-v1"));
function record(reference,value){
  click("#recordPayment");
  fill('#pmForm [name="reference"]',reference);
  fill('#pmForm [name="amount"]',String(value));
  fill('#pmForm [name="date"]',"2026-10-26");
  submit("#pmForm");
  const row=[...d.querySelectorAll(".receipt-btn")].find(x=>{
    const payment=state().pmDemo.payments.find(p=>p.id===x.dataset.id);
    return payment?.reference===reference;
  });
  assert.ok(row,"Recorded payment not shown: "+reference);
  row.click();
  assert.match($("#pmDialog").textContent,/PAYMENT RECEIPT/);
  assert.match($("#pmDialog").textContent,new RegExp(reference));
  close();
  const assign=[...d.querySelectorAll(".assign-btn")].find(x=>x.dataset.id===row.dataset.id);
  assert.ok(assign && !assign.disabled,"Assign must be available after creating receipt");
  assign.click();
  fill('#allocationForm [name="amount"]',String(value));
  submit("#allocationForm");
  close();
}

click("#addEntity");
fill("#entityName","Demo Barjous");
submit("#entityForm");
nav("Project Management");
click("#addCustomer");
fill('#pmForm [name="name"]',"Example Customer");
submit("#pmForm");
click("#addProject");
fill('#pmForm [name="name"]',"Project Test A");
submit("#pmForm");
click("#addInstallment");
fill('#pmForm [name="label"]',"Fifth Installment");
fill('#pmForm [name="amount"]',"50000");
fill('#pmForm [name="dueDate"]',"2026-12-01");
submit("#pmForm");
const projectId=state().pmDemo.projects[0].id;
assert.equal(w.sessionStorage.getItem("next-accountant-demo-project:"+state().activeEntityId),projectId);

nav("Payments / Receipts");
record("R1",20000);
record("R2",15000);
record("R3",15000);
let model=state().pmDemo;
assert.equal(model.plans.length,1);
assert.equal(model.allocations.length,3);
assert.equal(model.allocations.reduce((n,x)=>n+x.amountCents,0),5000000);
assert.equal(model.payments.filter(x=>x.receiptGenerated).length,3);
assert.equal(model.payments.map(x=>x.reference).join(","),"R1,R2,R3");

// Unassign/reassign one receipt without losing the project's session selection.
const third=model.payments[2];
const assign=[...d.querySelectorAll(".assign-btn")].find(x=>x.dataset.id===third.id);
assign.click();
click(".unassign");
model=state().pmDemo;
assert.equal(model.allocations.length,2);
fill('#allocationForm [name="amount"]',"15000");
submit("#allocationForm");
close();
model=state().pmDemo;
assert.equal(model.allocations.length,3);
assert.equal(model.allocations.reduce((n,x)=>n+x.amountCents,0),5000000);

// Edits and deletes must be available and properly adjust demo allocations.
const first=model.payments[0];
click('.edit-btn[data-id="'+first.id+'"]');
fill('#pmForm [name="amount"]',"19000");
submit("#pmForm");
assert.ok(alerts.some(x=>String(x).includes("Unassign first")),"Allocated payment should not shrink below assigned value.");
close();
click('.delete-btn[data-id="'+third.id+'"]');
model=state().pmDemo;
assert.equal(model.payments.length,2);
assert.equal(model.allocations.length,2);
nav("Project Management");
assert.equal($("#demoProjectChoice").value,projectId);
assert.ok(!d.querySelector('script[src*="adsterra"]'));
assert.ok(!d.querySelector('script[src*="googletagmanager"]'));
console.log("PASS web UI: customer/project/installment; 3 receipts and partial allocation; assign/unassign; edit guard; delete; session project persistence; ad-free.");
