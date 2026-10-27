import hashlib
import json
import urllib.request
import urllib.error

BASE = "http://127.0.0.1:8787"
TOKEN = "synthetic-fixture-only"

def call(path, method="GET", body=None, headers=None, authorized=True):
    h = {"Content-Type":"application/json"}
    if authorized:
        h["Authorization"] = "Bearer " + TOKEN
    if headers:
        h.update(headers)
    if isinstance(body, (dict,list)):
        body=json.dumps(body).encode()
    request=urllib.request.Request(BASE+path,method=method,headers=h,data=body)
    try:
        with urllib.request.urlopen(request,timeout=15) as r:
            content=r.read()
            return r.status, dict(r.headers), json.loads(content) if content and r.headers.get("Content-Type","").startswith("application/json") else content
    except urllib.error.HTTPError as e:
        return e.code,dict(e.headers),e.read().decode()

status, _, health=call("/health",authorized=False)
assert status==200 and health["environment"]=="staging" and health["database"] and health["files"],health

status,_,_=call("/api/admin/tables",authorized=False)
assert status==401, status

# Reproduce the actual Windows 0.2.0 migrator payload: SQL statement
# definitions spread across many lines and a semicolon in a quoted string.
sql=("PRAGMA foreign_keys = ON;\n"
     "CREATE TABLE IF NOT EXISTS SmokePlan (\n"
     "  Id TEXT PRIMARY KEY,\n"
     "  Planned INTEGER NOT NULL,\n"
     "  Note TEXT DEFAULT 'pending; review'\n"
     ");\n"
     "CREATE TABLE IF NOT EXISTS SmokePayment (\n"
     "  Id TEXT PRIMARY KEY,\n"
     "  PlanId TEXT NOT NULL REFERENCES SmokePlan(Id),\n"
     "  Amount INTEGER NOT NULL\n"
     ");\n"
     "CREATE TABLE IF NOT EXISTS SmokeBinary (Id INTEGER PRIMARY KEY, Bytes BLOB);\n"
     "CREATE INDEX IF NOT EXISTS SmokePaymentPlanIdx ON SmokePayment(PlanId);\n")
status,_,result=call("/api/admin/apply-schema","POST",{"sql":sql,"sourceSchemaVersion":21})
assert status==200 and result["ok"] and result["created"]==4, (status,result)

# Replaying CREATE definitions must be safe if the previous attempt ended
# after some successful schema statements, but must reject incompatible DDL.
status,_,replay=call("/api/admin/apply-schema","POST",{"sql":sql,"sourceSchemaVersion":21})
assert status==200 and replay["reused"]==4 and replay["created"]==0,(status,replay)
conflict="PRAGMA foreign_keys = ON;\nCREATE TABLE SmokePlan (Id TEXT PRIMARY KEY, Planned TEXT);"
status,_,_=call("/api/admin/apply-schema","POST",{"sql":conflict,"sourceSchemaVersion":21})
assert status==409,status
danger="PRAGMA foreign_keys = ON;\nDROP TABLE SmokePlan;"
status,_,_=call("/api/admin/apply-schema","POST",{"sql":danger,"sourceSchemaVersion":21})
assert status==400,status

status,_,data=call("/api/admin/import-batch","POST",{"table":"SmokePlan","rows":[{"Id":"fifth","Planned":50000}]})
assert status==200 and data["imported"]==1,(status,data)

payments=[{"Id":"R1","PlanId":"fifth","Amount":20000},
          {"Id":"R2","PlanId":"fifth","Amount":15000},
          {"Id":"R3","PlanId":"fifth","Amount":15000}]
status,_,result=call("/api/admin/import-batch","POST",{"table":"SmokePayment","rows":payments})
assert status==200 and result["imported"]==3,(status,result)

status,_,rows=call("/api/admin/export-table?table=SmokePayment")
assert status==200 and sum(row["Amount"] for row in rows["rows"])==50000,rows

status,_,result=call("/api/admin/import-batch","POST",{"table":"SmokePayment","rows":[payments[0]]})
assert status!=200, "Duplicate payment unexpectedly replaced."

status,_,result=call("/api/admin/import-batch","POST",{"table":"SmokeBinary","rows":[{"Id":1,"Bytes":{"$base64":"AQIDBA=="}}]})
assert status==200,(status,result)

status,_,counts=call("/api/admin/counts?page=0")
assert status==200 and counts["page"]==0 and isinstance(counts["hasMore"],bool),counts
all_counts={}
page=0
while True:
    status,_,item=call("/api/admin/counts?page="+str(page))
    assert status==200,(status,item)
    for t in item["tables"]:
        all_counts[t["name"]]=t["count"]
    if not item["hasMore"]:
        break
    page+=1
    assert page < 100
assert all_counts["SmokePayment"]==3 and all_counts["SmokePlan"]==1,all_counts

blob=b"synthetic file smoke test"
digest=hashlib.sha256(blob).hexdigest()
status,_,response=call("/api/files/smoke/test.txt","PUT",blob,
 {"Content-Type":"text/plain","X-File-Name":"test.txt","X-Expected-Sha256":digest})
assert status==200 and response["sha256"]==digest,(status,response)
status,headers,_=call("/api/files/smoke/test.txt","HEAD")
assert status==200 and headers.get("X-File-Sha256")==digest,(status,headers)

status,_,replay=call("/api/files/smoke/test.txt","PUT",blob,
 {"Content-Type":"text/plain","X-File-Name":"test.txt","X-Expected-Sha256":digest})
assert status==200 and replay.get("unchanged")==True,(status,replay)

status,_,_=call("/api/files/smoke/test.txt","DELETE")
assert status==405, "Migration credential must not delete R2 files."
status,headers,_=call("/api/files/smoke/test.txt","HEAD")
assert status==200 and headers.get("X-File-Sha256")==digest, "Failed DELETE must preserve R2 file."

print("PASS: staging identity, locked admin, DDL, FK, three-receipt allocation, BLOB, paged counts, file SHA, and idempotent R2.")
