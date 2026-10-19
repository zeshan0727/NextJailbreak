import Foundation
import Security

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

enum OpenAIServiceError: LocalizedError {
    case missingKey, invalidResponse, server(String)
    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add and save an OpenAI API key in Settings first."
        case .invalidResponse: return "OpenAI returned an unreadable response."
        case .server(let message): return message
        }
    }
}

final class OpenAIService: ObservableObject {
    static let shared = OpenAIService()
    static let selectableModels = [
        "gpt-4.1-nano", "gpt-4.1-mini", "gpt-4o-mini",
        "gpt-5-nano", "gpt-5-mini", "gpt-5.6-sol"
    ]
    private static let service = "com.nextsolution.dailyledger.openai"
    private static let account = "api-key"
    @Published private(set) var inputTokens = UserDefaults.standard.integer(forKey: "OpenAIInputTokens")
    @Published private(set) var outputTokens = UserDefaults.standard.integer(forKey: "OpenAIOutputTokens")
    var totalTokens: Int { inputTokens + outputTokens }
    var hasAPIKey: Bool { !(loadAPIKey() ?? "").isEmpty }

    func saveAPIKey(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { deleteAPIKey(); return }

        // The protected app store is the reliable source of truth for TrollStore
        // and rootless installs. If Keychain entitlement behavior differs, the
        // OpenAI key still persists securely inside this device/app container.
        try ProtectedSecretStore.shared.save(value, for: Self.service)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        _ = SecItemAdd(item as CFDictionary, nil) // best-effort mirror

        guard loadAPIKey() == value else {
            throw OpenAIServiceError.server("The OpenAI API key could not be verified after saving.")
        }
    }

    func loadAPIKey() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        guard let protectedValue = ProtectedSecretStore.shared.value(for: Self.service),
              !protectedValue.isEmpty else { return nil }
        try? saveAPIKey(protectedValue)
        return protectedValue
    }

    func deleteAPIKey() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.account]
        SecItemDelete(query as CFDictionary)
        ProtectedSecretStore.shared.removeValue(for: Self.service)
    }

    func request(messages: [OpenAIMessage], model: String, maxTokens: Int = 500) async throws -> String {
        guard let key = loadAPIKey(), !key.isEmpty else { throw OpenAIServiceError.missingKey }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(OpenAIRequest(
            model: model, messages: messages, maxCompletionTokens: min(max(maxTokens, 16), 700)
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(OpenAIAPIError.self, from: data)
            throw OpenAIServiceError.server(error?.error.message ?? "OpenAI request failed (HTTP \(http.statusCode)).")
        }
        guard let decoded = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
              let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw OpenAIServiceError.invalidResponse
        }
        if let usage = decoded.usage {
            await MainActor.run {
                inputTokens += usage.promptTokens
                outputTokens += usage.completionTokens
                UserDefaults.standard.set(inputTokens, forKey: "OpenAIInputTokens")
                UserDefaults.standard.set(outputTokens, forKey: "OpenAIOutputTokens")
            }
        }
        return content
    }
}

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let maxCompletionTokens: Int
    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxCompletionTokens = "max_completion_tokens"
    }
}
private struct OpenAIResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?
    struct Choice: Decodable { let message: OpenAIMessage }
    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
}
private struct OpenAIAPIError: Decodable {
    let error: Detail
    struct Detail: Decodable { let message: String }
}
