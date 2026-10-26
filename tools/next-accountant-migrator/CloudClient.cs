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
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("NextAccountantMigrator/0.1.0");
    }

    public Task<Health?> HealthAsync() => GetAsync<Health>("/health");

    public async Task ApplySchemaAsync(string sql, int sourceSchemaVersion) =>
        await PostAsync("/api/admin/apply-schema", new { sql, sourceSchemaVersion });

    public async Task ImportBatchAsync(string table, object rows) =>
        await PostAsync("/api/admin/import-batch", new { table, rows });

    public async Task<Dictionary<string,long>> CountsAsync()
    {
        var result = await GetAsync<RemoteCounts>("/api/admin/counts")
            ?? throw new InvalidOperationException("Cloud count response was empty.");
        return result.Tables.ToDictionary(
            x => x.Name, x => x.Count, StringComparer.OrdinalIgnoreCase);
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

            request.Headers.TryAddWithoutValidation(
                "X-File-Name", Path.GetFileName(relative));
            request.Headers.TryAddWithoutValidation(
                "X-File-Category", "V6BusinessBackup");
            request.Headers.TryAddWithoutValidation(
                "X-Record-Type", "MigrationFile");
            request.Headers.TryAddWithoutValidation(
                "X-Record-Id", relative);

            using var response = await _http.SendAsync(request);
            var text = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
                throw new InvalidOperationException(
                    $"File upload failed ({(int)response.StatusCode}): {text}");
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
