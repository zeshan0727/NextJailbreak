// Finance integrity aggregates used exclusively by the Windows local reconcilor.
// Only the authenticated staging owner may access this endpoint. The public web
// session can NEVER call this API, or alter the underlying V6 rows.
const sums = [
  ["SalesInvoices","SELECT COUNT(*) AS Count, COALESCE(SUM(Amount),0) AS Total FROM SalesInvoices"],
  ["PaymentVouchers","SELECT COUNT(*) AS Count, COALESCE(SUM(Amount),0) AS Total FROM PaymentVouchers"],
  ["ReceiptVouchers","SELECT COUNT(*) AS Count, COALESCE(SUM(Amount),0) AS Total FROM ReceiptVouchers"],
  ["PMPayments","SELECT COUNT(*) AS Count, COALESCE(SUM(Amount),0) AS Total FROM PMPayments"],
  ["PMPaymentPlan","SELECT COUNT(*) AS Count, COALESCE(SUM(Amount),0) AS Total FROM PMPaymentPlan"],
  ["PMPaymentPlanAllocations","SELECT COUNT(*) AS Count, COALESCE(SUM(Amount),0) AS Total FROM PMPaymentPlanAllocations"]
];
function secureJson(body,status=200) {
  return new Response(JSON.stringify(body), {status, headers:{
    "Cache-Control":"private, no-store",
    "Content-Type":"application/json; charset=utf-8",
    "X-Content-Type-Options":"nosniff"
  }});
}
export async function financeFingerprint(request,env) {
  if(request.method!=="GET")return secureJson({error:"Read only."},405);
  if(env.MIGRATION_ENV!=="staging")return secureJson({error:"Staging only."},503);
  const result = [];
  for(const [name,sql] of sums) {
    const r=await env.DB.prepare(sql).first();
    if(!r||!Number.isFinite(Number(r.Total))||!Number.isSafeInteger(Number(r.Count)))
      return secureJson({error:"Unable to calculate accounting fingerprint."},503);
    result.push({name,count:Number(r.Count),total:Number(r.Total)});
  }
  const index=await env.DB.prepare("SELECT COUNT(*) AS total FROM WebFileIndex").first();
  return secureJson({
    schemaVersion:21,
    fileIndexCount:Number(index?.total||0),
    aggregates:result
  });
}
