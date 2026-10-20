import SwiftUI
import Foundation
import Security

// Next IPA Factory 1.2: iPhone-owned configuration, OpenAI-managed agent runs.
// Do not place API keys or GitHub tokens in source or iCloud-synced preferences.
enum SecureLocal {
    static func save(_ value: String, name: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "com.nextsolution.ipafactory.local",
                                   kSecAttrAccount as String: name]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var record = query
        record[kSecValueData as String] = Data(value.utf8)
        record[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(record as CFDictionary, nil)
    }
    static func load(_ name: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "com.nextsolution.ipafactory.local",
                                   kSecAttrAccount as String: name,
                                   kSecMatchLimit as String: kSecMatchLimitOne,
                                   kSecReturnData as String: true]
        var raw: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &raw) == errSecSuccess,
              let data = raw as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct AgentRole: Identifiable {
    let id: Int
    let name: String
    let purpose: String
}
enum FactoryRoles {
    static let all: [AgentRole] = [
        .init(id: 0, name: "Prompt Engineer", purpose: "Convert the user request to a precise iOS acceptance specification. Identify every required screen, behavior, and test."),
        .init(id: 1, name: "Architect", purpose: "Design SwiftUI project modules, interfaces, entitlements, and technical architecture."),
        .init(id: 2, name: "UI Developer", purpose: "Implement SwiftUI screens, components, layout, accessibility, and responsive behavior."),
        .init(id: 3, name: "Core Developer", purpose: "Implement business logic, data persistence, API integration and comprehensive unit tests."),
        .init(id: 4, name: "iOS Specialist", purpose: "Check iOS 16 compatibility, TrollStore packaging, permissions and entitlements."),
        .init(id: 5, name: "Integrator", purpose: "Merge architecture, UI, core and platform work into one coherent Xcode project; identify conflicts."),
        .init(id: 6, name: "QA Reviewer", purpose: "Independently compare the integrated project against all acceptance criteria and propose concrete fixes."),
        .init(id: 7, name: "Release Reviewer", purpose: "Independently check readiness, tests, signing constraints, and evidence before final delivery.")
    ]
}

struct AgentTaskRow: Identifiable, Codable {
    var id: UUID = UUID()
    var role: String
    var status: String
    var output: String = ""
    var sessionID: String = ""
}
struct AgentSessionRecord: Codable {
    var id: String
    var status: String?
    var error: String?
}
struct GithubRunRecord: Codable {
    let id: Int
    let status: String
    let conclusion: String?
    let html_url: String
}
struct GithubRunList: Codable {
    let workflow_runs: [GithubRunRecord]
}
struct APIProblem: LocalizedError {
    let details: String
    var errorDescription: String? { details }
}

struct NetworkBridge {
    let openaiKey: String
    let githubToken: String
    static func response(_ request: URLRequest) async throws -> Data {
        let (data, answer) = try await URLSession.shared.data(for: request)
        guard let http = answer as? HTTPURLResponse else { throw APIProblem(details: "No HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIProblem(details: "HTTP " + String(http.statusCode) + " — " + String(body.prefix(650)))
        }
        return data
    }
    private func baseRequest(_ url: URL, key: String, beta: Bool = false) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 70
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if beta { request.setValue("agents=v1", forHTTPHeaderField: "OpenAI-Beta") }
        return request
    }
    private func openai(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        guard !openaiKey.isEmpty else { throw APIProblem(details: "Enter an OpenAI API key in Settings.") }
        guard let url = URL(string: "https://api.openai.com/v1" + path) else { throw APIProblem(details: "Bad OpenAI URL") }
        var request = baseRequest(url, key: openaiKey, beta: true)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data = try await NetworkBridge.response(request)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    private func github(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, Int) {
        guard !githubToken.isEmpty else { throw APIProblem(details: "Enter a fine-grained GitHub token in Settings.") }
        guard let url = URL(string: "https://api.github.com/repos/" + path) else { throw APIProblem(details: "Bad GitHub URL") }
        var request = baseRequest(url, key: githubToken)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, reply) = try await URLSession.shared.data(for: request)
        guard let reply = reply as? HTTPURLResponse else { throw APIProblem(details: "No GitHub response") }
        guard (200...299).contains(reply.statusCode) else {
            throw APIProblem(details: "GitHub " + String(reply.statusCode) + " — " + String((String(data: data, encoding: .utf8) ?? "").prefix(500)))
        }
        return (data, reply.statusCode)
    }
    func agent(_ agentID: String) async throws -> String {
        let value = try await openai("/agents/" + agentID)
        return (value["name"] as? String) ?? (value["id"] as? String) ?? "Connected agent"
    }

    // Best-effort, read-only check: the agent endpoint may omit private tool
    // configuration. A clean result is not a guarantee that a vault isn't needed.
    func checkAgentVaultRequirement(agentID: String) async throws -> Bool {
        let value = try await openai("/agents/" + agentID)
        func hasCredentialID(_ node: Any) -> Bool {
            if let dictionary = node as? [String: Any] {
                if let credential = dictionary["credential_id"] as? String, !credential.isEmpty {
                    return true
                }
                return dictionary.values.contains(where: { hasCredentialID($0) })
            }
            if let list = node as? [Any] {
                return list.contains(where: { hasCredentialID($0) })
            }
            return false
        }
        for key in ["tools", "mcp_servers", "tool_resources", "integrations", "connections"] {
            if let toolConfiguration = value[key], hasCredentialID(toolConfiguration) {
                return true
            }
        }
        return false
    }
    func startSession(agentID: String, task: String) async throws -> String {
        let payload: [String: Any] = [
            "agent_id": agentID,
            "environment": ["type": "openai_hosted"],
            "input": task,
            "stream": false
        ]
        let value = try await openai("/agents/sessions", method: "POST", body: payload)
        guard let id = value["id"] as? String, !id.isEmpty else { throw APIProblem(details: "OpenAI did not return a session ID.") }
        return id
    }
    func pollAgent(_ sessionID: String, onStatus: (@MainActor (String) -> Void)? = nil) async throws -> String? {
        let state = try await openai("/agents/sessions/" + sessionID)
        let status = (state["status"] as? String) ?? "unknown"
        if let onStatus { await onStatus(status) }
        if status == "failed" {
            throw APIProblem(details: "Agent failed: " + String(describing: state["error"] ?? "Unknown"))
        }
        if status == "requires_action" {
            throw APIProblem(details: "Agent requested a tool approval. Configure that action in the agent; this test build does not silently grant it.")
        }
        guard status == "idle" else { return nil }
        let items = try await openai("/agents/sessions/" + sessionID + "/items?order=asc&limit=100")
        let entries = items["data"] as? [[String: Any]] ?? []
        var texts: [String] = []
        for entry in entries {
            guard (entry["role"] as? String) == "assistant" else { continue }
            if let content = entry["content"] as? [[String: Any]] {
                for piece in content where (piece["type"] as? String) == "output_text" {
                    if let text = piece["text"] as? String { texts.append(text) }
                }
            }
        }
        let output = texts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Avoid reporting the user's input as completed agent output.
        return output.isEmpty ? nil : output
    }
    func runAgent(agentID: String, task: String, onStarted: @escaping @MainActor (String) -> Void) async throws -> String {
        try await runAgentWithProgress(agentID: agentID, task: task, onStarted: onStarted, onStatus: { _ in })
    }
    // Reports the actual hosted session state after each API poll; no invented task milestones.
    func runAgentWithProgress(agentID: String, task: String,
                              onStarted: @escaping @MainActor (String) -> Void,
                              onStatus: @escaping @MainActor (String) -> Void) async throws -> String {
        let session = try await startSession(agentID: agentID, task: task)
        await onStarted(session)
        for _ in 0..<150 {
            try Task.checkCancellation()
            if let final = try await pollAgent(session, onStatus: onStatus) { return final }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw APIProblem(details: "Session still running after 5 minutes. Session ID: " + session)
    }
    func checkGithub(repo: String) async throws -> String {
        let (data, _) = try await github(repo)
        let parsed = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (parsed["full_name"] as? String) ?? repo
    }
    func triggerBuild(repo: String, branch: String, workflow: String) async throws {
        let encoded = workflow.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workflow
        _ = try await github(repo + "/actions/workflows/" + encoded + "/dispatches", method: "POST", body: ["ref": branch])
    }
    func latestRun(repo: String, branch: String, workflow: String) async throws -> GithubRunRecord? {
        let encoded = workflow.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workflow
        let path = repo + "/actions/workflows/" + encoded + "/runs?branch=" + (branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch) + "&per_page=10"
        let (data, _) = try await github(path)
        return try JSONDecoder().decode(GithubRunList.self, from: data).workflow_runs.first
    }
}

@MainActor final class LocalFactoryState: ObservableObject {
    @AppStorage("nextfactory.repo") var repo = "zeshan0727/NextJailbreak"
    @AppStorage("nextfactory.branch") var branch = "feature/next-ipa-factory-v1"
    @AppStorage("nextfactory.workflow") var workflow = "build-next-ipa-factory.yml"
    @AppStorage("nextfactory.ids") private var idsJSON = "{}"
    @AppStorage("nextfactory.history") private var historyJSON = "[]"
    @Published var openaiKey = SecureLocal.load("openai")
    @Published var githubToken = SecureLocal.load("github")
    @Published var agentIDs: [String: String] = [:]
    @Published var prompt = ""
    @Published var logs = "Ready. Configure an OpenAI API key and agent IDs to begin."
    @Published var busy = false
    @Published var tasks: [AgentTaskRow] = []
    @Published var latestBuild: GithubRunRecord?
    @Published var selectedAgentCount = 8
    var gateway: NetworkBridge { NetworkBridge(openaiKey: openaiKey, githubToken: githubToken) }
    init() {
        if let data = idsJSON.data(using: .utf8),
           let value = try? JSONDecoder().decode([String: String].self, from: data) { agentIDs = value }
        if let data = historyJSON.data(using: .utf8),
           let value = try? JSONDecoder().decode([AgentTaskRow].self, from: data) { tasks = value }
    }
    func saveSettings() {
        SecureLocal.save(openaiKey.trimmingCharacters(in: .whitespacesAndNewlines), name: "openai")
        SecureLocal.save(githubToken.trimmingCharacters(in: .whitespacesAndNewlines), name: "github")
        idsJSON = String(data: ((try? JSONEncoder().encode(agentIDs)) ?? Data("{}".utf8)), encoding: .utf8) ?? "{}"
        logs = "Saved locally on this iPhone. No PC server is required."
    }
    private func persist() {
        historyJSON = String(data: ((try? JSONEncoder().encode(Array(tasks.prefix(32)))) ?? Data("[]".utf8)), encoding: .utf8) ?? "[]"
    }
    func verify() async {
        busy = true
        defer { busy = false }
        do {
            let id = agentIDs[FactoryRoles.all[0].name] ?? ""
            guard !id.isEmpty else { throw APIProblem(details: "Add your first saved agent ID.") }
            let name = try await gateway.agent(id)
            logs = "OpenAI connected: " + name + ". Credentials kept on the iPhone."
        } catch { logs = error.localizedDescription }
    }
    func checkGithub() async {
        busy = true
        defer { busy = false }
        do {
            logs = "GitHub connected: " + (try await gateway.checkGithub(repo: repo))
        } catch { logs = error.localizedDescription }
    }
    func build() async {
        busy = true
        defer { busy = false }
        do {
            try await gateway.triggerBuild(repo: repo, branch: branch, workflow: workflow)
            logs = "Build requested from GitHub Actions. Refresh after a short wait to see compilation status."
        } catch { logs = error.localizedDescription }
    }
    func refreshBuild() async {
        do {
            latestBuild = try await gateway.latestRun(repo: repo, branch: branch, workflow: workflow)
            if let run = latestBuild {
                logs = "GitHub run #" + String(run.id) + ": " + run.status + ", " + (run.conclusion ?? "pending")
            } else { logs = "No workflow runs found." }
        } catch { logs = error.localizedDescription }
    }
    func runCommand() async {
        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { logs = "Enter an app request first."; return }
        let selected = Array(FactoryRoles.all.prefix(selectedAgentCount))
        for role in selected {
            guard !(agentIDs[role.name] ?? "").isEmpty else { logs = "Missing ID: " + role.name; return }
        }
        busy = true
        tasks = selected.map { AgentTaskRow(role: $0.name, status: "Queued") }
        logs = "Starting managed agent sessions in OpenAI; no separate backend."
        persist()
        let service = gateway
        func run(_ index: Int, instruction: String) async -> String {
            let role = selected[index]
            let id = agentIDs[role.name] ?? ""
            tasks[index].status = "Working"
            persist()
            do {
                let text = try await service.runAgent(agentID: id, task: instruction) { session in
                    self.tasks[index].sessionID = session
                    self.persist()
                }
                tasks[index].status = "Completed"
                tasks[index].output = text
                persist()
                return text
            } catch {
                tasks[index].status = "Failed"
                tasks[index].output = error.localizedDescription
                persist()
                return "FAILED (" + role.name + "): " + error.localizedDescription
            }
        }
        let spec = await run(0, instruction: "USER REQUEST:\n" + instruction + "\n\nYour role: " + selected[0].purpose + "\nDeliver a concrete, testable specification, not unsupported success claims.")
        var outputs = [String](repeating: "", count: selected.count)
        outputs[0] = spec
        if selected.count > 1 {
            await withTaskGroup(of: (Int, String).self) { group in
                for index in 1..<min(selected.count, 5) {
                    let role = selected[index]
                    let input = "USER REQUEST:\n" + instruction + "\n\nACCEPTANCE SPECIFICATION:\n" + String(spec.prefix(15000)) + "\n\nROLE:\n" + role.purpose + "\nProvide specific source-code changes or verifiable engineering output. Never claim to have built an IPA without a build log."
                    group.addTask { [service, id = self.agentIDs[role.name] ?? ""] in
                        do {
                            let session = try await service.startSession(agentID: id, task: input)
                            let result = try await service.runExistingSession(session)
                            return (index, "SESSION " + session + "\n" + result)
                        } catch { return (index, "FAILED: " + error.localizedDescription) }
                    }
                    tasks[index].status = "Working"
                }
                for await (index, answer) in group {
                    outputs[index] = answer
                    tasks[index].output = answer
                    tasks[index].status = answer.hasPrefix("FAILED") ? "Failed" : "Completed"
                    persist()
                }
            }
        }
        if selected.count > 5 {
            for index in 5..<selected.count {
                let previous = outputs.enumerated().map { String($0.offset + 1) + ": " + $0.element.prefix(6500) }.joined(separator: "\n---\n")
                outputs[index] = await run(index, instruction: "USER REQUEST:\n" + instruction + "\nSPEC:\n" + spec.prefix(12000) + "\nPREVIOUS AGENT WORK:\n" + previous.prefix(25000) + "\nROLE:\n" + selected[index].purpose + "\nIdentify explicit discrepancies and needed fixes.")
            }
        }
        logs = "Agent work finished. Review each result below. GitHub compilation is a separate verified step."
        busy = false
        persist()
    }
}

// Keep session execution reusable by the concurrent developer calls.
extension NetworkBridge {
    func runExistingSession(_ session: String) async throws -> String {
        for _ in 0..<150 {
            try Task.checkCancellation()
            if let result = try await pollAgent(session) { return result }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw APIProblem(details: "Agent session continues in OpenAI: " + session)
    }
}
