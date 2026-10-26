using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace NextAccountant.Migrator;

internal static class KeyEnrollment
{
    private static readonly string SecureDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "NextAccountant", "StagingCredential");
    private static readonly string PrivateKeyPath =
        Path.Combine(SecureDirectory, "staging-rsa-private.dpapi");

    public static void PreparePublicKey()
    {
        Directory.CreateDirectory(SecureDirectory);
        using var rsa = ReadOrCreateKey();
        var publicKey = rsa.ExportSubjectPublicKeyInfoPem();
        var exported = Path.Combine(AppContext.BaseDirectory, "NEXT_ACCOUNTANT_STAGING_PUBLIC_KEY.pem");
        File.WriteAllText(exported, publicKey);
        Console.WriteLine("Staging public key prepared:");
        Console.WriteLine(exported);
        Console.WriteLine("The private RSA key stays on this Windows user profile, protected by Windows DPAPI.");
        Console.WriteLine("Only the PUBLIC KEY file may be shared with ChatGPT.");
        Console.WriteLine("Never share files from " + SecureDirectory);
    }

    public static string? TryReadToken()
    {
        var credentialPath = Path.Combine(AppContext.BaseDirectory,
            "NEXT_ACCOUNTANT_STAGING_CREDENTIAL.txt");
        if (!File.Exists(credentialPath)) return null;
        if (!File.Exists(PrivateKeyPath))
            throw new InvalidDataException(
                "This Windows user has no prepared staging private key. Run PREPARE_STAGING_KEY.bat first.");

        using var rsa = ReadOrCreateKey();
        var ciphertext = Convert.FromBase64String(
            File.ReadAllText(credentialPath).Trim());
        var plaintext = rsa.Decrypt(ciphertext, RSAEncryptionPadding.OaepSHA256);
        var token = System.Text.Encoding.UTF8.GetString(plaintext);
        CryptographicOperations.ZeroMemory(plaintext);
        if (!Regex.IsMatch(token, "^[a-fA-F0-9]{64}$"))
            throw new InvalidDataException("Decrypted staging credential format is invalid.");
        return token;
    }

    private static RSA ReadOrCreateKey()
    {
        var rsa = RSA.Create();
        if (File.Exists(PrivateKeyPath))
        {
            var encrypted = File.ReadAllBytes(PrivateKeyPath);
            var raw = ProtectedData.Unprotect(encrypted,null,DataProtectionScope.CurrentUser);
            try { rsa.ImportPkcs8PrivateKey(raw,out _); }
            finally { CryptographicOperations.ZeroMemory(raw); }
        }
        else
        {
            rsa.KeySize = 3072;
            var raw = rsa.ExportPkcs8PrivateKey();
            try
            {
                File.WriteAllBytes(PrivateKeyPath,ProtectedData.Protect(
                    raw,null,DataProtectionScope.CurrentUser));
            }
            finally { CryptographicOperations.ZeroMemory(raw); }
        }
        return rsa;
    }
}
