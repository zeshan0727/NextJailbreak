using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace NextAccountant.Migrator;

internal static class SqliteExport
{
    public static async Task<List<string>> TablesAsync(SqliteConnection cn)
    {
        var result = new List<string>();
        await using var cmd = cn.CreateCommand();
        cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name";
        await using var rd = await cmd.ExecuteReaderAsync();
        while (await rd.ReadAsync()) result.Add(rd.GetString(0));
        return result;
    }

    public static async Task<Dictionary<string,long>> CountsAsync(SqliteConnection cn)
    {
        var result = new Dictionary<string,long>(StringComparer.OrdinalIgnoreCase);
        foreach (var table in await TablesAsync(cn))
        {
            await using var cmd = cn.CreateCommand();
            cmd.CommandText = $"SELECT COUNT(*) FROM [{Escape(table)}]";
            result[table] = Convert.ToInt64(await cmd.ExecuteScalarAsync() ?? 0L);
        }
        return result;
    }

    public static async Task<int> SchemaVersionAsync(SqliteConnection cn)
    {
        try
        {
            await using var cmd = cn.CreateCommand();
            cmd.CommandText = "SELECT COALESCE(MAX(Version),0) FROM SchemaVersion";
            return Convert.ToInt32(await cmd.ExecuteScalarAsync() ?? 0);
        }
        catch { return 0; }
    }

    public static async Task<string> SchemaSqlAsync(SqliteConnection cn)
    {
        var statements = new List<string> { "PRAGMA foreign_keys = ON" };
        await using var cmd = cn.CreateCommand();
        cmd.CommandText = @"SELECT type,name,sql FROM sqlite_master
WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND type IN ('table','index')
ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name";
        await using var rd = await cmd.ExecuteReaderAsync();
        while (await rd.ReadAsync())
        {
            var sql = rd.GetString(2).Trim().TrimEnd(';');
            if (sql.Length > 0) statements.Add(sql);
        }
        return string.Join(";

", statements) + ";
";
    }

    public static async Task<List<string>> DependencyOrderAsync(SqliteConnection cn)
    {
        var tables = await TablesAsync(cn);
        var deps = tables.ToDictionary(
            t => t, _ => new HashSet<string>(StringComparer.OrdinalIgnoreCase),
            StringComparer.OrdinalIgnoreCase);

        foreach (var table in tables)
        {
            await using var cmd = cn.CreateCommand();
            cmd.CommandText = $"PRAGMA foreign_key_list([{Escape(table)}])";
            await using var rd = await cmd.ExecuteReaderAsync();
            while (await rd.ReadAsync())
            {
                var parent = rd.GetString(rd.GetOrdinal("table"));
                if (deps.ContainsKey(parent) &&
                    !parent.Equals(table, StringComparison.OrdinalIgnoreCase))
                    deps[table].Add(parent);
            }
        }

        var output = new List<string>();
        var remaining = new HashSet<string>(tables, StringComparer.OrdinalIgnoreCase);
        while (remaining.Count > 0)
        {
            var ready = remaining
                .Where(t => deps[t].All(d => !remaining.Contains(d)))
                .OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
            if (ready.Count == 0)
            {
                output.AddRange(remaining.OrderBy(x => x, StringComparer.OrdinalIgnoreCase));
                break;
            }

            output.AddRange(ready);
            foreach (var item in ready) remaining.Remove(item);
        }
        return output;
    }

    public static async IAsyncEnumerable<List<Dictionary<string,object?>>> BatchesAsync(
        SqliteConnection cn, string table, int maxRows = 50, int maxJsonBytes = 450_000)
    {
        await using var cmd = cn.CreateCommand();
        cmd.CommandText = $"SELECT * FROM [{Escape(table)}]";
        await using var rd = await cmd.ExecuteReaderAsync();

        var batch = new List<Dictionary<string,object?>>();
        var estimated = 0;
        while (await rd.ReadAsync())
        {
            var row = new Dictionary<string,object?>(StringComparer.OrdinalIgnoreCase);
            for (var i = 0; i < rd.FieldCount; i++)
            {
                object? value = rd.IsDBNull(i) ? null : rd.GetValue(i);
                if (value is byte[] bytes) value = Convert.ToBase64String(bytes);
                row[rd.GetName(i)] = value;
            }

            var rowBytes = JsonSerializer.SerializeToUtf8Bytes(row).Length;
            if (batch.Count > 0 &&
                (batch.Count >= maxRows || estimated + rowBytes > maxJsonBytes))
            {
                yield return batch;
                batch = [];
                estimated = 0;
            }

            batch.Add(row);
            estimated += rowBytes;
        }

        if (batch.Count > 0) yield return batch;
    }

    private static string Escape(string value) => value.Replace("]", "]]");
}
