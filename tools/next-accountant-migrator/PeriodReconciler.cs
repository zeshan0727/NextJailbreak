using System.Globalization;
using Microsoft.Data.Sqlite;

namespace NextAccountant.Migrator;

internal sealed class FinancialBreakdownResponse
{
    public int SchemaVersion { get; set; }
    public int GroupCount { get; set; }
    public List<FinancialBreakdownGroup> Groups { get; set; } = [];
}
internal sealed class FinancialBreakdownGroup
{
    public string Name { get; set; } = "";
    public long? EntityId { get; set; }
    public string Period { get; set; } = "";
    public string Currency { get; set; } = "";
    public long Count { get; set; }
    public double Total { get; set; }
    public long NullAmounts { get; set; }
}

internal static class PeriodReconciler
{
    // These source projections are intentionally independent of their D1
    // counterparts in financial-breakdown.js. They run on the Windows backup.
    // Dates are grouped as raw source YYYY-MM, without invented FX conversion.
    private static readonly Dictionary<string,string> Source = new()
    {
        ["SalesInvoices"] =
          "SELECT x.EntityId AS EntityId, CASE WHEN x.Year BETWEEN 2000 AND 2100 AND x.Month BETWEEN 1 AND 12 " +
          "THEN printf('%04d-%02d',x.Year,x.Month) ELSE 'UNKNOWN' END AS Period, 'SOURCE' AS Currency, " +
          "x.Amount AS Amount FROM SalesInvoices x",
        ["PaymentVouchers"] =
          "SELECT x.EntityId AS EntityId, CASE WHEN x.VoucherDate GLOB '[12][0-9][0-9][0-9]-[01][0-9]*' " +
          "THEN substr(x.VoucherDate,1,7) ELSE 'UNKNOWN' END AS Period, " +
          "COALESCE(NULLIF(upper(trim(x.Currency)),''),'UNKNOWN') AS Currency, " +
          "x.Amount AS Amount FROM PaymentVouchers x",
        ["ReceiptVouchers"] =
          "SELECT x.EntityId AS EntityId, CASE WHEN x.ReceiptDate GLOB '[12][0-9][0-9][0-9]-[01][0-9]*' " +
          "THEN substr(x.ReceiptDate,1,7) ELSE 'UNKNOWN' END AS Period, " +
          "COALESCE(NULLIF(upper(trim(x.Currency)),''),'UNKNOWN') AS Currency, " +
          "x.Amount AS Amount FROM ReceiptVouchers x",
        ["PMPayments"] =
          "SELECT c.EntityId AS EntityId, CASE WHEN x.PaymentDate GLOB '[12][0-9][0-9][0-9]-[01][0-9]*' " +
          "THEN substr(x.PaymentDate,1,7) ELSE 'UNKNOWN' END AS Period, " +
          "'UNSPECIFIED' AS Currency,x.Amount AS Amount FROM PMPayments x " +
          "LEFT JOIN PMCustomers c ON c.Id=x.CustomerId",
        ["PMPaymentPlan"] =
          "SELECT c.EntityId AS EntityId, CASE WHEN x.DueDate GLOB '[12][0-9][0-9][0-9]-[01][0-9]*' " +
          "THEN substr(x.DueDate,1,7) ELSE 'UNKNOWN' END AS Period, " +
          "COALESCE(NULLIF(upper(trim(x.Currency)),''),'UNKNOWN') AS Currency,x.Amount AS Amount " +
          "FROM PMPaymentPlan x LEFT JOIN PMProjects p ON p.Id=x.ProjectId " +
          "LEFT JOIN PMCustomers c ON c.Id=p.CustomerId",
        ["PMPaymentPlanAllocations"] =
          "SELECT c.EntityId AS EntityId, CASE WHEN x.ReceivedDate GLOB '[12][0-9][0-9][0-9]-[01][0-9]*' " +
          "THEN substr(x.ReceivedDate,1,7) ELSE 'UNKNOWN' END AS Period, " +
          "COALESCE(NULLIF(upper(trim(pl.Currency)),''),'UNKNOWN') AS Currency,x.Amount AS Amount " +
          "FROM PMPaymentPlanAllocations x " +
          "LEFT JOIN PMPaymentPlan pl ON pl.Id=x.PaymentPlanId " +
          "LEFT JOIN PMProjects p ON p.Id=pl.ProjectId " +
          "LEFT JOIN PMCustomers c ON c.Id=p.CustomerId"
    };

    private static string Key(FinancialBreakdownGroup group) =>
        string.Join("|",group.Name,
            group.EntityId?.ToString(CultureInfo.InvariantCulture) ?? "NULL",
            group.Period.Length.ToString(CultureInfo.InvariantCulture) + ":" + group.Period,
            group.Currency.Length.ToString(CultureInfo.InvariantCulture) + ":" + group.Currency);

    public static async Task VerifyAsync(SqliteConnection source, CloudClient cloud, int schemaVersion)
    {
        var remote=await cloud.FinancialBreakdownAsync()
          ?? throw new InvalidDataException("Cloud monthly financial breakdown missing.");
        if(remote.SchemaVersion!=schemaVersion || remote.GroupCount!=remote.Groups.Count)
            throw new InvalidDataException("Source schema/version or cloud breakdown group count mismatch.");
        if(remote.Groups.Any(x=>!Source.ContainsKey(x.Name) ||
              !double.IsFinite(x.Total) || x.Count<0 || x.NullAmounts<0))
            throw new InvalidDataException("Cloud returned invalid financial breakdown values.");

        var map=new Dictionary<string,FinancialBreakdownGroup>(StringComparer.Ordinal);
        foreach(var item in remote.Groups)
            if(!map.TryAdd(Key(item),item))
                throw new InvalidDataException("Cloud financial breakdown contains a duplicate group.");

        var mismatches=new HashSet<string>(StringComparer.Ordinal);
        var matched=0;
        foreach(var (name,projection) in Source)
        {
            var sql="SELECT EntityId,Period,Currency,COUNT(*) AS Count," +
                "COALESCE(SUM(Amount),0) AS Total," +
                "COALESCE(SUM(CASE WHEN Amount IS NULL THEN 1 ELSE 0 END),0) AS NullAmounts " +
                "FROM ("+projection+") GROUP BY EntityId,Period,Currency " +
                "ORDER BY EntityId,Period,Currency";
            await using var cmd=source.CreateCommand();
            cmd.CommandText=sql;
            await using var rows=await cmd.ExecuteReaderAsync();
            while(await rows.ReadAsync())
            {
                var group=new FinancialBreakdownGroup
                {
                    Name=name,
                    EntityId=rows.IsDBNull(0)?null:Convert.ToInt64(rows.GetValue(0),CultureInfo.InvariantCulture),
                    Period=rows.IsDBNull(1)?"UNKNOWN":rows.GetString(1),
                    Currency=rows.IsDBNull(2)?"UNKNOWN":rows.GetString(2),
                    Count=rows.GetInt64(3),
                    Total=Convert.ToDouble(rows.GetValue(4),CultureInfo.InvariantCulture),
                    NullAmounts=rows.GetInt64(5)
                };
                if(!map.Remove(Key(group),out var candidate) ||
                   !double.IsFinite(group.Total) ||
                   candidate!.Count!=group.Count ||
                   candidate.NullAmounts!=group.NullAmounts ||
                   Math.Abs(candidate.Total-group.Total)>=0.005)
                {
                    mismatches.Add(name);
                }
                else matched++;
            }
        }
        foreach(var unmatched in map.Values) mismatches.Add(unmatched.Name);
        if(mismatches.Count>0)
            throw new InvalidDataException(
                "Per-company/month/currency source reconciliation failed for: " +
                string.Join(", ",mismatches.OrderBy(x=>x)) +
                ". Imported V6 records were NOT changed.");
        Console.WriteLine("  Company/month/currency breakdown: MATCH");
        Console.WriteLine("  Groups checked: " + matched.ToString("N0",CultureInfo.InvariantCulture));
        Console.WriteLine("  Null-amount counts: MATCH");
        Console.WriteLine("  No source values were sent to GitHub or shown in this console.");
    }
}
