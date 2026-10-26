using Microsoft.Data.Sqlite;
using NextAccountant.Migrator;

const string DefaultRoot =
    @"D:\Zeeshan - All Entites Data OCT 2024 - till date\Accountants\AccountantsNext";
const string DefaultApi = "https://accounts-api.nextjailbreak.com";

var options = CliArgs.Parse(args);
var installRoot = options.Get("root") ?? DefaultRoot;
var apiBase = options.Get("api") ?? DefaultApi;
var prepareOnly = options.Has("prepare-only") || options.Has("dry-run");
var databaseOnly = options.Has("database-only-test");
var backup = options.Get("backup") ?? BackupVerifier.FindNewest(installRoot);

if (string.IsNullOrWhiteSpace(backup) || !File.Exists(backup))
    return Fail("No ACCOUNTANTS V6 business backup was found. Create a fresh verified business backup first.");

Console.WriteLine("NEXT ACCOUNTANT WEB MIGRATOR 0.1.0");
Console.WriteLine("Source: " + backup);
Console.WriteLine("Mode: " +
    (prepareOnly ? "PREPARE / VERIFY ONLY" :
     databaseOnly ? "DATABASE-ONLY TEST" : "FULL MIGRATION"));
Console.WriteLine();

var temp = Path.Combine(
    Path.GetTempPath(), "NextAccountantMigrator", Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(temp);

try
{
    var verified = await BackupVerifier.VerifyAndExtractAsync(backup, temp);
    await using var source = new SqliteConnection(
        $"Data Source={verified.DatabasePath};Mode=ReadOnly;Cache=Private");
    await source.OpenAsync();

    var counts = await SqliteExport.CountsAsync(source);
    var schemaVersion = await SqliteExport.SchemaVersionAsync(source);
    var schema = await SqliteExport.SchemaSqlAsync(source);
    var files = verified.Manifest.Files
        .Where(x => !x.Path.Equals(
            verified.Manifest.DatabaseEntry, StringComparison.OrdinalIgnoreCase))
        .Where(x => x.Path.StartsWith("Data/", StringComparison.OrdinalIgnoreCase))
        .ToList();

    Console.WriteLine($"PASS V6 manifest: {verified.Manifest.Files.Count:N0} files");
    Console.WriteLine("PASS SQLite integrity: ok");
    Console.WriteLine($"Schema version: {schemaVersion}");
    Console.WriteLine($"Business tables: {counts.Count:N0}");
    Console.WriteLine($"Database rows: {counts.Values.Sum():N0}");
    Console.WriteLine($"Business files: {files.Count:N0}");

    if (prepareOnly)
    {
        Console.WriteLine("PREPARE PASS: no cloud writes were performed.");
        return 0;
    }

    var token = options.Get("token") ??
        Environment.GetEnvironmentVariable("NEXT_ACCOUNTANT_OWNER_TOKEN");
    if (string.IsNullOrWhiteSpace(token))
        return Fail("Cloud owner authentication is not configured. No migration was started.");

    using var cloud = new CloudClient(apiBase, token);
    var health = await cloud.HealthAsync();
    if (health is null || !health.Ok || !health.Database)
        return Fail("Cloud database health check failed. No migration was started.");
    if (!databaseOnly && !health.Files)
        return Fail("Private R2 file storage is not ready. Full migration was not started.");

    var remoteBefore = await cloud.CountsAsync();
    if (remoteBefore.Any(x =>
        !x.Key.StartsWith("Web", StringComparison.OrdinalIgnoreCase) && x.Value > 0))
        return Fail("Cloud business tables are not empty. Refusing to overwrite web data.");

    Console.WriteLine("Applying verified source schema...");
    await cloud.ApplySchemaAsync(schema, schemaVersion);

    long imported = 0;
    foreach (var table in await SqliteExport.DependencyOrderAsync(source))
    {
        if (!counts.TryGetValue(table, out var count) || count == 0) continue;
        Console.WriteLine($"Importing {table}: {count:N0} rows");
        await foreach (var batch in SqliteExport.BatchesAsync(source, table))
        {
            await cloud.ImportBatchAsync(table, batch);
            imported += batch.Count;
        }
    }

    if (!databaseOnly)
        await cloud.UploadBackupFilesAsync(backup, files);

    var remote = await cloud.CountsAsync();
    var mismatches = counts
        .Where(x => !remote.TryGetValue(x.Key, out var n) || n != x.Value)
        .Select(x =>
            $"{x.Key}: local {x.Value:N0}, cloud " +
            $"{(remote.TryGetValue(x.Key, out var r) ? r : -1):N0}")
        .ToList();

    if (mismatches.Count > 0)
        return Fail("Count reconciliation failed:\n  " +
            string.Join("\n  ", mismatches));

    Console.WriteLine();
    Console.WriteLine($"MIGRATION PASS: {imported:N0} rows imported and reconciled.");
    Console.WriteLine(databaseOnly
        ? "Files intentionally skipped in database-only test mode."
        : $"MIGRATION PASS: {files.Count:N0} business files uploaded.");
    Console.WriteLine(
        "Windows ACCOUNTANTS remains authoritative until module/report reconciliation passes.");
    return 0;
}
catch (Exception ex)
{
    return Fail(ex.Message);
}
finally
{
    try { Directory.Delete(temp, true); } catch { }
}

static int Fail(string message)
{
    Console.Error.WriteLine();
    Console.Error.WriteLine("STOP: " + message);
    return 1;
}
