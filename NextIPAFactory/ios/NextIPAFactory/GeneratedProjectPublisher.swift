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
    @Published var agentProgress: [FactoryAgentProgress] = FactoryRoles.all.map {
        FactoryAgentProgress(role: $0.name, duty: $0.purpose)
    }
    @Published var reviewSummary = ""
    @Published var approvedByTeam = false
    @Published var activity: [FactoryGenerationEvent] = []
    @Published var startedAt: Date?
    @Published var liveState = "Ready"
    func report(_ text: String) {
        liveState = text
        if activity.last?.detail != text {
            activity.append(FactoryGenerationEvent(detail: text))
            if activity.count > 30 { activity.removeFirst(activity.count - 30) }
        }
    }
    func generate(using factory: LocalFactoryState, reuseEditedPrompt: Bool = false) async {
        await runTeamPipeline(using: factory, reuseEditedPrompt: reuseEditedPrompt)
    }
    static func extractJSON(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end {
            return String(trimmed[start...end])
        }
        return trimmed
    }
    func publish(using factory: LocalFactoryState) async {
        guard approvedByTeam, !proposed.isEmpty else {
            message = "Publish blocked: QA and Release Reviewer have not approved this source."
            report("Source publication blocked by missing review approval")
            return
        }
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
                            Text("Describe your idea once. All eight saved agents coordinate development, source QA and release review; you approve the final GitHub commit.")
                                
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
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("8-agent team status", systemImage: "person.3.sequence.fill")
                                    .font(.headline)
                                Spacer()
                                Text(String(delivery.agentProgress.filter { $0.state == "Completed" || $0.state == "Reused" }.count) + "/8")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text("Each row reflects an actual saved-agent session. Development roles 2–5 run in parallel.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(delivery.agentProgress) { item in
                                Divider()
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: item.state == "Completed" || item.state == "Reused" ?
                                          "checkmark.circle.fill" :
                                          item.state == "Failed" || item.state == "Interrupted" ?
                                          "xmark.circle.fill" :
                                          item.state == "Working" ? "arrow.triangle.2.circlepath.circle" :
                                          "circle.dotted")
                                        .foregroundStyle(item.state == "Completed" || item.state == "Reused" ?
                                                         Color.green :
                                                         item.state == "Failed" || item.state == "Interrupted" ?
                                                         Color.red :
                                                         item.state == "Working" ? Color.indigo : Color.gray)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(item.role).font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(item.state).font(.caption2.weight(.medium))
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(item.duty).font(.caption2).foregroundStyle(.secondary)
                                            .lineLimit(2)
                                        Text(item.detail).font(.caption2).foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                }
                            }
                            if !delivery.reviewSummary.isEmpty {
                                Divider()
                                Text("Independent source reviews").font(.subheadline.weight(.medium))
                                Text(delivery.reviewSummary).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                    if !delivery.engineeredPrompt.isEmpty {
                        FactoryCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Prompt Engineer's development prompt", systemImage: "text.book.closed")
                                    .font(.headline)
                                Text("Used as the acceptance specification for all seven remaining agents. You can edit and rerun the team.")
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
                                    Label("Re-run all agents with edited prompt", systemImage: "arrow.clockwise")
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
                                }.buttonStyle(.borderedProminent).tint(.indigo)
                                    .disabled(delivery.running || !delivery.approvedByTeam)
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
