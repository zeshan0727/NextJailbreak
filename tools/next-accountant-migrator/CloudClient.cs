using System.IO.Compression;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace NextAccountant.Migrator;

internal sealed class CloudClient : IDisposable
{
    private readonly HttpClient _http;
    private readonly string _base;

    public CloudClient(string apiBase, string token)
    {
        _base = apiBase.TrimEnd('/');
        _http = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        _http.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("NextAccountantMigrator/0.5.0");
    }

    public async Task<Uri> BeginReadOnlyWebSessionAsync()
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, _base + "/api/web/session/start");
        using var response = await _http.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException("Private web login could not be started (HTTP " +
                (int)response.StatusCode + "). Verify Cloudflare staging deployment.");
        using var parsed = JsonDocument.Parse(body);
        var url = parsed.RootElement.GetProperty("launchUrl").GetString();
        if (!Uri.TryCreate(url, UriKind.Absolute, out var verified) ||
            verified.Scheme != Uri.UriSchemeHttps ||
            verified.Host != "accounts-stage-api.nextjailbreak.com" ||
            verified.Port != 443 ||
            verified.AbsolutePath != "/web/activate" ||
            !verified.Query.StartsWith("?ticket=",StringComparison.Ordinal))
            throw new InvalidDataException("Unexpected private web login URL. Refusing to open it.");
        return verified;
    }

    public Task<Health?> HealthAsync() => GetAsync<Health>("/health");
    public Task<FinancialFingerprint?> FinancialFingerprintAsync() =>
        GetAsync<FinancialFingerprint>("/api/admin/financial-fingerprint");
    public Task<FinancialBreakdownResponse?> FinancialBreakdownAsync() =>
        GetAsync<FinancialBreakdownResponse>("/api/admin/financial-breakdown");
    public Task<TrialBalanceSnapshotResponse?> TrialBalanceSnapshotAsync() =>
        GetAsync<TrialBalanceSnapshotResponse>("/api/admin/tb-snapshot");


    public async Task ApplySchemaAsync(string sql, int sourceSchemaVersion) =>
        await PostAsync("/api/admin/apply-schema", new { sql, sourceSchemaVersion });

    public async Task ImportBatchAsync(string table, object rows) =>
        await PostAsync("/api/admin/import-batch", new { table, rows });

    public async Task<Dictionary<string,long>> CountsAsync()
    {
        var totals = new Dictionary<string,long>(StringComparer.OrdinalIgnoreCase);
        for (int page = 0; page < 1000; page++)
        {
            var result = await GetAsync<RemoteCounts>("/api/admin/counts?page=" + page)
                ?? throw new InvalidOperationException("Cloud count response was empty.");
            if (result.Page != page)
                throw new InvalidDataException("Cloud count page did not match the request.");
            foreach (var entry in result.Tables)
            {
                if (!totals.TryAdd(entry.Name, entry.Count))
                    throw new InvalidDataException("Duplicate count entry for " + entry.Name);
            }
            if (!result.HasMore) return totals;
        }
        throw new InvalidDataException("Remote count pagination limit exceeded.");
    }

    public async Task UploadBackupFilesAsync(
        string backupZip, IReadOnlyList<BackupFile> files)
    {
        using var archive = ZipFile.OpenRead(backupZip);
        long index = 0;
        foreach (var item in files)
        {
            var entry = archive.GetEntry(item.Path)
                ?? throw new InvalidDataException("Backup file missing: " + item.Path);

            var relative = item.Path["Data/".Length..].Replace('\\', '/');
            var key = "business/" + relative;
            Console.WriteLine($"Uploading file {++index:N0}/{files.Count:N0}: {relative}");

            await using var input = entry.Open();
            using var content = new StreamContent(input);
            content.Headers.ContentType =
                new MediaTypeHeaderValue(ContentTypeFor(relative));
            content.Headers.ContentLength = entry.Length;

            using var request = new HttpRequestMessage(
                HttpMethod.Put, _base + "/api/files/" + EscapePath(key))
            { Content = content };

            // Header values must be ASCII; percent-encode original UTF-8 names.
            // The staging Worker decodes these explicit metadata headers.
            // Do NOT send Unicode directly through .NET HttpRequestHeaders.
            request.Headers.TryAddWithoutValidation(
                "X-File-Name-Encoded", Uri.EscapeDataString(Path.GetFileName(relative)));
            request.Headers.TryAddWithoutValidation(
                "X-File-Category", "V6BusinessBackup");
            request.Headers.TryAddWithoutValidation(
                "X-Expected-Sha256", item.Sha256);
            request.Headers.TryAddWithoutValidation(
                "X-Record-Type", "MigrationFile");
            request.Headers.TryAddWithoutValidation(
                "X-Record-Id-Encoded", Uri.EscapeDataString(relative));

            using var response = await _http.SendAsync(request);
            var text = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
                throw new InvalidOperationException(
                    $"File upload failed ({(int)response.StatusCode}): {text}");
            using var digest = JsonDocument.Parse(text);
            if (!digest.RootElement.TryGetProperty("sha256",out var returnedHash) ||
                !string.Equals(returnedHash.GetString(),item.Sha256,StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Cloud file hash mismatch for " + relative);
        }
    }

    private async Task<T?> GetAsync<T>(string path)
    {
        using var response = await _http.GetAsync(_base + path);
        var text = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException(
                $"GET {path} failed ({(int)response.StatusCode}): {text}");

        return JsonSerializer.Deserialize<T>(
            text, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    }

    private async Task PostAsync(string path, object body)
    {
        using var content = new StringContent(
            JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
        using var response = await _http.PostAsync(_base + path, content);
        var text = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException(
                $"POST {path} failed ({(int)response.StatusCode}): {text}");
    }

    private static string EscapePath(string path) =>
        string.Join("/", path.Split('/').Select(Uri.EscapeDataString));

    private static string ContentTypeFor(string path) =>
        Path.GetExtension(path).ToLowerInvariant() switch
        {
            ".pdf" => "application/pdf",
            ".jpg" or ".jpeg" => "image/jpeg",
            ".png" => "image/png",
            ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            ".xls" => "application/vnd.ms-excel",
            ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            ".doc" => "application/msword",
            ".csv" => "text/csv",
            ".json" => "application/json",
            ".txt" => "text/plain",
            _ => "application/octet-stream"
        };

    public void Dispose() => _http.Dispose();
}
