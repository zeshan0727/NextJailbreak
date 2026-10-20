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
    @Published var engineeredPrompt = ""
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
    func generate(using factory: LocalFactoryState, reuseEditedPrompt: Bool = false) async {
        let integratorID = factory.agentIDs["Integrator"] ?? ""
        let engineerID = factory.agentIDs["Prompt Engineer"] ?? ""
        guard !integratorID.isEmpty else {
            message = "Add the Integrator agent ID in Settings first."
            return
        }
        guard reuseEditedPrompt || !engineerID.isEmpty else {
            message = "Add the Prompt Engineer agent ID in Settings first."
            return
        }
        let request = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            message = "Describe the app you want to create, in your own words."
            return
        }
        guard !reuseEditedPrompt || !engineeredPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "There is no prepared prompt to use."
            return
        }

        running = true
        proposed = []
        activity = []
        startedAt = Date()
        lastSession = ""
        report("Starting app development")
        defer { running = false }

        do {
            if !reuseEditedPrompt {
                engineeredPrompt = ""
                let brief = """
                You are the Next IPA Factory Prompt Engineer. Expand the user's brief into
                a precise, implementation-ready iOS app specification for another coding agent.
                Do not return source code, JSON, Markdown fences, or claims of compilation.
                Preserve every user-requested behavior and restriction. Do not add unrelated
                functionality, require payments, backend services, or privileged capabilities.
                Do not require a custom app icon or new assets unless the user requests them.
                If a detail is unspecified, choose an ordinary iOS default rather than inventing
                major features. Target iOS 16 and native SwiftUI unless the user says otherwise.
                Provide: app purpose, screens, controls/actions, data model/persistence,
                user flows, error cases, constraints, and specific acceptance tests.
                Explicitly distinguish required features from reasonable defaults.
                The prompt is handed straight to an implementation agent after this step.

                ORIGINAL USER IDEA:
                \(request)
                """
                report("Agent 1 • Prompt Engineer: expanding your idea")
                message = "Preparing a development specification from your instructions."
                let refined = try await factory.gateway.runAgentWithProgress(
                    agentID: engineerID,
                    task: brief,
                    onStarted: { [weak self] session in
                        self?.lastSession = session
                        self?.report("Prompt Engineer session created")
                    },
                    onStatus: { [weak self] status in
                        self?.report("Prompt Engineer: " + status)
                    }
                )
                guard !refined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw APIProblem(details: "Prompt Engineer returned an empty specification.")
                }
                engineeredPrompt = refined
                report("Detailed prompt prepared; handing it to Agent 6")
            } else {
                report("Using your edited development prompt")
            }

            let spec = """
            Develop this complete, working iPhone app from the original idea and
            the detailed requirements written by the Prompt Engineer.

            ORIGINAL USER IDEA (must not be contradicted):
            \(request)

            DETAILED DEVELOPMENT PROMPT:
            \(String(engineeredPrompt.prefix(24000)))

            Return exactly ONE valid JSON object of files, no commentary or code fences:
            {"files":[{"path":"project.yml","content":"..."},{"path":"Sources/GeneratedApp.swift","content":"..."}]}
            project.yml MUST use name: GeneratedApp; target: GeneratedApp;
            type: application; platform: iOS; sources path: Sources.
            Target iOS 16.0 or the user's requested compatible target.
            Include exactly one @main struct GeneratedAppApp: App.
            Implement requested controls, behavior, and persistence, with all imports.
            No TODO placeholders, invented dependencies, or fabricated test results.
            Only include app assets/icons when the user's requirements ask for them
            and the source publishing/build pipeline supports the needed file format.
            """
            report("Agent 6 • Integrator: generating complete SwiftUI source")
            message = "The detailed prompt is ready. Generating the Xcode project now."
            let fullText = try await factory.gateway.runAgentWithProgress(
                agentID: integratorID,
                task: spec,
                onStarted: { [weak self] session in
                    self?.lastSession = session
                    self?.report("Integrator session created")
                },
                onStatus: { [weak self] status in
                    self?.report("Integrator: " + status)
                }
            )
            report("Receiving and validating generated project")
            let cleaned = Self.extractJSON(fullText)
            guard let data = cleaned.data(using: .utf8) else {
                throw APIProblem(details: "Integrator output is not UTF-8.")
            }
            let payload = try JSONDecoder().decode(FactoryGeneratedManifest.self, from: data)
            guard !payload.files.isEmpty else {
                throw APIProblem(details: "Integrator returned an empty project.")
            }
            proposed = payload.files
            report("Ready for review: " + String(payload.files.count) + " source files")
            message = "Agent 1 prepared the prompt; Agent 6 generated " +
                String(payload.files.count) + " source files. Review and approve GitHub publishing."
        } catch {
            proposed = []
            report("Development stopped: " + error.localizedDescription)
            message = "Generation failed: " + error.localizedDescription +
                (lastSession.isEmpty ? "" : ". Session: " + lastSession)
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
                            Text("Describe an app in plain language. Agent 1 writes the detailed prompt, then Agent 6 builds the source automatically. You approve GitHub publishing.")
                                
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("App identifier (e.g. my-calculator)", text: $delivery.slug)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Text("Your app idea").font(.subheadline.weight(.semibold))
                            TextEditor(text: $delivery.command)
                                .frame(minHeight: 130).padding(5)
                                .scrollContentBackground(.hidden)
                                .background(Color.indigo.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                            Button {
                                Task { await delivery.generate(using: factory) }
                            } label: {
                                Label(delivery.running ? "Developing app…" : "Create app from my idea", systemImage: "sparkles")
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
                    if !delivery.engineeredPrompt.isEmpty {
                        FactoryCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Prompt Engineer's development prompt", systemImage: "text.book.closed")
                                    .font(.headline)
                                Text("Automatically sent to the Integrator. You can edit and regenerate if needed.")
                                    .font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: $delivery.engineeredPrompt)
                                    .font(.system(.footnote, design: .monospaced))
                                    .frame(minHeight: 180, maxHeight: 260)
                                    .scrollContentBackground(.hidden)
                                    .padding(5)
                                    .background(Color.indigo.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                Button {
                                    Task { await delivery.generate(using: factory, reuseEditedPrompt: true) }
                                } label: {
                                    Label("Regenerate using edited prompt", systemImage: "arrow.clockwise")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(delivery.running)
                            }
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
