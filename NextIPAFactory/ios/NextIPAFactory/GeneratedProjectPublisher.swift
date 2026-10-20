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
    func publish(slug: String, files: [FactoryGeneratedFile]) async throws -> String {
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
        let tree = try await request("/git/trees", method: "POST", body: [
            "base_tree": baseTree,
            "tree": entries
        ])
        guard let treeSHA = tree["sha"] as? String else { throw APIProblem(details: "Git tree creation failed") }
        let newCommit = try await request("/git/commits", method: "POST", body: [
            "message": "Next IPA Factory: generate " + slug + " from approved iPhone source",
            "tree": treeSHA,
            "parents": [head]
        ])
        guard let newSHA = newCommit["sha"] as? String else { throw APIProblem(details: "Git commit creation failed") }
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
    func generate(using factory: LocalFactoryState) async {
        let id = factory.agentIDs["Integrator"] ?? ""
        guard !id.isEmpty else { message = "Set the Integrator agent ID in Settings first."; return }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { message = "Describe the app you want to create."; return }
        running = true
        defer { running = false }
        let spec = """
        Create a COMPLETE, MINIMAL, COMPILABLE iPhone SwiftUI XcodeGen project for this request:
        \(command)
        Target iOS 16.0. The full reply must be exactly ONE JSON object, with this shape:
        {"files":[{"path":"project.yml","content":"..."},{"path":"Sources/GeneratedApp.swift","content":"..."},{"path":"Sources/AppIconSpec.json","content":"..."}]}
        project.yml MUST use name: GeneratedApp, target GeneratedApp, type application, platform iOS, sources path Sources.
        Swift file must contain @main struct GeneratedAppApp: App. No omitted sections, TODOs, markdown, external assets, or fake verifications.
        Always include Sources/AppIconSpec.json. Its content must be valid JSON with string keys background, highlight, foreground (6-digit #RRGGBB colors) and glyph (1–2 characters).
        Example AppIconSpec.json file content: {"background":"#343FCB","highlight":"#17B6DE","foreground":"#FFFFFF","glyph":"N"}
        The GitHub compiler converts that JSON into a real 1024x1024 iPhone icon and includes it in Assets.xcassets. Do not reference missing PNGs or produce binary/base64 image assets.
        Include actual working implementation, not descriptions. iOS 16 SwiftUI, all required imports.
        Never invent an Xcode build result.
        """
        do {
            let fullText = try await factory.gateway.runAgent(agentID: id, task: spec) { [weak self] session in
                self?.lastSession = session
                self?.message = "OpenAI agent running in hosted environment, session " + session
            }
            let cleaned = Self.extractJSON(fullText)
            guard let data = cleaned.data(using: .utf8) else { throw APIProblem(details: "Agent output is not UTF-8.") }
            let payload = try JSONDecoder().decode(FactoryGeneratedManifest.self, from: data)
            guard !payload.files.isEmpty else { throw APIProblem(details: "Agent returned an empty project.") }
            proposed = payload.files
            message = "Generated " + String(payload.files.count) + " files. Inspect the filenames before approving a GitHub commit."
        } catch {
            proposed = []
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
        defer { running = false }
        do {
            let writer = FactoryGitWriter(token: factory.githubToken, repo: factory.repo, branch: factory.branch)
            let commit = try await writer.publish(slug: slug, files: proposed)
            message = "Committed source: " + String(commit.prefix(10)) + ". GitHub Actions will compile the generated project. Build success is not yet verified."
        } catch {
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
                        VStack(alignment: .leading, spacing: 9) {
                            Label("Generation status", systemImage: "text.bubble").font(.headline)
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
