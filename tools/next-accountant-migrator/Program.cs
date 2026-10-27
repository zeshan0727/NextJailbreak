using Microsoft.Data.Sqlite;
using NextAccountant.Migrator;

const string DefaultRoot =
    @"D:\Zeeshan - All Entites Data OCT 2024 - till date\Accountants\AccountantsNext";
const string DefaultApi = "https://accounts-stage-api.nextjailbreak.com";

var options = CliArgs.Parse(args);
if (options.Has("prepare-staging-key"))
{
    KeyEnrollment.PreparePublicKey();
    return 0;
}
if (options.Has("open-staging-web"))
{
    // This operation does not load, read or modify the Windows business backup.
    // Only the Windows DPAPI-protected existing staging credential is used.
    try
    {
        var token = Environment.GetEnvironmentVariable("NEXT_ACCOUNTANT_STAGING_OWNER_TOKEN") ??
            KeyEnrollment.TryReadToken();
        if (string.IsNullOrWhiteSpace(token))
            return Fail("The private encrypted staging credential is missing from this Windows user profile.");
        using var client = new CloudClient(DefaultApi, token);
        var link = await client.BeginReadOnlyWebSessionAsync();
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = link.AbsoluteUri,
            UseShellExecute = true
        });
        Console.WriteLine("Private read-only Next Accountant staging opened in your browser.");
        Console.WriteLine("The migration token was NOT sent to your browser.");
        Console.WriteLine("The web session expires automatically after eight hours.");
        return 0;
    }
    catch (Exception ex) { return Fail("Could not open secure staging: " + ex.Message); }
}
var installRoot = options.Get("root") ?? DefaultRoot;
var apiBase = options.Get("api") ?? DefaultApi;
var prepareOnly = options.Has("prepare-only") || options.Has("dry-run");
var databaseOnly = options.Has("database-only-test");
var commitStaging = options.Has("commit-staging-import");
var resumeFilesOnly = options.Has("resume-staging-files-only");
var financialOnly = options.Has("financial-reconcile-only");
if ((commitStaging ? 1 : 0) + (resumeFilesOnly ? 1 : 0) + (financialOnly ? 1 : 0) > 1)
    return Fail("Select only one staging mode: full import, file recovery or financial verification.");
var backup = options.Get("backup") ?? BackupVerifier.FindNewest(installRoot);

if (string.IsNullOrWhiteSpace(backup) || !File.Exists(backup))
    return Fail("No ACCOUNTANTS V6 business backup was found. Create a fresh verified business backup first.");

Console.WriteLine("NEXT ACCOUNTANT WEB MIGRATOR 0.4.0 - STAGING ONLY");
Console.WriteLine("Source: " + backup);
Console.WriteLine("Mode: " +
    (prepareOnly ? "PREPARE / VERIFY ONLY" :
     financialOnly ? "STAGING FINANCIAL RECONCILIATION (read only)" :
     resumeFilesOnly ? "SAFE STAGING FILE-ONLY RECOVERY (no database writes)" :
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


    if (financialOnly)
    {
        const string verifiedSnapshot = "Accountants6_BUSINESS_DESKTOP-BL913CT_20261026_092040.zip";
        if (!string.Equals(Path.GetFileName(backup),verifiedSnapshot,StringComparison.OrdinalIgnoreCase))
            return Fail("Financial reconciliation requires the original imported V6 snapshot. No changes performed.");
        if (counts.Count != 109 || counts.Values.Sum() != 11913 || files.Count != 909 || schemaVersion != 21)
            return Fail("Source snapshot identity does not match staging import baseline.");
        var verifyToken = Environment.GetEnvironmentVariable("NEXT_ACCOUNTANT_STAGING_OWNER_TOKEN") ??
            KeyEnrollment.TryReadToken();
        if (string.IsNullOrWhiteSpace(verifyToken))
            return Fail("Missing Windows-protected staging credential; no comparison possible.");
        using var verifyCloud = new CloudClient(DefaultApi,verifyToken);
        var verifyHealth = await verifyCloud.HealthAsync();
        if (verifyHealth is null || !verifyHealth.Ok || verifyHealth.Environment != "staging")
            return Fail("Staging API failed identity/health check. No changes performed.");
        await FinancialReconciler.VerifyAsync(source,verifyCloud,counts,files.Count,schemaVersion);
        return 0;
    }

    if (prepareOnly || (!commitStaging && !resumeFilesOnly))
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

    var token = Environment.GetEnvironmentVariable("NEXT_ACCOUNTANT_STAGING_OWNER_TOKEN") ??
        KeyEnrollment.TryReadToken();
    if (string.IsNullOrWhiteSpace(token))
        return Fail("Secure staging credential is missing. Use PREPARE_STAGING_KEY.bat and place the encrypted credential file beside the migrator. No migration was started.");

    using var cloud = new CloudClient(apiBase, token);
    var health = await cloud.HealthAsync();
    if (health is null || !health.Ok || !health.Database || !string.Equals(health.Environment,"staging",StringComparison.OrdinalIgnoreCase))
        return Fail("Staging identity/database health check failed. No migration was started.");
    if (!health.Files)
        return Fail("Private R2 file storage is not ready. Full migration was not started.");

    var remoteBefore = await cloud.CountsAsync();
    if (resumeFilesOnly)
    {
        // File-only recovery is permitted ONLY for the exact verified V6 backup
        // that produced the interrupted 2026-10-27 staging migration.
        const string expectedBackup = "Accountants6_BUSINESS_DESKTOP-BL913CT_20261026_092040.zip";
        if (!string.Equals(Path.GetFileName(backup), expectedBackup, StringComparison.OrdinalIgnoreCase))
            return Fail("File-only recovery requires the original verified 2026-10-26 09:20:40 V6 backup, not another/newer backup.");
        if (counts.Count != 109 || counts.Values.Sum() != 11913 || files.Count != 909 || schemaVersion != 21)
            return Fail("This backup's identity/record and file counts differ from the verified interrupted migration. No writes performed.");
        var mismatched = counts.Where(x =>
                !remoteBefore.TryGetValue(x.Key, out var n) || n != x.Value)
            .Select(x => x.Key)
            .ToList();
        var extra = remoteBefore.Where(x =>
                !x.Key.StartsWith("Web", StringComparison.OrdinalIgnoreCase) &&
                !counts.ContainsKey(x.Key) && x.Value > 0)
            .Select(x => x.Key).ToList();
        if (mismatched.Count > 0 || extra.Count > 0)
            return Fail("STAGING FILE RECOVERY BLOCKED: source data row counts do not exactly match staging. No writes performed. Mismatched tables: " +
                string.Join(", ", mismatched.Take(12)) + " Extra populated tables: " + string.Join(", ", extra.Take(12)));
        if (!remoteBefore.TryGetValue("WebFileIndex", out var existingIndexedFiles) ||
            existingIndexedFiles <= 0 || existingIndexedFiles >= files.Count)
            return Fail("File-only recovery expected a partial but nonempty staging file index. No writes performed.");
        Console.WriteLine($"PASS: verified {counts.Count:N0} staging source tables and {counts.Values.Sum():N0} rows match source.");
        Console.WriteLine($"PASS: found {existingIndexedFiles:N0} indexed R2 files. No schema or business rows will be imported again.");
        Console.WriteLine("Resuming file upload in IDEMPOTENT mode; completed files will be hash-checked and skipped.");
        await cloud.UploadBackupFilesAsync(backup, files);
        var after = await cloud.CountsAsync();
        var finalBad = counts.Where(x => !after.TryGetValue(x.Key, out var n) || n != x.Value).ToList();
        if (finalBad.Count > 0)
            return Fail("Post-resume staging row reconciliation failed. No additional SQL rows were written.");
        if (!after.TryGetValue("WebFileIndex", out var indexedAfter) || indexedAfter != files.Count)
            return Fail($"File index reconciliation failed: expected {files.Count:N0}, indexed {indexedAfter:N0}. Review staging before retry.");
        Console.WriteLine();
        Console.WriteLine($"STAGING FILE RECOVERY PASS: {counts.Values.Sum():N0} database rows untouched, {indexedAfter:N0} files hash-verified and indexed.");
        Console.WriteLine("Financial reconciliation and production approval remain separate.");
        return 0;
    }
    if (remoteBefore.Any(x =>
        !x.Key.StartsWith("Web", StringComparison.OrdinalIgnoreCase) && x.Value > 0))
        return Fail("Cloud business tables are not empty. Refusing full import.");

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
