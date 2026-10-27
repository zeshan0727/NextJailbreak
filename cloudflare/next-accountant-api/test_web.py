# Synthetic-only web gateway tests. Never use the real business database.
import hashlib
import json
import urllib.request
import urllib.error
from urllib.parse import quote

HOST="http://127.0.0.1:8787"
OWNER="synthetic-fixture-only"
def req(path,method="GET",body=None,bearer=False,cookie=None,follow=True,origin=None):
    headers={"Accept":"application/json"}
    if bearer:headers["Authorization"]="Bearer "+OWNER
    if cookie:headers["Cookie"]=cookie
    if origin:headers["Origin"]=origin
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
"Customers":[{"Id":1,"EntityId":1,"Reference":"C1","ContactName":"Synthetic Contact","NeedsReview":0}]
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
status,_,_=req("/api/web/records?type=Employees&entityId=1",cookie=browser_cookie)
assert status==400,"Sensitive unapproved table was exposed"
status,_,_=req("/api/web/records?type=Invoices&entityId=1%20OR%201=1",cookie=browser_cookie)
assert status==400,"SQL injection-like ID accepted"
status,_,_=req("/api/web/logout","POST",cookie=browser_cookie,origin=HOST)
assert status==204,status
status,_,_=req("/api/web/entities",cookie=browser_cookie)
assert status==401,"Sign-out failed to revoke session"

print("PASS private staging: one-time token, HttpOnly read-only cookie, real-schema synthetic projections, scoped API, logout and rejected writes.")
