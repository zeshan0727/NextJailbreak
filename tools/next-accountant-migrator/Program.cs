using Microsoft.Data.Sqlite;
using NextAccountant.Migrator;

const string DefaultRoot =
    @"D:\Zeeshan - All Entites Data OCT 2024 - till date\Accountants\AccountantsNext";
const string DefaultApi = "https://accounts-stage-api.nextjailbreak.com";

var options = CliArgs.Parse(args);
var installRoot = options.Get("root") ?? DefaultRoot;
var apiBase = options.Get("api") ?? DefaultApi;
var prepareOnly = options.Has("prepare-only") || options.Has("dry-run");
var databaseOnly = options.Has("database-only-test");
var commitStaging = options.Has("commit-staging-import");
var backup = options.Get("backup") ?? BackupVerifier.FindNewest(installRoot);

if (string.IsNullOrWhiteSpace(backup) || !File.Exists(backup))
    return Fail("No ACCOUNTANTS V6 business backup was found. Create a fresh verified business backup first.");

Console.WriteLine("NEXT ACCOUNTANT WEB MIGRATOR 0.2.0 - STAGING ONLY");
Console.WriteLine("Source: " + backup);
Console.WriteLine("Mode: " +
    (prepareOnly ? "PREPARE / VERIFY ONLY" :
     commitStaging ? "STAGING IMPORT" : "SAFE READ-ONLY (import not authorized)"));
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
    var d1 = await D1Compatibility.InspectAsync(
        source, verified.DatabasePath, schema, files);

    Console.WriteLine();
    Console.WriteLine("CLOUDFLARE D1 / R2 COMPATIBILITY");
    Console.WriteLine($"SQLite DB size: {d1.DatabaseBytes:N0} bytes");
    Console.WriteLine($"Largest estimated row: {d1.LargestRowBytes:N0} bytes");
    Console.WriteLine($"Views: {d1.ViewCount} | Triggers: {d1.TriggerCount} | Virtual tables: {d1.VirtualTableCount}");
    Console.WriteLine($"Foreign key violations: {d1.ForeignKeyViolations}");
    foreach (var warning in d1.Warnings.Distinct().Take(20))
        Console.WriteLine("WARNING: " + warning);
    var blockers = d1.Blockers.Distinct().ToList();
    foreach (var issue in blockers.Take(40))
        Console.WriteLine("BLOCKER: " + issue);
    if (blockers.Count > 40)
        Console.WriteLine($"... plus {blockers.Count - 40:N0} additional blockers.");
    if (blockers.Count > 0)
        return Fail("D1/R2 compatibility preflight found " + blockers.Count +
            " blocker(s). No cloud writes were performed.");
    Console.WriteLine("D1/R2 COMPATIBILITY: PASS (static preflight only)");


    if (prepareOnly || !commitStaging)
    {
        Console.WriteLine("PREPARE PASS: no cloud writes were performed.");
        if (!prepareOnly) Console.WriteLine("Import requires explicit --commit-staging-import flag.");
        return 0;
    }

    if (databaseOnly)
        return Fail("Database-only imports are disabled because they can leave incomplete staging data.");
    if (!Uri.TryCreate(apiBase, UriKind.Absolute, out var checkedUri) ||
        checkedUri.Scheme != Uri.UriSchemeHttps ||
        !string.Equals(checkedUri.Host,"accounts-stage-api.nextjailbreak.com",StringComparison.OrdinalIgnoreCase) ||
        checkedUri.AbsolutePath != "/" || !string.IsNullOrEmpty(checkedUri.Query) || checkedUri.Port != 443)
        return Fail("Refusing non-staging destination. Staging host is accounts-stage-api.nextjailbreak.com only.");

    var token = Environment.GetEnvironmentVariable("NEXT_ACCOUNTANT_STAGING_OWNER_TOKEN");
    if (string.IsNullOrWhiteSpace(token))
        return Fail("Cloud owner authentication is not configured. No migration was started.");

    using var cloud = new CloudClient(apiBase, token);
    var health = await cloud.HealthAsync();
    if (health is null || !health.Ok || !health.Database || !string.Equals(health.Environment,"staging",StringComparison.OrdinalIgnoreCase))
        return Fail("Staging identity/database health check failed. No migration was started.");
    if (!health.Files)
        return Fail("Private R2 file storage is not ready. Full migration was not started.");

    var remoteBefore = await cloud.CountsAsync();
    if (remoteBefore.Any(x =>
        !x.Key.StartsWith("Web", StringComparison.OrdinalIgnoreCase) && x.Value > 0))
        return Fail("Cloud business tables are not empty. Refusing to overwrite web data.");

    Console.WriteLine("Applying source schema to isolated staging in bounded groups...");
    var ddl = await SqliteExport.SchemaStatementsAsync(source);
    const int maxDdlPerRequest = 8;
    for (var i = 0; i < ddl.Count; i += maxDdlPerRequest)
    {
        var group = ddl.Skip(i).Take(maxDdlPerRequest);
        var sqlGroup = "PRAGMA foreign_keys = ON;\n" +
            string.Join(";\n", group) + ";\n";
        if (System.Text.Encoding.UTF8.GetByteCount(sqlGroup) >= 50_000)
            return Fail("A source-schema batch is too large for safe D1 transfer.");
        await cloud.ApplySchemaAsync(sqlGroup,schemaVersion);
        Console.WriteLine($"Applied schema statements {i+1:N0}-{Math.Min(i+maxDdlPerRequest,ddl.Count):N0}/{ddl.Count:N0}");
    }

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
    Console.WriteLine($"STAGING IMPORT CHECK: {imported:N0} rows imported and count-reconciled.");
    Console.WriteLine($"STAGING IMPORT CHECK: {files.Count:N0} business files uploaded and SHA-256 verified.");
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
