import SwiftUI
import Foundation

struct FactoryGeneratedFile: Codable, Identifiable {
    var path: String
    var content: String
    var id: String { path }
}
struct FactoryGeneratedManifest: Codable {
    var files: [FactoryGeneratedFile]
}
struct FactoryGenerationEvent: Identifiable {
    let id = UUID()
    let time = Date()
    let detail: String
}
struct FactoryGitWriter {
    let token: String
    let repo: String
    let branch: String
    private func request(_ suffix: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        guard !token.isEmpty else { throw APIProblem(details: "Save a GitHub fine-grained personal access token in Settings.") }
        guard let url = URL(string: "https://api.github.com/repos/" + repo + suffix) else { throw APIProblem(details: "Invalid GitHub request") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 70
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let bytes = try await NetworkBridge.response(req)
        return (try JSONSerialization.jsonObject(with: bytes)) as? [String: Any] ?? [:]
    }
    func publish(slug: String, files: [FactoryGeneratedFile],
                 onProgress: (@MainActor (String) -> Void)? = nil) async throws -> String {
        if let onProgress { await onProgress("Validating generated files") }
        guard slug.range(of: "^[a-z0-9][a-z0-9-]{1,35}$", options: .regularExpression) != nil else {
            throw APIProblem(details: "App slug must be 2–36 lowercase letters, numbers or dashes.")
        }
        guard (2...25).contains(files.count),
              files.contains(where: { $0.path == "project.yml" }),
              files.contains(where: { $0.path.hasSuffix(".swift") }) else {
            throw APIProblem(details: "Need project.yml and at least one Swift source file (2–25 files).")
        }
        for file in files {
            guard !file.path.contains(".."), !file.path.hasPrefix("/"),
                  !file.path.contains("\\"),
                  !file.path.contains("\n"),
                  (file.path == "project.yml" || file.path.hasPrefix("Sources/")),
                  [".swift", ".yml", ".plist", ".json", ".xcassets"].contains(where: { file.path.hasSuffix($0) }),
                  file.content.utf8.count < 100000 else {
                throw APIProblem(details: "Unsafe source path or file size: " + file.path)
            }
        }
        guard files.reduce(0, { $0 + $1.content.utf8.count }) < 400000 else {
            throw APIProblem(details: "Generated project exceeds 400 KB source limit.")
        }
        let project = files.first(where: { $0.path == "project.yml" })?.content ?? ""
        guard project.contains("name: GeneratedApp"), project.contains("GeneratedApp:"), project.contains("Sources") else {
            throw APIProblem(details: "project.yml must declare the GeneratedApp app target and Sources directory.")
        }
        if let onProgress { await onProgress("Reading GitHub branch head") }
        let ref = try await request("/git/ref/heads/" + branch)
        guard let object = ref["object"] as? [String: Any], let head = object["sha"] as? String else {
            throw APIProblem(details: "Failed to obtain current Git branch SHA.")
        }
        let commit = try await request("/git/commits/" + head)
        guard let treeObject = commit["tree"] as? [String: Any], let baseTree = treeObject["sha"] as? String else {
            throw APIProblem(details: "Failed to obtain current tree SHA.")
        }
        let entries: [[String: Any]] = files.map { file in
            ["path": "NextIPAFactory/generated-apps/" + slug + "/" + file.path,
             "mode": "100644", "type": "blob", "content": file.content]
        }
        if let onProgress { await onProgress("Uploading approved source to GitHub") }
        let tree = try await request("/git/trees", method: "POST", body: [
            "base_tree": baseTree,
            "tree": entries
        ])
        guard let treeSHA = tree["sha"] as? String else { throw APIProblem(details: "Git tree creation failed") }
        if let onProgress { await onProgress("Creating GitHub source commit") }
        let newCommit = try await request("/git/commits", method: "POST", body: [
            "message": "Next IPA Factory: generate " + slug + " from approved iPhone source",
            "tree": treeSHA,
            "parents": [head]
        ])
        guard let newSHA = newCommit["sha"] as? String else { throw APIProblem(details: "Git commit creation failed") }
        if let onProgress { await onProgress("Publishing commit to development branch") }
        _ = try await request("/git/refs/heads/" + branch, method: "PATCH", body: [
            "sha": newSHA, "force": false
        ])
        return newSHA
    }
}
@MainActor final class FactoryCodeDelivery: ObservableObject {
    @Published var slug = "my-app"
    @Published var command = ""
    @Published var proposed: [FactoryGeneratedFile] = []
    @Published var running = false
    @Published var message = "Generate a native Xcode project using your Integrator agent."
    @Published var lastSession = ""
    @Published var activity: [FactoryGenerationEvent] = []
    @Published var startedAt: Date?
    @Published var liveState = "Ready"
    private func report(_ text: String) {
        liveState = text
        if activity.last?.detail != text {
            activity.append(FactoryGenerationEvent(detail: text))
            if activity.count > 30 { activity.removeFirst(activity.count - 30) }
        }
    }
    func generate(using factory: LocalFactoryState) async {
        let id = factory.agentIDs["Integrator"] ?? ""
        guard !id.isEmpty else { message = "Set the Integrator agent ID in Settings first."; return }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { message = "Describe the app you want to create."; return }
        running = true
        activity = []
        startedAt = Date()
        report("Preparing generation request")
        defer { running = false }
        let spec = """
        Create a COMPLETE, MINIMAL, COMPILABLE iPhone SwiftUI XcodeGen project for this request:
        \(command)
        Target iOS 16.0. The full reply must be exactly ONE JSON object, with this shape:
        {"files":[{"path":"project.yml","content":"..."},{"path":"Sources/GeneratedApp.swift","content":"..."}]}
        project.yml MUST use name: GeneratedApp, target GeneratedApp, type application, platform iOS, sources path Sources.
        Swift file must contain @main struct GeneratedAppApp: App. No omitted sections, TODOs, markdown, external assets, or fake verifications.
        Include actual working implementation, not descriptions. iOS 16 SwiftUI, all required imports.
        Never invent an Xcode build result.
        """
        do {
            report("Connecting to Integrator agent")
            let fullText = try await factory.gateway.runAgentWithProgress(agentID: id, task: spec, onStarted: { [weak self] session in
                self?.lastSession = session
                self?.report("Agent session created")
                self?.message = "Live agent session: " + session
            }, onStatus: { [weak self] status in
                self?.report("OpenAI session: " + status)
            })
            report("Receiving generated source")
            let cleaned = Self.extractJSON(fullText)
            guard let data = cleaned.data(using: .utf8) else { throw APIProblem(details: "Agent output is not UTF-8.") }
            report("Parsing Xcode project files")
            let payload = try JSONDecoder().decode(FactoryGeneratedManifest.self, from: data)
            guard !payload.files.isEmpty else { throw APIProblem(details: "Agent returned an empty project.") }
            proposed = payload.files
            report("Source ready for review: " + String(payload.files.count) + " files")
            message = "Generated " + String(payload.files.count) + " files. Inspect the filenames before approving a GitHub commit."
        } catch {
            proposed = []
            report("Generation failed")
            message = "Generation failed: " + error.localizedDescription + ". You can inspect session " + lastSession
        }
    }
    private static func extractJSON(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end {
            return String(trimmed[start...end])
        }
        return trimmed
    }
    func publish(using factory: LocalFactoryState) async {
        running = true
        startedAt = Date()
        report("Starting GitHub publication")
        defer { running = false }
        do {
            let writer = FactoryGitWriter(token: factory.githubToken, repo: factory.repo, branch: factory.branch)
            let commit = try await writer.publish(slug: slug, files: proposed, onProgress: { [weak self] step in
                self?.report(step)
            })
            report("Source published successfully: " + String(commit.prefix(10)))
            message = "Committed source: " + String(commit.prefix(10)) + ". GitHub Actions will compile the generated project. Build success is not yet verified."
        } catch {
            report("GitHub publication failed")
            message = "GitHub publication failed: " + error.localizedDescription
        }
    }
}
struct FactoryCodeDeliveryView: View {
    @EnvironmentObject var factory: LocalFactoryState
    @StateObject private var delivery = FactoryCodeDelivery()
    @State private var approve = false
    @State private var inspectFile: FactoryGeneratedFile?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Generate an Xcode app", systemImage: "wand.and.stars").font(.headline)
                            Text("The Integrator agent creates project files in an OpenAI-managed session. You approve before GitHub receives any writes.")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("App identifier (e.g. daily-notes)", text: $delivery.slug)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            TextEditor(text: $delivery.command)
                                .frame(minHeight: 130).padding(5)
                                .scrollContentBackground(.hidden)
                                .background(Color.indigo.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                            Button {
                                Task { await delivery.generate(using: factory) }
                            } label: {
                                Label(delivery.running ? "Generating…" : "Generate complete source", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent).tint(.indigo)
                                .disabled(delivery.running)
                        }
                    }
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Label("Live activity", systemImage: "waveform.path").font(.headline)
                                Spacer()
                                if delivery.running { ProgressView().controlSize(.small) }
                            }
                            Text(delivery.liveState).font(.subheadline.weight(.medium))
                            if delivery.running, let began = delivery.startedAt {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text("Elapsed: " + String(Int(context.date.timeIntervalSince(began))) + "s")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            ForEach(delivery.activity.suffix(8).reversed()) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(Color.indigo.opacity(0.8)).frame(width: 6, height: 6).padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.detail).font(.caption)
                                        Text(item.time.formatted(date: .omitted, time: .standard))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            Divider()
                            Text(delivery.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    if !delivery.proposed.isEmpty {
                        FactoryCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Source review", systemImage: "doc.text.magnifyingglass").font(.headline)
                                Text("All source files remain on the phone until you explicitly approve publishing.")
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(delivery.proposed) { file in
                                    Button { inspectFile = file } label: {
                                        HStack {
                                            Image(systemName: "doc.text")
                                            Text(file.path).lineLimit(1)
                                            Spacer()
                                            Text(String(file.content.utf8.count) + " B").foregroundStyle(.secondary)
                                        }.font(.caption)
                                    }.buttonStyle(.plain)
                                    Divider()
                                }
                                Button {
                                    approve = true
                                } label: {
                                    Label("Review & approve GitHub commit", systemImage: "checkmark.shield")
                                        .frame(maxWidth: .infinity)
                                }.buttonStyle(.borderedProminent).tint(.indigo).disabled(delivery.running)
                            }
                        }
                    }
                }.padding(16)
            }
            .navigationTitle("Generate")
            .background(Color(red: 0.962, green: 0.967, blue: 0.988))
            .confirmationDialog("Publish generated Xcode source?", isPresented: $approve, titleVisibility: .visible) {
                Button("Publish to isolated GitHub branch") {
                    Task { await delivery.publish(using: factory) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Commit only to NextIPAFactory/generated-apps/" + delivery.slug + " on branch " + factory.branch + ". This may trigger GitHub macOS builds and usage charges.")
            }
            .sheet(item: $inspectFile) { file in
                NavigationStack {
                    ScrollView {
                        Text(file.content).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .padding().frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle(file.path)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: file.content) { Image(systemName: "square.and.arrow.up") }
                    }}
                }
            }
        }
    }
}
