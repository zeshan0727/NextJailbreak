namespace NextAccountant.Migrator;

internal sealed class BackupManifest
{
    public string Product { get; set; } = "";
    public int BackupFormat { get; set; }
    public string DatabaseEntry { get; set; } = "Data/AccountantsNext.db";
    public long TotalBytes { get; set; }
    public List<BackupFile> Files { get; set; } = [];
}

internal sealed class BackupFile
{
    public string Path { get; set; } = "";
    public long Size { get; set; }
    public string Sha256 { get; set; } = "";
}

internal sealed record VerifiedBackup(BackupManifest Manifest, string DatabasePath);

internal sealed class Health
{
    public bool Ok { get; set; }
    public bool Database { get; set; }
    public bool Files { get; set; }
    public string Environment { get; set; } = "";
    public string Version { get; set; } = "";
}

internal sealed class RemoteCounts
{
    public int Page { get; set; }
    public bool HasMore { get; set; }
    public List<RemoteTableCount> Tables { get; set; } = [];
}

internal sealed class RemoteTableCount
{
    public string Name { get; set; } = "";
    public long Count { get; set; }
}

internal sealed class CliArgs
{
    private readonly Dictionary<string,string?> _values = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _flags = new(StringComparer.OrdinalIgnoreCase);

    public static CliArgs Parse(string[] args)
    {
        var result = new CliArgs();
        for (var i = 0; i < args.Length; i++)
        {
            if (!args[i].StartsWith("--", StringComparison.Ordinal)) continue;
            var key = args[i][2..];
            if (i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal))
                result._values[key] = args[++i];
            else
                result._flags.Add(key);
        }
        return result;
    }

    public string? Get(string key) => _values.TryGetValue(key, out var value) ? value : null;
    public bool Has(string key) => _flags.Contains(key);
}
