import Foundation
import Security

struct DeepSeekMessage: Codable {
    let role: String
    let content: String
}

enum DeepSeekError: LocalizedError {
    case missingKey
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add and save a DeepSeek API key in Settings first."
        case .invalidResponse: return "DeepSeek returned an unreadable response."
        case .server(let message): return message
        }
    }
}

final class DeepSeekService: ObservableObject {
    static let shared = DeepSeekService()
    private static let keychainService = "com.nextsolution.dailyledger.deepseek"
    private static let keychainAccount = "api-key"

    @Published private(set) var promptTokens: Int
    @Published private(set) var completionTokens: Int
    @Published private(set) var totalTokens: Int

    private init() {
        promptTokens = UserDefaults.standard.integer(forKey: "DeepSeekPromptTokens")
        completionTokens = UserDefaults.standard.integer(forKey: "DeepSeekCompletionTokens")
        totalTokens = UserDefaults.standard.integer(forKey: "DeepSeekTotalTokens")
    }

    var hasAPIKey: Bool { !(loadAPIKey() ?? "").isEmpty }

    func saveAPIKey(_ value: String) throws {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            deleteAPIKey()
            return
        }
        let data = Data(cleaned.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeepSeekError.server("The API key could not be saved securely.")
        }
        try? ProtectedSecretStore.shared.save(cleaned, for: Self.keychainService)
    }

    func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        guard let protectedValue = ProtectedSecretStore.shared.value(for: Self.keychainService),
              !protectedValue.isEmpty else { return nil }
        try? saveAPIKey(protectedValue)
        return protectedValue
    }

    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        ProtectedSecretStore.shared.removeValue(for: Self.keychainService)
    }

    func request(
        messages: [DeepSeekMessage],
        model: String,
        maxTokens: Int = 650
    ) async throws -> String {
        guard let key = loadAPIKey(), !key.isEmpty else { throw DeepSeekError.missingKey }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            DeepSeekRequest(
                model: model,
                messages: messages,
                thinking: .init(type: "disabled"),
                maxTokens: min(max(maxTokens, 16), 650)
            )
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(DeepSeekAPIError.self, from: data)
            throw DeepSeekError.server(apiError?.error.message ?? "DeepSeek request failed (HTTP \(http.statusCode)).")
        }
        guard let decoded = try? JSONDecoder().decode(DeepSeekResponse.self, from: data),
              let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.invalidResponse
        }
        if let usage = decoded.usage {
            await MainActor.run { record(usage) }
        }
        return content
    }

    func resetUsage() {
        promptTokens = 0
        completionTokens = 0
        totalTokens = 0
        saveUsage()
    }

    private func record(_ usage: DeepSeekResponse.Usage) {
        promptTokens += usage.promptTokens
        completionTokens += usage.completionTokens
        totalTokens += usage.totalTokens
        saveUsage()
    }

    private func saveUsage() {
        UserDefaults.standard.set(promptTokens, forKey: "DeepSeekPromptTokens")
        UserDefaults.standard.set(completionTokens, forKey: "DeepSeekCompletionTokens")
        UserDefaults.standard.set(totalTokens, forKey: "DeepSeekTotalTokens")
    }
}

private struct DeepSeekRequest: Encodable {
    let model: String
    let messages: [DeepSeekMessage]
    let thinking: Thinking
    let maxTokens: Int

    private enum CodingKeys: String, CodingKey {
        case model, messages, thinking
        case maxTokens = "max_tokens"
    }

    struct Thinking: Encodable { let type: String }
}

private struct DeepSeekResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?
    struct Choice: Decodable {
        let message: DeepSeekMessage
    }
    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

private struct DeepSeekAPIError: Decodable {
    let error: APIError
    struct APIError: Decodable { let message: String }
}
