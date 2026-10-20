import SwiftUI
import Security
import Foundation

enum Palette {
    static let background = Color(red: 0.965, green: 0.972, blue: 0.995)
    static let primary = Color(red: 0.31, green: 0.31, blue: 0.89)
    static let muted = Color(red: 0.45, green: 0.49, blue: 0.58)
}
struct AgentSettingsResponse: Codable {
    let roles: [String]
    let ids: [String: String]
}
struct AgentSettingsRequest: Encodable {
    let ids: [String: String]
}
struct ServerHealth: Codable {
    let ok: Bool
    let version: String
}
struct TaskRequest: Encodable {
    let prompt: String
    let agent_count: Int
}
struct TaskResponse: Codable, Identifiable {
    let id: String
    let prompt: String
    let status: String
    let message: String
    let agent_count: Int
    let agents: [String: ProgressInfo]
    let download_url: String?
}
struct ProgressInfo: Codable {
    let state: String
    let detail: String
}
struct CancelInfo: Codable {
    let cancel_requested: Bool
}
struct NetworkError: LocalizedError {
    let description: String
    var errorDescription: String? { description }
}
enum Vault {
    private static let account = "next-ipa-factory-backend"
    static func read() -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ token: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard !token.isEmpty else { return }
        var options = q
        options[kSecValueData as String] = Data(token.utf8)
        options[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(options as CFDictionary, nil)
    }
}
struct API {
    let base: String
    let token: String
    private func url(_ path: String) throws -> URL {
        guard let host = URL(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              host.scheme == "https", host.host != nil else {
            throw NetworkError(description: "Use an HTTPS backend URL.")
        }
        let root = host.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let address = URL(string: root + path) else {
            throw NetworkError(description: "Invalid backend URL.")
        }
        return address
    }
    private func request(_ path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        var r = URLRequest(url: try url(path))
        r.httpMethod = method
        r.timeoutInterval = 45
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body = body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }
    private func send<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request(path, method: method, body: body))
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw NetworkError(description: "Backend refused the request. Check token and server.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func health() async throws -> ServerHealth { try await send("/health") }
    func agents() async throws -> AgentSettingsResponse { try await send("/agents") }
    func save(_ ids: [String: String]) async throws -> AgentSettingsResponse {
        let body = try JSONEncoder().encode(AgentSettingsRequest(ids: ids))
        return try await send("/agents", method: "PUT", body: body)
    }
    func tasks() async throws -> [TaskResponse] { try await send("/tasks") }
    func create(_ prompt: String, count: Int) async throws -> TaskResponse {
        let body = try JSONEncoder().encode(TaskRequest(prompt: prompt, agent_count: count))
        return try await send("/tasks", method: "POST", body: body)
    }
    func cancel(_ id: String) async throws {
        let _: CancelInfo = try await send("/tasks/" + id + "/cancel", method: "POST")
    }
    func source(_ id: String) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(for: request("/tasks/" + id + "/source.zip"))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetworkError(description: "Source file not ready.")
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Factory-" + String(id.prefix(8)) + "-SOURCE.zip")
        try data.write(to: file, options: .atomic)
        return file
    }
}
@MainActor final class FactoryState: ObservableObject {
    @AppStorage("factoryEndpoint") var endpoint = ""
    @Published var token = Vault.read()
    @Published var roles: [String] = [
        "Prompt Engineer", "Architect", "UI Developer", "Core Developer",
        "iOS Specialist", "Integrator", "QA Reviewer", "Release Reviewer",
        "Security Reviewer", "Accessibility Reviewer", "Performance Reviewer", "Second QA Reviewer"
    ]
    @Published var agentIDs: [String: String] = [:]
    @Published var tasks: [TaskResponse] = []
    @Published var message: String? = nil
    @Published var online = false
    @Published var working = false
    var api: API { API(base: endpoint, token: token) }
    init() {
        if let cached = UserDefaults.standard.dictionary(forKey: "agentIDCache") as? [String: String] {
            agentIDs = cached
        }
    }
    func updateToken(_ value: String) {
        token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        Vault.write(token)
    }
    func connect() async {
        working = true
        defer { working = false }
        do {
            guard !token.isEmpty else { throw NetworkError(description: "Enter your access token.") }
            let health = try await api.health()
            guard health.ok else { throw NetworkError(description: "Backend health failed.") }
            await fetchAgents()
            try await refreshTasks()
            online = true
            message = "Connected to backend v" + health.version
        } catch {
            online = false
            message = error.localizedDescription
        }
    }
    func fetchAgents() async {
        do {
            let result = try await api.agents()
            roles = result.roles
            agentIDs = result.ids
            UserDefaults.standard.set(result.ids, forKey: "agentIDCache")
        } catch { message = error.localizedDescription }
    }
    func saveAgents() async {
        working = true
        defer { working = false }
        do {
            let result = try await api.save(agentIDs)
            agentIDs = result.ids
            UserDefaults.standard.set(result.ids, forKey: "agentIDCache")
            message = "Saved " + String(result.ids.count) + " agent IDs securely on your backend."
        } catch { message = error.localizedDescription }
    }
    func refreshTasks() async throws {
        tasks = try await api.tasks()
    }
    func refresh() async {
        do { try await refreshTasks() }
        catch { message = error.localizedDescription }
    }
    func create(_ prompt: String, count: Int) async {
        working = true
        defer { working = false }
        do {
            _ = try await api.create(prompt, count: count)
            try await refreshTasks()
            message = "Task submitted to your agent team."
        } catch { message = error.localizedDescription }
    }
    func cancel(_ id: String) async {
        do {
            try await api.cancel(id)
            try await refreshTasks()
        } catch { message = error.localizedDescription }
    }
}
struct WhitePanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.primary.opacity(0.07)))
    }
}
struct FactoryMain: View {
    @EnvironmentObject var model: FactoryState
    @State private var prompt = ""
    @State private var count = 8
    @State private var exportURL: URL? = nil
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WhitePanel {
                        HStack(spacing: 12) {
                            Image(systemName: "cpu.fill").foregroundStyle(Palette.primary).font(.title2)
                            VStack(alignment: .leading) {
                                Text("Next IPA Factory").font(.title3.weight(.bold))
                                Text("Parallel iPhone app engineering").font(.caption).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Circle().fill(model.online ? Color.green : Color.orange).frame(width: 11, height: 11)
                        }
                    }
                    WhitePanel {
                        VStack(alignment: .leading, spacing: 11) {
                            Label("Describe your iPhone app", systemImage: "sparkles").font(.headline)
                            TextEditor(text: $prompt)
                                .scrollContentBackground(.hidden)
                                .frame(height: 125).padding(6)
                                .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                            HStack {
                                Text("Agents").font(.subheadline.weight(.medium))
                                Spacer()
                                Picker("Agents", selection: $count) {
                                    ForEach([4, 6, 8, 9, 10, 11, 12], id: \.self) { n in
                                        Text(String(n)).tag(n)
                                    }
                                }.pickerStyle(.menu)
                            }
                            Button {
                                let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                                Task { await model.create(request, count: count) }
                            } label: {
                                HStack {
                                    Image(systemName: "bolt.fill")
                                    Text(model.working ? "Processing" : "Generate App")
                                }.frame(maxWidth: .infinity).padding(9)
                            }.buttonStyle(.borderedProminent).tint(Palette.primary)
                                .disabled(model.working || prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 15)
                        }
                    }
                    HStack {
                        Text("Recent Builds").font(.headline)
                        Spacer()
                        Button { Task { await model.refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }.padding(.horizontal, 3)
                    ForEach(model.tasks) { task in
                        WhitePanel {
                            VStack(alignment: .leading, spacing: 11) {
                                HStack {
                                    Text(String(task.id.prefix(8)).uppercased()).font(.caption.monospaced()).foregroundStyle(Palette.primary)
                                    Spacer()
                                    Text(task.status.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                                }
                                Text(task.prompt).font(.subheadline.weight(.medium)).lineLimit(3)
                                Text(task.message).font(.caption).foregroundStyle(Palette.muted)
                                ProgressView(value: Double(task.agents.values.filter { $0.state == "completed" }.count),
                                             total: Double(max(1, task.agent_count)))
                                HStack {
                                    Text(String(task.agents.count) + " active roles").font(.caption2).foregroundStyle(Palette.muted)
                                    Spacer()
                                    if task.download_url != nil {
                                        Button("Source ZIP") {
                                            Task {
                                                do { exportURL = try await model.api.source(task.id) }
                                                catch { model.message = error.localizedDescription }
                                            }
                                        }.font(.caption)
                                    }
                                    if ["queued","planning","generating","integrating","reviewing"].contains(task.status) {
                                        Button("Stop", role: .destructive) {
                                            Task { await model.cancel(task.id) }
                                        }.font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }.padding(17)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Factory")
            .task { if !model.endpoint.isEmpty && !model.token.isEmpty { await model.connect() } }
            .refreshable { await model.refresh() }
            .sheet(item: Binding<SharedFile?>(
                get: { exportURL.map { SharedFile(url: $0) } },
                set: { exportURL = $0?.url }
            )) { file in
                NavigationStack {
                    ShareLink(item: file.url) {
                        Label("Share source ZIP", systemImage: "square.and.arrow.up")
                    }.navigationTitle("Export")
                }.presentationDetents([.medium])
            }
        }
    }
}
struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
struct FactorySettings: View {
    @EnvironmentObject var model: FactoryState
    @State private var temporaryToken = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WhitePanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Secure server connection", systemImage: "lock.shield").font(.headline)
                            TextField("https://your-backend.example", text: $model.endpoint)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .keyboardType(.URL).textFieldStyle(.roundedBorder)
                            SecureField("Access token", text: $temporaryToken).textFieldStyle(.roundedBorder)
                            Button("Save & Connect") {
                                if !temporaryToken.isEmpty { model.updateToken(temporaryToken); temporaryToken = "" }
                                Task { await model.connect() }
                            }.buttonStyle(.borderedProminent).tint(Palette.primary)
                            if let message = model.message {
                                Text(message).font(.caption).foregroundStyle(Palette.muted)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    WhitePanel {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                Label("Agent IDs", systemImage: "person.3.sequence.fill").font(.headline)
                                Spacer()
                                Button("Reload") { Task { await model.fetchAgents() } }.font(.caption)
                            }
                            Text("Assign OpenAI Saved Agents API identifiers (agent_...) to roles. Saved to the backend and cached on this iPhone.")
                                .font(.caption).foregroundStyle(Palette.muted)
                            ForEach(model.roles, id: \.self) { role in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(role).font(.caption.weight(.semibold))
                                    TextField("agent_...", text: Binding(
                                        get: { model.agentIDs[role] ?? "" },
                                        set: { model.agentIDs[role] = $0 }
                                    )).font(.caption.monospaced())
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            Button("Save Agent IDs") { Task { await model.saveAgents() } }
                                .frame(maxWidth: .infinity).buttonStyle(.borderedProminent)
                                .tint(Palette.primary).disabled(model.working)
                        }
                    }
                    WhitePanel {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("Build verification", systemImage: "checkmark.shield").font(.headline)
                            Text("Agent-generated sources must be compiled on a macOS Xcode runner before calling them IPA/TIPA builds.")
                            Text("Unsigned TIPA packages require compatible TrollStore installation. Actual device testing is separate.")
                        }.font(.caption).foregroundStyle(Palette.muted)
                    }
                }.padding(17)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Settings")
        }
    }
}
@main struct NextIPAFactoryApp: App {
    @StateObject private var model = FactoryState()
    var body: some Scene {
        WindowGroup {
            TabView {
                FactoryMain().tabItem { Label("Builds", systemImage: "hammer.fill") }
                FactorySettings().tabItem { Label("Agents", systemImage: "person.3.fill") }
            }
            .environmentObject(model)
            .tint(Palette.primary)
        }
    }
}
