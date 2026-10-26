/* Browser-only Customer SOA and Invoice preview.
 * Expected contract installments are NOT invoices or accounts receivable.
 * All data here is demo-only and never sent to any remote API.
 */
(function () {
  "use strict";
  const PREFIX = "next-accountant-demo-soa:";
  function data() {
    if (!state.pmDemo) state.pmDemo = {customers:[],projects:[],plans:[],payments:[],allocations:[],invoices:[]};
    if (!Array.isArray(state.pmDemo.invoices)) state.pmDemo.invoices = [];
    return state.pmDemo;
  }
  function safe(value) { return esc(value == null ? "" : value); }
  function fmt(value) { return money(value / 100); }
  function uuid() {
    return typeof crypto.randomUUID === "function" ? crypto.randomUUID() :
      "demo-" + Date.now() + "-" + Math.random().toString(36).slice(2);
  }
  function customersFor(entityId) { return data().customers.filter(x => x.entityId === entityId); }
  function projectsFor(entityId, customerId) {
    return data().projects.filter(x => x.entityId === entityId && x.customerId === customerId);
  }
  function csvCell(value) {
    const raw = String(value == null ? "" : value);
    // Prevent spreadsheet formula execution when importing a CSV.
    const neutral = /^[\s]*[=+\-@\t\r]/.test(raw) ? "'" + raw : raw;
    return '"' + neutral.replace(/"/g, '""') + '"';
  }
  function statement(entityId, customerId) {
    const source = data();
    const invoices = source.invoices.filter(x => x.entityId === entityId && x.customerId === customerId);
    const payments = source.payments.filter(x => x.entityId === entityId && x.customerId === customerId);
    const entries = invoices.map(x => ({id:x.id,date:x.date,kind:"Invoice",reference:x.reference,detail:x.projectName || source.projects.find(p => p.id === x.projectId)?.name || "",debit:x.amountCents,credit:0}))
      .concat(payments.map(x => ({id:x.id,date:x.date,kind:"Payment",reference:x.reference,detail:x.method || "",debit:0,credit:x.amountCents})))
      .sort((a,b) => a.date.localeCompare(b.date) || a.kind.localeCompare(b.kind) || a.reference.localeCompare(b.reference) || a.id.localeCompare(b.id));
    let running = 0;
    for (const entry of entries) {
      running += entry.debit - entry.credit;
      entry.balance = running;
    }
    const invoiced = invoices.reduce((a,x)=>a+x.amountCents,0);
    const received = payments.reduce((a,x)=>a+x.amountCents,0);
    return {entries,invoiced,received,balance:invoiced-received,invoiceCount:invoices.length,paymentCount:payments.length};
  }
  function invoiceDialog(entityId, customerId) {
    const choices = projectsFor(entityId,customerId);
    if (!choices.length) return alert("Create a project for this customer first.");
    const dialog = document.getElementById("pmDialog");
    dialog.innerHTML =
      '<form class="pm-form" id="soaInvoiceForm">' +
      '<header><h2>New demo customer invoice</h2><button type="button" class="secondary" id="pmCancel">Close</button></header>' +
      '<p class="muted">Invoices are recorded separately from contract payment-plan milestones. This is test data only.</p>' +
      '<label class="pm-field">Project<select name="projectId" required>' +
      choices.map(x => '<option value="' + safe(x.id) + '">' + safe(x.name) + '</option>').join("") +
      '</select></label>' +
      '<label class="pm-field">Invoice number<input name="reference" maxlength="100" required></label>' +
      '<label class="pm-field">Invoice date<input name="date" type="date" required value="' + new Date().toISOString().slice(0,10) + '"></label>' +
      '<label class="pm-field">Invoice total (QAR)<input name="amount" type="number" min="0.01" step="0.01" required></label>' +
      '<div class="dialog-actions"><button type="submit">Save demo invoice</button></div></form>';
    dialog.querySelector("#pmCancel").onclick=()=>dialog.close();
    dialog.querySelector("#soaInvoiceForm").onsubmit=event=>{
      event.preventDefault();
      try {
        const form = new FormData(event.currentTarget);
        const projectId = String(form.get("projectId") || "");
        if (!choices.some(x => x.id === projectId)) throw Error("Invalid project selection.");
        const reference = String(form.get("reference") || "").trim();
        const date = String(form.get("date") || "");
        const amount = Number(form.get("amount"));
        if (!reference) throw Error("Invoice number is required.");
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw Error("Invalid invoice date.");
        if (!Number.isFinite(amount) || amount <= 0 || !Number.isSafeInteger(Math.round(amount*100)))
          throw Error("Invalid invoice amount.");
        if (data().invoices.some(x => x.entityId === entityId && x.reference.toLowerCase() === reference.toLowerCase()))
          throw Error("This invoice number is already used within this entity.");
        data().invoices.push({id:uuid(),entityId,customerId,projectId,reference,date,amountCents:Math.round(amount*100)});
        save();
        dialog.close();
        window.demoSoa();
      } catch (error) { alert(error.message || "Cannot save invoice."); }
    };
    dialog.showModal();
  }
  function exportCsv(customer, statementData) {
    const cols = ["Date","Type","Reference","Detail","Invoice (QAR)","Payment (QAR)","Running balance (QAR)"];
    const rows = statementData.entries.map(x => [x.date,x.kind,x.reference,x.detail,
      (x.debit/100).toFixed(2),(x.credit/100).toFixed(2),(x.balance/100).toFixed(2)]);
    const csv = "\uFEFF" + [cols,...rows].map(row => row.map(csvCell).join(",")).join("\r\n");
    const file = new Blob([csv],{type:"text/csv;charset=utf-8"});
    const url = URL.createObjectURL(file);
    const element = document.createElement("a");
    element.href = url;
    element.download = "DEMO-customer-soa-" + new Date().toISOString().slice(0,10) + ".csv";
    element.click();
    URL.revokeObjectURL(url);
  }
  window.demoSoa = function () {
    const entity = activeEntity();
    if (!entity) {
      view.innerHTML = '<div class="demo-warning">DEMO WORKSPACE — no company data.</div><div class="panel"><h2>Select a test entity first</h2><button id="demoDashboard">Open Dashboard</button></div>';
      document.getElementById("demoDashboard").onclick=()=>{activePage="Dashboard";render();};
      return;
    }
    const customers = customersFor(entity.id);
    const key = PREFIX + entity.id;
    const requested = sessionStorage.getItem(key);
    const customer = customers.find(x=>x.id===requested) || customers[0] || null;
    if (customer && customer.id !== requested) sessionStorage.setItem(key,customer.id);
    const ledger = customer ? statement(entity.id,customer.id) : null;
    const balance = ledger?.balance || 0;
    const rows = ledger?.entries.map(x =>
      '<tr><td>' + safe(x.date) + '</td><td>' + safe(x.kind) + '</td><td><strong>' + safe(x.reference) + '</strong></td>' +
      '<td>' + safe(x.detail) + '</td><td>' + (x.debit ? fmt(x.debit) : "—") + '</td><td>' +
      (x.credit ? fmt(x.credit) : "—") + '</td><td>' + fmt(x.balance) + '</td></tr>').join("") || "";
    view.innerHTML =
      '<div class="demo-warning">DEMO CUSTOMER SOA — browser-only test invoices and payments. This is NOT an official Xero/Windows statement. Payment proofs are optional. Contract installments are excluded from invoiced totals.</div>' +
      '<div class="panel"><div class="panel-head"><div><h2>Customer Statement of Account</h2><p class="muted">Invoices create charges; actual received payments create credits, whether or not assigned to an installment.</p></div>' +
      '<div class="row"><button class="secondary" id="soaCsv"' + (!customer?' disabled':'') + '>Export demo CSV</button><button id="soaAddInvoice"' + (!customer || !projectsFor(entity.id,customer.id).length?' disabled':'') + '>+ Invoice</button></div></div>' +
      (customers.length ?
        '<label class="pm-field" style="max-width:420px">Customer<select id="soaCustomer">' +
        customers.map(x=>'<option value="' + safe(x.id) + '"' + (x.id===customer?.id?' selected':'') + '>' + safe(x.name) + '</option>').join("") + '</select></label>' :
        '<div class="empty">No test customers yet. Add a customer and project in Project Management.</div>') +
      '</div>' +
      (customer ?
        '<div class="cards">' +
        '<div class="card"><div class="metric-label">Invoiced</div><div class="metric">' + fmt(ledger.invoiced) + '</div></div>' +
        '<div class="card"><div class="metric-label">Received</div><div class="metric">' + fmt(ledger.received) + '</div></div>' +
        '<div class="card"><div class="metric-label">' + (balance >= 0 ? 'Net balance due' : 'Net customer credit') + '</div><div class="metric">' + fmt(Math.abs(balance)) + '</div></div>' +
        '<div class="card"><div class="metric-label">Transactions</div><div class="metric">' + ledger.entries.length + '</div></div>' +
        '</div><div class="panel"><div class="panel-head"><h2>' + safe(customer.name) + ' — transaction ledger</h2><span class="pill">QAR • Demo only</span></div>' +
        (ledger.entries.length ?
          '<div class="pm-scroll"><table class="soa-table"><thead><tr><th>Date</th><th>Type</th><th>Reference</th><th>Detail</th><th>Invoice</th><th>Payment</th><th>Running balance</th></tr></thead><tbody>' + rows + '</tbody></table></div>' :
          '<div class="empty">No invoice or payment transactions for this customer.</div>') +
        '<p class="muted">Balances use only the demo transactions entered here. Aging, tax, opening balances, allocation to invoices, and official PDF styling require reconciliation with the Windows system.</p></div>' : '') +
      '<dialog id="pmDialog"></dialog>';
    if (customer) {
      document.getElementById("soaCustomer").onchange=e=>{
        sessionStorage.setItem(key,e.target.value);
        window.demoSoa();
      };
      document.getElementById("soaAddInvoice").onclick=()=>invoiceDialog(entity.id,customer.id);
      document.getElementById("soaCsv").onclick=()=>exportCsv(customer,ledger);
    }
  };
})();
