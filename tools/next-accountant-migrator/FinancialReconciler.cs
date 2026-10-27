using System.Globalization;
using Microsoft.Data.Sqlite;

namespace NextAccountant.Migrator;

// Independent monetary reconciliation against the exact original verified V6
// snapshot. Cloud D1 answers with owner-only totals. No business records,
// financial values, or credentials are uploaded to GitHub or written to logs.
internal sealed class FinancialFingerprint
{
    public int SchemaVersion { get; set; }
    public int FileIndexCount { get; set; }
    public List<FinanceAggregate> Aggregates { get; set; } = [];
}

internal sealed class FinanceAggregate
{
    public string Name { get; set; } = "";
    public long Count { get; set; }
    public double Total { get; set; }
}

internal static class FinancialReconciler
{
    private static readonly Dictionary<string,string> AggregateSql = new()
    {
        ["SalesInvoices"] = "SELECT COUNT(*), COALESCE(SUM(Amount),0) FROM SalesInvoices",
        ["PaymentVouchers"] = "SELECT COUNT(*), COALESCE(SUM(Amount),0) FROM PaymentVouchers",
        ["ReceiptVouchers"] = "SELECT COUNT(*), COALESCE(SUM(Amount),0) FROM ReceiptVouchers",
        ["PMPayments"] = "SELECT COUNT(*), COALESCE(SUM(Amount),0) FROM PMPayments",
        ["PMPaymentPlan"] = "SELECT COUNT(*), COALESCE(SUM(Amount),0) FROM PMPaymentPlan",
        ["PMPaymentPlanAllocations"] = "SELECT COUNT(*), COALESCE(SUM(Amount),0) FROM PMPaymentPlanAllocations"
    };

    public static async Task VerifyAsync(
        SqliteConnection source, CloudClient cloud,
        IReadOnlyDictionary<string,long> expectedCounts,
        int expectedFiles, int sourceSchemaVersion)
    {
        var remoteCounts = await cloud.CountsAsync();
        var failures = new List<string>();
        foreach (var entry in expectedCounts)
            if (!remoteCounts.TryGetValue(entry.Key, out var n) || n != entry.Value)
                failures.Add(entry.Key + " source record count differs");

        var extras = remoteCounts
            .Where(x => !x.Key.StartsWith("Web",StringComparison.OrdinalIgnoreCase)
                        && !expectedCounts.ContainsKey(x.Key) && x.Value > 0)
            .Select(x => x.Key).ToList();
        if (extras.Count > 0)
            failures.Add("Staging includes additional populated source tables.");

        var remote = await cloud.FinancialFingerprintAsync()
            ?? throw new InvalidDataException("Staging financial fingerprint missing.");
        if (remote.SchemaVersion != sourceSchemaVersion)
            failures.Add("Staging/source schema versions differ.");
        if (remote.FileIndexCount != expectedFiles)
            failures.Add("Cloud supporting-file index count differs.");
        if (remote.Aggregates.Count != AggregateSql.Count)
            failures.Add("Unexpected number of financial aggregates.");

        foreach (var (name,sql) in AggregateSql)
        {
            await using var cmd = source.CreateCommand();
            cmd.CommandText = sql;
            await using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync())
            {
                failures.Add(name + " local aggregation unavailable.");
                continue;
            }
            var count = Convert.ToInt64(reader.GetValue(0),CultureInfo.InvariantCulture);
            var total = Convert.ToDouble(reader.GetValue(1),CultureInfo.InvariantCulture);
            var target = remote.Aggregates.SingleOrDefault(x =>
                string.Equals(x.Name,name,StringComparison.Ordinal));
            var passed = target is not null &&
                target.Count == count && double.IsFinite(target.Total) &&
                Math.Abs(total - target.Total) < 0.005;
            Console.WriteLine("  " + name + ": " + (passed ? "MATCH" : "MISMATCH"));
            if (!passed) failures.Add(name + " row count or monetary amount differs.");
        }

        if (failures.Count > 0)
            throw new InvalidDataException("Financial staging reconciliation failed:\n  " +
                string.Join("\n  ",failures));

        Console.WriteLine();
        Console.WriteLine("CHECKING COMPANY / MONTH / SOURCE CURRENCY...");
        await PeriodReconciler.VerifyAsync(source, cloud, sourceSchemaVersion);
        await SnapshotReconciler.VerifyAsync(source, cloud);
        Console.WriteLine();
        Console.WriteLine("FINANCIAL RECONCILIATION PASSED");
        Console.WriteLine("  Exact source database row counts: PASS");
        Console.WriteLine("  V6 staging supporting-file index: PASS");
        Console.WriteLine("  Six financial source monetary totals: PASS");
        Console.WriteLine("  Grouped monetary and record-count reconciliation: PASS");
        Console.WriteLine("  Manager report source snapshot account totals: PASS");
        Console.WriteLine("  No business records or Windows data were modified.");
        Console.WriteLine("  Windows report-format and trial-balance parity still require independent approval.");
    }
}
