using System.Text;
using Microsoft.Data.Sqlite;

namespace NextAccountant.Migrator;

internal sealed class D1CompatibilityResult
{
    public long DatabaseBytes { get; set; }
    public int TableCount { get; set; }
    public int TriggerCount { get; set; }
    public int ViewCount { get; set; }
    public int VirtualTableCount { get; set; }
    public int ForeignKeyViolations { get; set; }
    public long LargestRowBytes { get; set; }
    public List<string> Blockers { get; } = [];
    public List<string> Warnings { get; } = [];
}

internal static class D1Compatibility
{
    private const int D1MaxColumns = 100;
    private const int D1MaxCellOrRowBytes = 2_000_000;
    private const int WorkerMaxUploadBytes = 50 * 1024 * 1024;
    private const long D1FreeDatabaseBytes = 500_000_000;

    public static async Task<D1CompatibilityResult> InspectAsync(
        SqliteConnection connection,
        string databasePath,
        string schemaSql,
        IReadOnlyList<BackupFile> files)
    {
        var result = new D1CompatibilityResult
        {
            DatabaseBytes = new FileInfo(databasePath).Length
        };
        var tables = await SqliteExport.TablesAsync(connection);
        result.TableCount = tables.Count;

        if (result.DatabaseBytes > D1FreeDatabaseBytes)
            result.Warnings.Add("SQLite DB snapshot exceeds the 500 MB D1 Free maximum; a paid Workers plan or a smaller target DB would be required.");

        if (Encoding.UTF8.GetByteCount(schemaSql) > 250_000)
            result.Blockers.Add("Source schema exceeds the current migration API's 250 KB apply-schema request limit.");

        await using (var meta = connection.CreateCommand())
        {
            meta.CommandText = @"SELECT type, name, sql
FROM sqlite_master
WHERE type IN ('trigger','view')
   OR (type='table' AND sql LIKE 'CREATE VIRTUAL TABLE%')";
            await using var reader = await meta.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                var type = reader.GetString(0);
                if (type == "trigger") result.TriggerCount++;
                else if (type == "view") result.ViewCount++;
                else result.VirtualTableCount++;
            }
        }

        if (result.TriggerCount > 0 || result.ViewCount > 0 || result.VirtualTableCount > 0)
            result.Blockers.Add($"Current importer does not preserve {result.TriggerCount} triggers, {result.ViewCount} views or {result.VirtualTableCount} virtual tables.");

        await using (var fk = connection.CreateCommand())
        {
            fk.CommandText = "PRAGMA foreign_key_check;";
            await using var reader = await fk.ExecuteReaderAsync();
            while (await reader.ReadAsync()) result.ForeignKeyViolations++;
        }
        if (result.ForeignKeyViolations > 0)
            result.Blockers.Add($"Source SQLite has {result.ForeignKeyViolations} foreign-key violations.");

        foreach (var table in tables)
        {
            var escaped = table.Replace("]", "]]");
            await using var info = connection.CreateCommand();
            info.CommandText = "PRAGMA table_info([" + escaped + "])";
            var colCount = 0;
            await using (var reader = await info.ExecuteReaderAsync())
                while (await reader.ReadAsync()) colCount++;
            if (colCount > D1MaxColumns)
                result.Blockers.Add($"Table {table} has {colCount} columns; D1 maximum is {D1MaxColumns}.");

            await using var query = connection.CreateCommand();
            query.CommandText = "SELECT * FROM [" + escaped + "]";
            await using var rows = await query.ExecuteReaderAsync();
            while (await rows.ReadAsync())
            {
                long approxBytes = 0;
                for (var i = 0; i < rows.FieldCount; i++)
                {
                    if (rows.IsDBNull(i)) continue;
                    var value = rows.GetValue(i);
                    var size = value switch
                    {
                        byte[] blob => blob.LongLength,
                        string str => Encoding.UTF8.GetByteCount(str),
                        long or double or int or float or bool => 8L,
                        _ => Encoding.UTF8.GetByteCount(value.ToString() ?? "")
                    };
                    approxBytes += size;
                    if (size >= D1MaxCellOrRowBytes)
                        result.Blockers.Add($"Oversized SQLite cell in table {table}, column {rows.GetName(i)}.");
                    if (value is long integer && (integer > 9_007_199_254_740_991L || integer < -9_007_199_254_740_991L))
                        result.Blockers.Add($"Unsafe 64-bit integer precision in table {table}, column {rows.GetName(i)}.");
                }
                result.LargestRowBytes = Math.Max(result.LargestRowBytes, approxBytes);
                if (approxBytes >= D1MaxCellOrRowBytes)
                    result.Blockers.Add($"Oversized SQLite row in table {table}.");
            }
        }

        foreach (var file in files)
        {
            if (file.Size > WorkerMaxUploadBytes)
                result.Blockers.Add($"Attachment exceeds current 50 MB API limit: {file.Path} ({file.Size} bytes).");
        }

        return result;
    }
}
