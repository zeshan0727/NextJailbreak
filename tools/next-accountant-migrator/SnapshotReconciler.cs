using System.Globalization;
using Microsoft.Data.Sqlite;

namespace NextAccountant.Migrator;

internal sealed class TrialBalanceSnapshotResponse
{
    public int Count { get; set; }
    public List<TrialBalanceSnapshotGroup> Groups { get; set; } = [];
}
internal sealed class TrialBalanceSnapshotGroup
{
    public string? SnapshotId { get; set; }
    public long Count { get; set; }
    public double DebitYtd { get; set; }
    public double CreditYtd { get; set; }
    public double CurrentBalance { get; set; }
    public long NullEntries { get; set; }
}
internal static class SnapshotReconciler
{
    public static async Task VerifyAsync(SqliteConnection source,CloudClient cloud)
    {
        var cloudSnapshots=await cloud.TrialBalanceSnapshotAsync()
            ?? throw new InvalidDataException("Cloud manager-report account snapshots are unavailable.");
        if(cloudSnapshots.Count!=cloudSnapshots.Groups.Count)
            throw new InvalidDataException("Cloud manager-report snapshot count inconsistent.");

        var index=new Dictionary<string,TrialBalanceSnapshotGroup>(StringComparer.Ordinal);
        foreach(var item in cloudSnapshots.Groups)
            if(!index.TryAdd(item.SnapshotId ?? "\u0001NULL",item))
                throw new InvalidDataException("Duplicate cloud manager-report snapshot key.");

        await using var cmd=source.CreateCommand();
        cmd.CommandText="SELECT SnapshotId,COUNT(*)," +
            "COALESCE(SUM(DebitYtd),0),COALESCE(SUM(CreditYtd),0)," +
            "COALESCE(SUM(CurrentBalance),0)," +
            "COALESCE(SUM(CASE WHEN DebitYtd IS NULL OR CreditYtd IS NULL " +
              "OR CurrentBalance IS NULL THEN 1 ELSE 0 END),0) " +
            "FROM ManagerReportAccountsV6A GROUP BY SnapshotId ORDER BY SnapshotId";
        await using var reader=await cmd.ExecuteReaderAsync();
        var failures=0;
        var checkedSnapshots=0;
        while(await reader.ReadAsync())
        {
            var id=reader.IsDBNull(0)?"\u0001NULL":reader.GetString(0);
            if(!index.Remove(id,out var target))
            {
                failures++;
                continue;
            }
            var count=reader.GetInt64(1);
            var debit=Convert.ToDouble(reader.GetValue(2),CultureInfo.InvariantCulture);
            var credit=Convert.ToDouble(reader.GetValue(3),CultureInfo.InvariantCulture);
            var balance=Convert.ToDouble(reader.GetValue(4),CultureInfo.InvariantCulture);
            var nullEntries=reader.GetInt64(5);
            if(target.Count!=count || target.NullEntries!=nullEntries ||
               !double.IsFinite(target.DebitYtd)||!double.IsFinite(target.CreditYtd)||
               !double.IsFinite(target.CurrentBalance)||
               Math.Abs(target.DebitYtd-debit)>=0.005 ||
               Math.Abs(target.CreditYtd-credit)>=0.005 ||
               Math.Abs(target.CurrentBalance-balance)>=0.005)
                failures++;
            checkedSnapshots++;
        }
        if(failures>0||index.Count>0)
            throw new InvalidDataException(
                "Windows manager-report account snapshot parity failed: "+
                failures+" differing and "+index.Count+" cloud-only groups. "+
                "No production or staging financial entries were altered.");
        Console.WriteLine("  Manager-report account snapshots: MATCH ("+
            checkedSnapshots.ToString("N0",CultureInfo.InvariantCulture)+
            " source snapshots)");
        Console.WriteLine("  Snapshot debit/credit/balance source aggregates: MATCH");
        Console.WriteLine("  Report calculation and rendering parity still NOT certified.");
    }
}
