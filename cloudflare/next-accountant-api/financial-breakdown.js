// Source-to-cloud financial integrity comparisons by entity, period and currency.
// Owner-only; all queries are read-only and GROUP results contain no party names.
const definitions = [
  {
    name:"SalesInvoices",
    sql:"SELECT x.EntityId AS EntityId, " +
      "CASE WHEN x.Year BETWEEN 2000 AND 2100 AND x.Month BETWEEN 1 AND 12 " +
      "THEN printf('%04d-%02d',x.Year,x.Month) ELSE 'UNKNOWN' END AS Period, " +
      "'SOURCE' AS Currency, x.Amount AS Amount FROM SalesInvoices x"
  },
  {
    name:"PaymentVouchers",
    sql:"SELECT x.EntityId AS EntityId, " +
      "CASE WHEN x.VoucherDate GLOB '[12][0-9][0-9][0-9]-[01][0-9]*' " +
      "THEN substr(x.VoucherDate,1,7) ELSE 'UNKNOWN' END AS Period, " +
      "COALESCE(NULLIF(upper(trim(x.Currency)),''),'UNKNOWN') AS Currency, " +
      "x.Amount AS Amount FROM PaymentVouchers x"
  },
  {
    name:"ReceiptVouchers",
    sql:"SELECT x.EntityId AS EntityId, " +
      "CASE WHEN x.ReceiptDate GLOB '[12][0-9][0-9][0-9]-[01][0-9]*' " +
      "THEN substr(x.ReceiptDate,1,7) ELSE 'UNKNOWN' END AS Period, " +
      "COALESCE(NULLIF(upper(trim(x.Currency)),''),'UNKNOWN') AS Currency, " +
      "x.Amount AS Amount FROM ReceiptVouchers x"
  },
  {
    name:"PMPayments",
    sql:"SELECT c.EntityId AS EntityId, " +
      "CASE WHEN x.PaymentDate GLOB '[12][0-9][0-9][0-9]-[01][0-9]*' " +
      "THEN substr(x.PaymentDate,1,7) ELSE 'UNKNOWN' END AS Period, " +
      "'UNSPECIFIED' AS Currency, x.Amount AS Amount " +
      "FROM PMPayments x LEFT JOIN PMCustomers c ON c.Id=x.CustomerId"
  },
  {
    name:"PMPaymentPlan",
    sql:"SELECT c.EntityId AS EntityId, " +
      "CASE WHEN x.DueDate GLOB '[12][0-9][0-9][0-9]-[01][0-9]*' " +
      "THEN substr(x.DueDate,1,7) ELSE 'UNKNOWN' END AS Period, " +
      "COALESCE(NULLIF(upper(trim(x.Currency)),''),'UNKNOWN') AS Currency, " +
      "x.Amount AS Amount FROM PMPaymentPlan x " +
      "LEFT JOIN PMProjects p ON p.Id=x.ProjectId " +
      "LEFT JOIN PMCustomers c ON c.Id=p.CustomerId"
  },
  {
    name:"PMPaymentPlanAllocations",
    sql:"SELECT c.EntityId AS EntityId, " +
      "CASE WHEN x.ReceivedDate GLOB '[12][0-9][0-9][0-9]-[01][0-9]*' " +
      "THEN substr(x.ReceivedDate,1,7) ELSE 'UNKNOWN' END AS Period, " +
      "COALESCE(NULLIF(upper(trim(pl.Currency)),''),'UNKNOWN') AS Currency, " +
      "x.Amount AS Amount FROM PMPaymentPlanAllocations x " +
      "LEFT JOIN PMPaymentPlan pl ON pl.Id=x.PaymentPlanId " +
      "LEFT JOIN PMProjects p ON p.Id=pl.ProjectId " +
      "LEFT JOIN PMCustomers c ON c.Id=p.CustomerId"
  }
];

export async function financialBreakdown(request, env) {
  if(env.MIGRATION_ENV!=='staging')return Response.json({error:"Staging only."},{status:503});
  if(request.method!=='GET')return Response.json({error:"Read only."},{status:405});
  const groups=[];
  for(const definition of definitions) {
    const sql="SELECT EntityId,Period,Currency,COUNT(*) AS Count," +
      "COALESCE(SUM(Amount),0) AS Total, " +
      "COALESCE(SUM(CASE WHEN Amount IS NULL THEN 1 ELSE 0 END),0) AS NullAmounts " +
      "FROM ("+definition.sql+") GROUP BY EntityId,Period,Currency " +
      "ORDER BY EntityId,Period,Currency";
    const result=await env.DB.prepare(sql).all();
    for(const row of result.results||[]){
      if(!Number.isFinite(Number(row.Total))||!Number.isSafeInteger(Number(row.Count)))
        return Response.json({error:"Invalid financial aggregation."},{status:503});
      groups.push({
        name:definition.name,
        entityId:row.EntityId===null?null:Number(row.EntityId),
        period:row.Period===null?"UNKNOWN":String(row.Period),
        currency:String(row.Currency||"UNKNOWN"),
        count:Number(row.Count),
        total:Number(row.Total),
        nullAmounts:Number(row.NullAmounts||0)
      });
      if(groups.length>6000)return Response.json({error:"Unexpected breakdown size."},{status:503});
    }
  }
  return new Response(JSON.stringify({schemaVersion:21,groupCount:groups.length,groups}),{
    headers:{
      "Content-Type":"application/json; charset=utf-8",
      "Cache-Control":"private, no-store",
      "X-Content-Type-Options":"nosniff",
      "Referrer-Policy":"no-referrer"
    }
  });
}
