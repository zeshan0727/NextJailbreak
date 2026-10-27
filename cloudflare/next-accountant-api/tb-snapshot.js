// Owner-only snapshot-account integrity check of imported manager-report data.
// Aggregated account values are compared to the same original local V6 backup.
// This confirms storage parity, NOT financial statement correctness or export parity.
export async function trialBalanceSnapshotFingerprint(request,env){
  if(env.MIGRATION_ENV!=='staging')
    return Response.json({error:'Staging only.'},{status:503});
  if(request.method!=='GET')
    return Response.json({error:'Read only.'},{status:405});
  const result=await env.DB.prepare(
    "SELECT SnapshotId, COUNT(*) AS Count," +
    "COALESCE(SUM(DebitYtd),0) AS DebitYtd," +
    "COALESCE(SUM(CreditYtd),0) AS CreditYtd," +
    "COALESCE(SUM(CurrentBalance),0) AS CurrentBalance," +
    "COALESCE(SUM(CASE WHEN DebitYtd IS NULL OR CreditYtd IS NULL " +
      "OR CurrentBalance IS NULL THEN 1 ELSE 0 END),0) AS NullEntries " +
    "FROM ManagerReportAccountsV6A GROUP BY SnapshotId ORDER BY SnapshotId"
  ).all();
  const groups=(result.results||[]).map(x=>({
    snapshotId:x.SnapshotId===null?null:String(x.SnapshotId),
    count:Number(x.Count),debitYtd:Number(x.DebitYtd),
    creditYtd:Number(x.CreditYtd),currentBalance:Number(x.CurrentBalance),
    nullEntries:Number(x.NullEntries)
  }));
  if(groups.length>5000 || groups.some(x=>x.count<1 || 
     !Number.isSafeInteger(x.count)||!Number.isFinite(x.debitYtd)||
     !Number.isFinite(x.creditYtd)||!Number.isFinite(x.currentBalance)))
    return Response.json({error:'Unverifiable trial balance snapshot data.'},{status:503});
  return new Response(JSON.stringify({groups,count:groups.length}),{headers:{
    'Cache-Control':'private, no-store',
    'Content-Type':'application/json; charset=utf-8',
    'X-Content-Type-Options':'nosniff',
    'Referrer-Policy':'no-referrer'
  }});
}
