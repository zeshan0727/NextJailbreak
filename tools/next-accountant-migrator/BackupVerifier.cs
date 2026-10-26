using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace NextAccountant.Migrator;

internal static class BackupVerifier
{
    public static string? FindNewest(string installRoot)
    {
        var dirs = new[]
        {
            Path.Combine(installRoot, "RecoveryMedia"),
            Path.Combine(installRoot, "Data", "Backups", "BusinessPackages"),
            Path.Combine(installRoot, "Data", "Backups", "CloudPackages"),
            Path.Combine(installRoot, "Data", "Backups")
        };

        return dirs.Where(Directory.Exists)
            .SelectMany(d => Directory.EnumerateFiles(
                d, "Accountants6_BUSINESS_*.zip", SearchOption.AllDirectories))
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .FirstOrDefault();
    }

    public static async Task<VerifiedBackup> VerifyAndExtractAsync(string zipPath, string tempRoot)
    {
        using var archive = ZipFile.OpenRead(zipPath);
        var manifestEntry = archive.GetEntry("V6_BACKUP_MANIFEST.json")
            ?? throw new InvalidDataException("V6_BACKUP_MANIFEST.json is missing.");

        BackupManifest? manifest;
        await using (var stream = manifestEntry.Open())
            manifest = await JsonSerializer.DeserializeAsync<BackupManifest>(
                stream, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        if (manifest is null || manifest.BackupFormat != 1 ||
            !manifest.Product.StartsWith("Accountants 6", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Unsupported V6 business backup manifest.");

        foreach (var expected in manifest.Files)
        {
            var entry = archive.GetEntry(expected.Path)
                ?? throw new InvalidDataException("Missing backup entry: " + expected.Path);
            if (entry.Length != expected.Size)
                throw new InvalidDataException("Size mismatch: " + expected.Path);

            await using var input = entry.Open();
            var hash = Convert.ToHexString(await SHA256.HashDataAsync(input));
            if (!hash.Equals(expected.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("SHA-256 mismatch: " + expected.Path);
        }

        var dbEntry = archive.GetEntry(manifest.DatabaseEntry)
            ?? throw new InvalidDataException("Database snapshot is missing.");

        var dbPath = Path.Combine(tempRoot, "AccountantsNext.db");
        await using (var input = dbEntry.Open())
        await using (var output = File.Create(dbPath))
            await input.CopyToAsync(output);

        await using var cn = new SqliteConnection(
            $"Data Source={dbPath};Mode=ReadOnly;Cache=Private");
        await cn.OpenAsync();
        await using var cmd = cn.CreateCommand();
        cmd.CommandText = "PRAGMA integrity_check;";
        var integrity = (await cmd.ExecuteScalarAsync())?.ToString() ?? "unknown";
        if (!integrity.Equals("ok", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("SQLite integrity check failed: " + integrity);

        return new VerifiedBackup(manifest, dbPath);
    }
}
