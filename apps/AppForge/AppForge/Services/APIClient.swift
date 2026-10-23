import Foundation

struct AIMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [AIMessage]
    let temperature: Double = 0.2
    let response_format: JSONFormat?
}
private struct JSONFormat: Encodable { let type = "json_object" }

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

/// Configurable OpenAI-compatible chat/completions client (including custom hosts).
struct AIClient {
    let endpoint: String
    let model: String
    let token: String

    func chat(system: String, user: String, jsonMode: Bool = false) async throws -> String {
        guard !token.isEmpty, !model.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ForgeError.message("Set an AI model and API key in Settings.")
        }
        guard var components = URLComponents(string: endpoint), components.scheme == "https", components.host != nil else {
            throw ForgeError.message("Enter a valid HTTPS base URL.")
        }
        if !components.path.hasSuffix("/chat/completions") {
            let suffix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = "/" + (suffix.isEmpty ? "" : suffix + "/") + "chat/completions"
        }
        guard let url = components.url else { throw ForgeError.message("Invalid API endpoint") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Official OpenAI Chat Completions supports JSON object mode.
        // Omit this field for alternative providers, which may not support it.
        let openAI = components.host?.lowercased() == "api.openai.com"
        request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: [
            AIMessage(role: "system", content: system),
            AIMessage(role: "user", content: user)
        ], response_format: jsonMode && openAI ? JSONFormat() : nil))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ForgeError.message("Invalid AI server response")
            }
            switch http.statusCode {
            case 200...299: break
            case 401, 403: throw ForgeError.message("AI key is invalid, expired, or lacks access")
            case 429: throw ForgeError.message("AI rate limit reached (429). Wait or change your free-tier model")
            default:
                let detail = String(decoding: data.prefix(450), as: UTF8.self)
                throw ForgeError.message("AI returned HTTP \(http.statusCode): \(detail)")
            }
            let parsed = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let text = parsed.choices.first?.message.content, !text.isEmpty else {
                throw ForgeError.message("Model returned an empty answer")
            }
            return text
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw ForgeError.message("You are offline. Reconnect to use the AI provider")
        }
    }

    static let promptSystem = """
    You are a principal iOS engineer and prompt architect. Transform the user's requirement into a detailed,
    implementable native SwiftUI iOS 16+ app specification. Include screens, interactions, state,
    persistence, error states, accessibility, minimal dependencies and acceptance criteria.
    Return the finished technical generation prompt only, not commentary.
    """

    static let codeSystem = """
    You generate COMPLETE minimal-dependency SwiftUI iOS 16+ applications. Return STRICT JSON ONLY:
    {"appName":"PlainASCIIName","bundleId":"com.example.app","files":[{"path":"Sources/ContentView.swift","content":"..."}]}
    No markdown fences, no prose. Every file must be a compilable Swift file under Sources/.
    DO NOT provide an @main App, Info.plist, project.yml, workflow or assets; those are injected.
    MUST define struct ContentView: View with a working body, including all referenced types.
    CRITICAL: models used with NavigationLink(value:) or navigationDestination(for:) MUST conform to Hashable.
    Prefer explicit NavigationLink(destination:) if a model cannot be Hashable.
    Keep SwiftUI body expressions small: split long NavigationStack, List, swipeActions, toolbar and alert
    combinations into named child View structs. Avoid compiler type-check timeout.
    Keep outputs COMPACT so the whole JSON fits the model response window. Escape Swift strings within JSON correctly.
    No external packages, secrets, networking backends, missing assets or TODO stubs.
    Assume deployment iOS 16 and Swift 5.9 features, no iOS 17-only APIs.
    Include complete production-quality code and import statements in every file that needs them.
    """
}
