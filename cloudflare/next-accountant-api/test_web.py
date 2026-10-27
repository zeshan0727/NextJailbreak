# Synthetic-only web gateway tests. Never use the real business database.
import hashlib
import json
import urllib.request
import urllib.error
from urllib.parse import quote

HOST="http://127.0.0.1:8787"
OWNER="synthetic-fixture-only"
def req(path,method="GET",body=None,bearer=False,cookie=None,follow=True,origin=None,extra_headers=None):
    headers={"Accept":"application/json"}
    if bearer:headers["Authorization"]="Bearer "+OWNER
    if cookie:headers["Cookie"]=cookie
    if origin:headers["Origin"]=origin
    if extra_headers:headers.update(extra_headers)
    if isinstance(body,(dict,list)):
        body=json.dumps(body).encode()
        headers["Content-Type"]="application/json"
    elif method=="POST" and body is None:body=b""
    request=urllib.request.Request(HOST+path,method=method,headers=headers,data=body)
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*args):return None
    opener=urllib.request.build_opener() if follow else urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(request,timeout=30) as response:
            text=response.read().decode()
            try:data=json.loads(text)
            except:data=text
            return response.status,dict(response.headers),data
    except urllib.error.HTTPError as e:
        content=e.read().decode()
        try:data=json.loads(content)
        except:data=content
        return e.code,dict(e.headers),data

# Test the identical allowlisted column structure used by the imported V6.
sql=[
"CREATE TABLE Entities(Id INTEGER PRIMARY KEY,Name TEXT,Code TEXT,IsActive INTEGER)",
"CREATE TABLE SalesInvoices(Id INTEGER PRIMARY KEY,EntityId INTEGER,InvoiceNumber TEXT,InvoiceDate TEXT,CustomerName TEXT,Amount REAL,Year INTEGER,Month INTEGER,IsCancelled INTEGER)",
"CREATE TABLE PaymentVouchers(Id INTEGER PRIMARY KEY,EntityId INTEGER,VoucherNo TEXT,VoucherDate TEXT,Payee TEXT,Amount REAL,Currency TEXT,Category TEXT,PaymentMode TEXT,Purpose TEXT)",
"CREATE TABLE ReceiptVouchers(Id INTEGER PRIMARY KEY,EntityId INTEGER,ReceiptNo TEXT,ReceiptDate TEXT,ReceivedFrom TEXT,Amount REAL,Currency TEXT,ReceiptType TEXT,ReferenceNo TEXT)",
"CREATE TABLE PMCustomers(Id INTEGER PRIMARY KEY,EntityId INTEGER,CustomerName TEXT)",
"CREATE TABLE PMProjects(Id INTEGER PRIMARY KEY,CustomerId INTEGER,ProjectCode TEXT,ProjectName TEXT,Status TEXT,CreatedAt TEXT)",
"CREATE TABLE PMPaymentPlan(Id INTEGER PRIMARY KEY,ProjectId INTEGER,SequenceNo INTEGER,Title TEXT,DueDate TEXT,Percentage REAL,Amount REAL,Currency TEXT)",
"CREATE TABLE PMPayments(Id INTEGER PRIMARY KEY,CustomerId INTEGER,ProjectId INTEGER,PaymentDate TEXT,Reference TEXT,Amount REAL,PaymentMethod TEXT,IsAdvance INTEGER)",
"CREATE TABLE PMPaymentPlanAllocations(Id INTEGER PRIMARY KEY,PaymentPlanId INTEGER,PaymentId INTEGER,ReceivedDate TEXT,Amount REAL)",
"CREATE TABLE Customers(Id INTEGER PRIMARY KEY,EntityId INTEGER,Reference TEXT,ContactName TEXT,NeedsReview INTEGER)",
"CREATE TABLE Employees(Id INTEGER PRIMARY KEY,EntityId INTEGER,EmployeeNo TEXT,Name TEXT,Position TEXT,Department TEXT,IsActive INTEGER)",
"CREATE TABLE DailyTasks(Id INTEGER PRIMARY KEY,EntityId INTEGER,Title TEXT,Status TEXT,Priority TEXT,DueAt TEXT,CreatedAt TEXT,UpdatedAt TEXT)",
]
for i in range(0,len(sql),8):
    status,_,response=req("/api/admin/apply-schema","POST",
        {"sql":"PRAGMA foreign_keys = ON;\n"+";\n".join(sql[i:i+8])+";",
         "sourceSchemaVersion":21},bearer=True)
    assert status==200,(status,response)
rows={
"Entities":[{"Id":1,"Name":"Synthetic Stone Cafe","Code":"SC","IsActive":1},{"Id":2,"Name":"Unmanaged Company","Code":"X","IsActive":1}],
"SalesInvoices":[{"Id":3,"EntityId":1,"InvoiceNumber":"TEST-INV-3","InvoiceDate":"2026-10-01","CustomerName":"Test Customer","Amount":500.25,"Year":2026,"Month":10,"IsCancelled":0}],
"PaymentVouchers":[{"Id":8,"EntityId":1,"VoucherNo":"PV-8","VoucherDate":"2026-10-02","Payee":"Test Payee","Amount":100.0,"Currency":"QAR","Category":"Services","PaymentMode":"Bank","Purpose":"Synthetic"}],
"ReceiptVouchers":[{"Id":9,"EntityId":1,"ReceiptNo":"RV-9","ReceiptDate":"2026-10-03","ReceivedFrom":"Test","Amount":125.5,"Currency":"QAR","ReceiptType":"Bank","ReferenceNo":"T-9"}],
"PMCustomers":[{"Id":1,"EntityId":1,"CustomerName":"Synthetic Customer"}],
"PMProjects":[{"Id":1,"CustomerId":1,"ProjectCode":"SC-1","ProjectName":"Synthetic Project","Status":"Active","CreatedAt":"2026-10-01"}],
"PMPaymentPlan":[{"Id":1,"ProjectId":1,"SequenceNo":1,"Title":"Installment","DueDate":"2026-12-01","Percentage":100,"Amount":300.0,"Currency":"QAR"}],
"PMPayments":[{"Id":1,"CustomerId":1,"ProjectId":1,"PaymentDate":"2026-10-04","Reference":"PAY-1","Amount":125.0,"PaymentMethod":"Bank","IsAdvance":0}],
"PMPaymentPlanAllocations":[{"Id":1,"PaymentPlanId":1,"PaymentId":1,"ReceivedDate":"2026-10-04","Amount":100.0}],
"Customers":[{"Id":1,"EntityId":1,"Reference":"C1","ContactName":"Synthetic Contact","NeedsReview":0}],
"Employees":[{"Id":1,"EntityId":1,"EmployeeNo":"T001","Name":"Synthetic Person","Position":"Accountant","Department":"Finance","IsActive":1}],
"DailyTasks":[{"Id":1,"EntityId":1,"Title":"Review synthetic voucher","Status":"Open","Priority":"Normal","DueAt":"2026-11-05","CreatedAt":"2026-10-27","UpdatedAt":"2026-10-27"}]
}
for table,payload in rows.items():
    status,_,result=req("/api/admin/import-batch","POST",{"table":table,"rows":payload},bearer=True)
    assert status==200,(table,status,result)

# The web route is not public even though static UI source may be loaded.
status,_,_=req("/api/web/entities")
assert status==401,status
status,_,_=req("/web")
assert status==401,status
status,_,_=req("/api/web/session/start","POST")
assert status==401,status
status,_,ticket=req("/api/web/session/start","POST",bearer=True)
assert status==200 and ticket["ok"] and ticket["expiresInSeconds"]<=90,(status,ticket)
target=ticket["launchUrl"]
assert target.startswith(HOST+"/web/activate?ticket="),target
ticket_value=target.split("ticket=",1)[1]
assert len(ticket_value)==64 and all(c in "0123456789abcdef" for c in ticket_value)
status,headers,_=req("/web/activate?ticket="+ticket_value,follow=False)
assert status==303 and headers.get("Location")=="/web",(status,headers)
full_cookie=headers.get("Set-Cookie","")
assert "HttpOnly" in full_cookie and "Secure" in full_cookie and "SameSite=Strict" in full_cookie
browser_cookie=full_cookie.split(";",1)[0]
status,_,_=req("/web/activate?ticket="+ticket_value,follow=False)
assert status==401,"One-time login ticket was re-used"
status,_,html=req("/web",cookie=browser_cookie)
assert status==200 and "Next Accountant" in html,(status,html[:200])
status,_,entities=req("/api/web/entities",cookie=browser_cookie)
assert status==200 and len(entities["entities"])==1 and entities["entities"][0]["Name"]=="Synthetic Stone Cafe",entities
status,_,_=req("/api/web/overview?entityId=2",cookie=browser_cookie)
assert status==404,"Unauthorized company visible through direct ID request"
status,_,_=req("/api/web/records?type=Invoices&entityId=2",cookie=browser_cookie)
assert status==404,"Unmanaged entity is accessible from records endpoint"
status,_,summary=req("/api/web/overview?entityId=1",cookie=browser_cookie)
assert status==200 and summary["invoiceCount"]==1 and summary["invoiceAmount"]==500.25,summary
assert summary["paymentCount"]==1 and summary["receiptCount"]==1,summary
status,_,contracts=req("/api/web/contracts?entityId=1",cookie=browser_cookie)
assert status==200 and len(contracts["projects"])==1 and contracts["projects"][0]["Allocated"]==100.0,contracts
status,_,plans=req("/api/web/records?type=Plans&entityId=1&page=0",cookie=browser_cookie)
assert status==200 and plans["total"]==1 and plans["rows"][0]["Amount"]==300.0,plans
status,_,employees=req("/api/web/records?type=Employees&entityId=1",cookie=browser_cookie)
assert status==200 and employees["total"]==1 and employees["rows"][0]["EmployeeNo"]=="T001",(status,employees)
status,_,tasks=req("/api/web/records?type=Tasks&entityId=1",cookie=browser_cookie)
assert status==200 and tasks["total"]==1 and tasks["rows"][0]["Title"]=="Review synthetic voucher",(status,tasks)
status,_,invoice=req("/api/web/records?type=Invoices&entityId=1&page=0",cookie=browser_cookie)
assert status==200 and invoice["total"]==1 and invoice["rows"][0]["InvoiceNumber"]=="TEST-INV-3",invoice
status,_,_=req("/api/web/records?type=Invoices&entityId=1",method="POST",cookie=browser_cookie)
assert status==405,"Read-only endpoint permitted POST"
status,_,_=req("/api/admin/counts",cookie=browser_cookie)
assert status==401,"Viewer cookie incorrectly gave administrator access"
status,_,_=req("/api/admin/financial-fingerprint",cookie=browser_cookie)
assert status==401,"Read-only viewer session could read privileged financial reconciliation API"
status,_,fingerprint=req("/api/admin/financial-fingerprint",bearer=True)
assert status==200 and fingerprint["fileIndexCount"]>=0,(status,fingerprint)
fingerprints={x["name"]:x for x in fingerprint["aggregates"]}
assert fingerprints["SalesInvoices"]["count"]==1 and fingerprints["SalesInvoices"]["total"]==500.25,fingerprints
assert fingerprints["PMPayments"]["count"]==1 and fingerprints["PMPayments"]["total"]==125.0,fingerprints
assert fingerprints["PMPaymentPlanAllocations"]["total"]==100.0,fingerprints
status,_,_=req("/api/admin/financial-breakdown",cookie=browser_cookie)
assert status==401,"Read-only browser cookie exposed private financial reconciliation aggregates"
status,_,detail=req("/api/admin/financial-breakdown",bearer=True)
assert status==200 and detail["schemaVersion"]==21,(status,detail)
detail_by_name={x["name"]:x for x in detail["groups"]}
assert len(detail_by_name)==6,(status,detail)
assert detail_by_name["SalesInvoices"]["period"]=="2026-10",detail_by_name
assert detail_by_name["SalesInvoices"]["currency"]=="SOURCE",detail_by_name
assert detail_by_name["SalesInvoices"]["total"]==500.25,detail_by_name
assert detail_by_name["PaymentVouchers"]["currency"]=="QAR",detail_by_name
assert detail_by_name["PMPayments"]["currency"]=="UNSPECIFIED",detail_by_name
assert detail_by_name["PMPaymentPlanAllocations"]["total"]==100.0,detail_by_name
assert all(x["entityId"]==1 and x["nullAmounts"]==0 for x in detail["groups"]),detail
print("PASS: owner-only per-company/month/currency accounting breakdown against original source schema.")
status,_,_=req("/api/web/records?type=SalaryHistory&entityId=1",cookie=browser_cookie)
assert status==400,"Unapproved payroll table was exposed"
status,_,_=req("/api/web/records?type=Invoices&entityId=1%20OR%201=1",cookie=browser_cookie)
assert status==400,"SQL injection-like ID accepted"

# PV / RV staging drafts: allow scoped writes in separate tables only.
new_pv={"entityId":1,"kind":"PV","date":"2026-10-04","currency":"QAR",
        "amountMinor":12550,"counterparty":"Test Payee",
        "narrative":"Synthetic transport cost","reference":"SYN-1"}
status,_,_=req("/api/web/drafts","POST",body=new_pv,origin=HOST)
assert status==401,"Anonymous draft creation was allowed"
status,_,_=req("/api/web/drafts","POST",body=new_pv,cookie=browser_cookie,
               origin="https://unrelated.example")
assert status==403,"Cross-origin draft creation was allowed"
bad=dict(new_pv,entityId=2)
status,_,_=req("/api/web/drafts","POST",body=bad,cookie=browser_cookie,origin=HOST)
assert status==404,"Unmanaged company draft was allowed"
status,_,created=req("/api/web/drafts","POST",body=new_pv,cookie=browser_cookie,origin=HOST)
assert status==201 and created["status"]=="DRAFT" and not created["postedToWindows"],(status,created)
draft=created["id"]
status,_,listed=req("/api/web/drafts?entityId=1",cookie=browser_cookie)
assert status==200 and len(listed["records"])==1 and listed["records"][0]["AmountMinor"]==12550,listed
status,_,untouched=req("/api/web/records?type=PaymentVouchers&entityId=1",cookie=browser_cookie)
assert status==200 and untouched["total"]==1,"Draft mutated source payment vouchers"
content=b"%PDF-1.4 synthetic private voucher proof"
encoded_doc="Test Proof 100%.pdf"
status,_,uploaded=req("/api/web/drafts/"+draft+"/document","PUT",body=content,
                      cookie=browser_cookie,origin=HOST,extra_headers={
                        "Content-Type":"application/pdf",
                        "X-File-Name-Encoded":quote(encoded_doc,safe="")
                      })
assert status==200 and uploaded["ok"] and not uploaded["postedToWindows"],(status,uploaded)
status,headers,returned=req("/api/web/drafts/"+draft+"/document",
                            cookie=browser_cookie)
assert status==200 and headers.get("X-Document-Sha256")==hashlib.sha256(content).hexdigest(),(status,headers)
status,_,again=req("/api/web/drafts/"+draft+"/document","PUT",body=content,
                   cookie=browser_cookie,origin=HOST,extra_headers={
                     "Content-Type":"application/pdf",
                     "X-File-Name-Encoded":quote(encoded_doc,safe="")
                   })
assert status==200 and again.get("unchanged") is True,(status,again)
status,_,conflict=req("/api/web/drafts/"+draft+"/document","PUT",body=b"different",
                      cookie=browser_cookie,origin=HOST,extra_headers={
                        "Content-Type":"application/pdf",
                        "X-File-Name-Encoded":"different.pdf"
                      })
assert status==409,"Draft file was overwritten"
status,_,_=req("/api/web/drafts?entityId=2",cookie=browser_cookie)
assert status==404,"Unmanaged company draft listing was allowed"
status,_,source_payments=req("/api/web/records?type=PaymentVouchers&entityId=1",cookie=browser_cookie)
assert status==200 and source_payments["total"]==1,"Draft wrote into imported Windows ledger"
print("PASS staging drafts: company scope, CSRF origin, PV creation, attachment, integrity, duplicate guard and source-ledger isolation.")


# Archived Windows-format reports remain unchanged in private R2, scoped by entity.
report_key="business/Audit/LegacyImported/Reports/Manager/Stone_Cafe/2026/2026-08-31/Smoke_Manager_Report.xlsx"
report_payload=b"synthetic original Excel archive fixture"
report_sha=hashlib.sha256(report_payload).hexdigest()
status,_,put=req("/api/files/"+quote(report_key,safe="/"),"PUT",
                 body=report_payload,bearer=True,extra_headers={
                   "Content-Type":"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                   "X-File-Name":"Smoke_Manager_Report.xlsx",
                   "X-File-Category":"V6BusinessBackup",
                   "X-Record-Type":"MigrationFile",
                   "X-Expected-Sha256":report_sha
                 })
assert status==200 and put["sha256"]==report_sha,(status,put)
status,_,archive=req("/api/web/manager-archive?entityId=1",cookie=browser_cookie)
assert status==200 and len(archive["files"])==1 and archive["files"][0]["Sha256"]==report_sha,(status,archive)
status,_,_=req("/api/web/manager-archive?entityId=2",cookie=browser_cookie)
assert status==404,"Unmanaged company can browse reports"
status,_,_=req("/api/web/manager-archive?entityId=1")
assert status==401,"Anonymous report archive can be browsed"
download="/api/web/manager-report-file?entityId=1&key="+quote(report_key,safe="")
status,headers,report=req(download,cookie=browser_cookie)
assert status==200 and headers["X-Report-Sha256"]==report_sha,(status,headers)
status,_,_=req("/api/web/manager-report-file?entityId=1&key="+quote(
  "business/Audit/LegacyImported/Reports/Manager/Erada_Fitness/private.xlsx",safe=""),
  cookie=browser_cookie)
assert status==404,"Cross-company report path was not blocked"
print("PASS: original report archive is integrity checked, authenticated and company-scoped.")

status,_,_=req("/api/web/logout","POST",cookie=browser_cookie,origin=HOST)
assert status==204,status
status,_,_=req("/api/web/entities",cookie=browser_cookie)
assert status==401,"Sign-out failed to revoke session"

print("PASS private staging: one-time token, HttpOnly read-only cookie, real-schema synthetic projections, scoped API, logout and rejected writes.")
