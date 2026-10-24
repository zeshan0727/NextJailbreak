import Foundation
import SwiftUI
import UserNotifications

/// Non-secret build context survives an AppForge relaunch.
private struct SavedForgeSession: Codable {
    let project: ForgeProject?
    let codePrompt: String
    let owner: String
    let repo: String
    let branch: String
    let commitSHA: String
    let repairs: Int
    let repairStatus: String
    let origin: AppBuildOrigin?
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: ForgeTab = .requirement
    @Published var moreSection: ForgeMoreSection = .myApps
    @Published var requirement = ""
    @Published var generatedPrompt = ""
    @Published var codePrompt = "" { didSet { persistBuildSession() } }
    @Published var project: ForgeProject? { didSet { persistBuildSession() } }
    @Published var history: [HistoryItem] = []
    @Published var preferences = ForgePreferences() { didSet { persistPreferences() } }
    @Published var busyPrompt = false
    @Published var busyCode = false
    @Published var busyPush = false
    @Published var busyTest = false
    @Published var busyFix = false
    @Published var supportMessages: [SupportMessage] = []
    @Published var supportBusy = false
    @Published var notice: String?
    @Published var repositories: [GitHubRepo] = []
    @Published var chosenRepo = "" { didSet { persistBuildSession() } }
    @Published private(set) var chosenBranch = "" { didSet { persistBuildSession() } }
    @Published var commitMessage = "Build with AppForge"
    @Published var lastCommitSHA = "" { didSet { persistBuildSession() } }
    @Published var lastOwner = "" { didSet { persistBuildSession() } }
    @Published var lastRepo = "" { didSet { persistBuildSession() } }
    @Published var activeRun: GitHubRun?
    @Published var jobs: [GitHubJob] = []
    @Published var failureLog = ""
    @Published var importedCrash: CrashSummary?
    var canRepairImportedCrash: Bool {
        guard let crash = importedCrash, let project = project else { return false }
        return crash.bundleID.isEmpty ||
            crash.bundleID.caseInsensitiveCompare(project.bundleId) == .orderedSame
    }
    @Published var successfulApps: [GitHubRun] = []
    @Published var appsLoading = false
    @Published var appsError: String?
    @Published var loadingSelectedApp = false
    @Published var selectedOrigin: AppBuildOrigin? { didSet { persistBuildSession() } }
    @Published var referenceBuildLog = ""
    @Published var userDiagnosticLog = ""
    @Published var releases: [GitHubRelease] = []
    @Published var downloadsOwner = ""
    @Published var downloadsRepo = ""
    @Published var downloadsRefreshing = false
    @Published var downloadsError: String?
    @Published var downloadsCheckedAt: Date?
    @Published var latestProjectRelease: GitHubRelease?
    @Published var currentBuildRelease: GitHubRelease?

    @Published var refreshing = false
    @Published var autoRepairEnabled = UserDefaults.standard.object(forKey: "forgeAutoRepair") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoRepairEnabled, forKey: "forgeAutoRepair") }
    }
    @Published var repairAttempt = 0 { didSet { persistBuildSession() } }
    @Published var repairStatus = "" { didSet { persistBuildSession() } }
    // Staged, bounded repairs: deterministic preflight then precise edit then regen.
    // Stop when the model cannot materially change source.
    let maximumRepairAttempts = 5
    @Published var exportURL: URL?
    let downloads = DownloadManager()
    private var missingRunChecks = 0
    private var fallbackDispatched = false
    private var notificationDeliveredFor = 0
    private var handledFailureRun: Int?
    private var restoringBuildSession = true
    private var queuedRepair = false

    init() {
        if let data = UserDefaults.standard.data(forKey: "forgePrefs"),
           let value = try? JSONDecoder().decode(ForgePreferences.self, from: data) {
            preferences = value
        }
        if let data = UserDefaults.standard.data(forKey: "forgeHistory"),
           let records = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            history = records
        }
        chosenRepo = preferences.defaultRepo
        if let data = UserDefaults.standard.data(forKey: "forgeBuildSession"),
           let session = try? JSONDecoder().decode(SavedForgeSession.self, from: data) {
            project = session.project
            codePrompt = session.codePrompt
            chosenRepo = session.repo.isEmpty ? preferences.defaultRepo : session.repo
            // Old arbitrary branch selections must not be trusted after upgrading.
            chosenBranch = session.branch.hasPrefix("appforge/") ? session.branch : ""
            lastOwner = session.owner
            lastRepo = session.repo
            lastCommitSHA = session.commitSHA
            repairAttempt = session.repairs
            repairStatus = session.repairStatus
            selectedOrigin = session.origin
        }

        downloadsOwner = lastOwner.isEmpty ? preferences.githubUsername : lastOwner
        downloadsRepo = lastRepo.isEmpty ? (chosenRepo.isEmpty ? preferences.defaultRepo : chosenRepo) : lastRepo
        restoringBuildSession = false
    }

    private func persistBuildSession() {
        guard !restoringBuildSession else { return }
        let session = SavedForgeSession(project: project, codePrompt: codePrompt, owner: lastOwner,
            repo: lastRepo.isEmpty ? chosenRepo : lastRepo, branch: chosenBranch,
            commitSHA: lastCommitSHA, repairs: repairAttempt, repairStatus: repairStatus,
            origin: selectedOrigin)
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: "forgeBuildSession")
        }
    }

    private func persistPreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: "forgePrefs")
    }
    private func saveHistory() {
        history = Array(history.prefix(30))
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "forgeHistory")
        }
    }
    func saveSecrets(ai: String, github: String) {
        do {
            try Keychain.write(ai, for: "ai")
            try Keychain.write(github, for: "github")
            notice = "Credentials saved securely in Keychain"
        } catch { notice = error.localizedDescription }
    }
    private func ai() -> AIClient {
        AIClient(endpoint: preferences.aiBaseURL, model: preferences.aiModel, token: Keychain.read("ai"))
    }
    /// A stronger reasoning model for targeted compiler fixes; keep generation economical.
    private func repairAI() -> AIClient {
        let model = preferences.aiBaseURL.contains("api.openai.com")
            ? (UserDefaults.standard.string(forKey: "forgeRepairModel") ?? "gpt-6.1-sol")
            : preferences.aiModel
        return AIClient(endpoint: preferences.aiBaseURL, model: model, token: Keychain.read("ai"))
    }

    private func github() -> GitHubClient { GitHubClient(token: Keychain.read("github")) }

    func generatePrompt() async {
        guard !requirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notice = "Enter your app requirement first"; return
        }
        busyPrompt = true; defer { busyPrompt = false }
        do {
            let result = try await ai().chat(system: AIClient.promptSystem, user: requirement)
            generatedPrompt = result
            history.insert(HistoryItem(requirement: requirement, prompt: result), at: 0)
            saveHistory()
        } catch { notice = error.localizedDescription }
    }

    private func getProject(system: String, request: String, repair: Bool = false) async throws -> ForgeProject {
        // Three bounded attempts: initial JSON, format repair, then compact regeneration.
        // Never treat an API rate-limit/network error as malformed JSON.
        var previous = ""
        var previousError = ""
        for attempt in 0..<3 {
            let instruction: String
            switch attempt {
            case 0:
                instruction = request
            case 1:
                instruction = """
                Repair the following INVALID JSON answer. Output one complete JSON object ONLY.
                Keep the original app features; use JSON string escaping for Swift backslashes and quotes.
                Required fields: appName, bundleId, files:[{path,content}].
                Limit to 1-4 complete Swift files, no markdown or extra text.
                Original requirements:
                \(String(request.prefix(12_000)))
                Parsing error: \(previousError)
                Previous malformed output (beginning):
                \(String(previous.prefix(7_000)))
                """
            default:
                instruction = """
                Regenerate this app using compact, valid JSON. Previous responses had broken JSON.
                Minimize comments and whitespace in Swift source, but retain core features.
                Return 1-3 complete iOS 16 Swift files as JSON, with escaped string contents.
                No markdown, no partial files, no surrounding prose.
                Requirements:
                \(String(request.prefix(10_000)))
                Last parsing issue: \(previousError)
                """
            }
            let answer = try await (repair ? repairAI() : ai()).chat(system: system, user: instruction, jsonMode: true)
            do {
                return try ProjectFactory.parseModelJSON(answer)
            } catch {
                previous = answer
                previousError = error.localizedDescription
                repairStatus = "AI returned malformed JSON. Retrying generation (\(attempt + 1)/3)…"
            }
        }
        throw ForgeError.message("Automatic JSON recovery could not produce valid source after 3 attempts. Try a shorter requirement or a model with a larger response limit. Last error: \(previousError)")
    }

    func generateCode() async {
        guard !codePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notice = "Enter or send a generation prompt"; return
        }
        busyCode = true; defer { busyCode = false }
        do {
            let generated = try await getProject(system: AIClient.codeSystem, request: codePrompt)
            project = try ProjectFactory.scaffold(generated, minIOS: preferences.minimumIOS)
            // A new code generation is a NEW project, even if the app name repeats.
            // Do not reuse or change an older app's GitHub branch.
            chosenBranch = ""
            lastCommitSHA = ""
            lastOwner = ""
            lastRepo = ""
            activeRun = nil
            jobs = []
            failureLog = ""
            selectedOrigin = nil
            referenceBuildLog = ""
            userDiagnosticLog = ""
            supportMessages = []
            repairAttempt = 0
            repairStatus = "New project ready. GitHub will create its own protected appforge/ branch."
        } catch { notice = error.localizedDescription }
    }

    func sendPromptToCode() { codePrompt = generatedPrompt; selectedTab = .code }
    func sendProjectToGitHub() { selectedTab = .github }
    func exportZip() {
        guard let project else { notice = "Generate code first"; return }
        do { exportURL = try ZIPWriter.export(project) }
        catch { notice = error.localizedDescription }
    }

    func testAI() async {
        busyTest = true; defer { busyTest = false }
        do {
            _ = try await ai().chat(system: "Reply with exactly OK", user: "Test connection")
            notice = "AI connection successful"
        } catch { notice = error.localizedDescription }
    }
    func testGitHub() async {
        busyTest = true; defer { busyTest = false }
        do { notice = "GitHub connected as @\(try await github().testToken())" }
        catch { notice = error.localizedDescription }
    }

    func refreshRepos() async {
        do {
            repositories = try await github().repositories()
            if chosenRepo.isEmpty, let first = repositories.first { chosenRepo = first.name }
        } catch { notice = error.localizedDescription }
    }
    func createRepo(name: String, isPrivate: Bool) async {
        do {
            let new = try await github().createRepo(name: name, isPrivate: isPrivate)
            preferences.githubUsername = new.full_name.split(separator: "/").first.map(String.init) ?? preferences.githubUsername
            await refreshRepos()
            chosenRepo = new.name
            // Repository creation must never select its default branch for pushes.
            chosenBranch = ""
            lastCommitSHA = ""
            lastRepo = ""
            lastOwner = ""
            notice = "Created repository \(new.full_name)"
        } catch { notice = error.localizedDescription }
    }

    func pushAndBuild(resetRepairCycle: Bool = true) async {
        if resetRepairCycle { repairAttempt = 0; repairStatus = ""; handledFailureRun = nil; queuedRepair = false }
        guard let project else { notice = "No generated project available"; return }
        let owner = preferences.githubUsername.trimmingCharacters(in: .whitespaces)
        let repo = chosenRepo.trimmingCharacters(in: .whitespaces)
        guard !owner.isEmpty, !repo.isEmpty else { notice = "Choose a repo and set your GitHub username"; return }
        busyPush = true; defer { busyPush = false }
        do {
            let client = github()
            let source = try await client.defaultBranch(owner: owner, repo: repo)
            let reusingOwnedBranch = chosenBranch.hasPrefix("appforge/")
                && !lastCommitSHA.isEmpty
                && lastOwner.caseInsensitiveCompare(owner) == .orderedSame
                && lastRepo.caseInsensitiveCompare(repo) == .orderedSame
            let slug = String(project.appName.lowercased()
                .map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
                .prefix(36))
            let uuid = String(UUID().uuidString.replacingOccurrences(of: "-", with: "")
                .lowercased().prefix(12))
            let destination = reusingOwnedBranch ? chosenBranch : "appforge/\(slug)-\(uuid)"
            let sha = try await client.push(project: project, owner: owner, repo: repo,
                branch: destination, message: commitMessage, sourceBranch: source,
                expectedHeadSHA: reusingOwnedBranch ? lastCommitSHA : nil)
            chosenBranch = destination
            lastCommitSHA = sha; lastOwner = owner; lastRepo = repo
            downloadsOwner = owner; downloadsRepo = repo
            currentBuildRelease = nil; latestProjectRelease = nil; releases = []
            downloadsCheckedAt = nil; downloadsError = nil
            activeRun = nil; jobs = []; failureLog = ""
            missingRunChecks = 0; fallbackDispatched = false
            if repairAttempt > 0 { repairStatus = "Repair \(repairAttempt)/\(maximumRepairAttempts) submitted. Checking new build…" }
            selectedTab = .status
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        } catch {
            notice = error.localizedDescription
            if !resetRepairCycle { repairStatus = "Automatic repair push failed: \(error.localizedDescription)" }
        }
    }

    func refreshBuild() async {
        guard !lastCommitSHA.isEmpty, !lastRepo.isEmpty, !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        do {
            let client = github()
            if let found = try await client.latestRun(owner: lastOwner, repo: lastRepo, sha: lastCommitSHA) {
                activeRun = found
                jobs = try await client.jobs(owner: lastOwner, repo: lastRepo, run: found.id)
                if found.status == "completed" {
                    if found.conclusion == "success" {
                        repairStatus = repairAttempt > 0 ? "Build succeeded after \(repairAttempt) AI repair(s)." : "Build succeeded."
                        if notificationDeliveredFor != found.id {
                            notificationDeliveredFor = found.id
                            let content = UNMutableNotificationContent()
                            content.title = "AppForge build succeeded"
                            content.body = "Your IPA is available in Downloads."
                            content.sound = .default
                            let request = UNNotificationRequest(identifier: "forge-\(found.id)", content: content, trigger: nil)
                            try? await UNUserNotificationCenter.current().add(request)
                            await refreshReleases()
                        }
                    } else if handledFailureRun != found.id {
                        handledFailureRun = found.id
                        if let failed = jobs.first(where: { $0.conclusion == "failure" }) ?? jobs.first {
                            do { failureLog = try await client.jobLog(owner: lastOwner, repo: lastRepo, job: failed.id) }
                            catch { failureLog = "Could not retrieve build logs: \(error.localizedDescription)" }
                        }
                        let didFailAtCompile = jobs.contains { job in
                            (job.steps ?? []).contains { step in
                                step.conclusion == "failure" &&
                                (step.name.contains("Build unsigned app") ||
                                 step.name.contains("Generate project") ||
                                 step.name.contains("Build iOS app"))
                            }
                        }
                        if autoRepairEnabled && didFailAtCompile && repairAttempt < maximumRepairAttempts,
                           project != nil && !failureLog.isEmpty {
                            queuedRepair = true
                            repairStatus = "Build failed. Starting automatic source repair…"
                            Task { await self.fixWithAI(automatically: true) }
                        } else if repairAttempt >= maximumRepairAttempts {
                            repairStatus = "Stopped after \(maximumRepairAttempts) automatic repairs. Review compiler errors."
                        } else if !autoRepairEnabled {
                            repairStatus = "Auto repair disabled. Use Fix with AI below."
                        } else if !didFailAtCompile {
                            repairStatus = "Build failed outside compilation. Review workflow logs; AI source repair not attempted."
                        }
                    }
                }
            } else {
                missingRunChecks += 1
                if missingRunChecks >= 4 && !fallbackDispatched && chosenBranch.hasPrefix("appforge/") {
                    fallbackDispatched = true
                    do { try await client.dispatch(owner: lastOwner, repo: lastRepo, branch: chosenBranch) }
                    catch { notice = "Push completed, but no run found yet. Manual dispatch unavailable: \(error.localizedDescription)" }
                }
            }
        } catch { notice = error.localizedDescription }
    }

    private struct SourcePatch: Decodable {
        let path: String
        let old: String
        let new: String
    }

    /// Repairs one diagnosed source span at a time, preserving all unrelated files.
    /// This keeps the model's response small and avoids repeated truncated-project JSON.
    private func proposeTargetedRepair(project: ForgeProject, failureLog: String) async throws -> ForgeProject {
        let errors = failureLog.split(separator: "\n")
            .filter { $0.contains("error:") || $0.contains("fatal error:") }
        guard let first = errors.first else {
            throw ForgeError.message("No compiler error lines were found in the build log.")
        }
        let line = String(first)
        let expression = #"/Sources/([A-Za-z0-9_./-]+\.swift):([0-9]+):"#
        guard let match = line.range(of: expression, options: .regularExpression) else {
            throw ForgeError.message("Could not locate the failing Swift file from the compiler output.")
        }
        let pathLine = String(line[match])
        let components = pathLine.split(separator: ":")
        guard components.count >= 2, let number = Int(components[1]) else {
            throw ForgeError.message("Could not parse the failing source line.")
        }
        let suffix = String(components[0])
        let path = "Sources/" + String(suffix.split(separator: "/").last ?? "")
        guard let source = project.files.first(where: { $0.path == path }) else {
            throw ForgeError.message("Compiler error file \(path) is not present in the current project.")
        }
        let lines = source.content.components(separatedBy: "\n")
        let start = max(0, number - 45)
        let end = min(lines.count, number + 35)
        let context = lines[start..<end].enumerated().map {
            "\($0.offset + start + 1): \($0.element)"
        }.joined(separator: "\n")
        let reasons = errors.prefix(20).joined(separator: "\n")
        var lastError = ""
        // Two concise attempts with different context; never commit unverified edits.
        for pass in 0..<2 {
            let response = try await repairAI().chat(system: """
                You are a Swift 5 / iOS 16 compiler error fixer.
                Return a SINGLE JSON object with path, old, new STRING properties.
                old must be an exact contiguous substring from the source snippet,
                new is its precise corrected replacement (not the entire file).
                Preserve the app features, types, security, and all unrelated code.
                Do not use TODOs, stubs, or platform APIs unavailable on iOS 16.
                No prose or markdown. JSON only.
                """, user: """
                App: \(project.appName)
                Failing file: \(path), approximate line \(number)
                Compiler diagnostics:
                \(String(reasons.prefix(6500)))
                Relevant source with line numbers:
                \(String(context.prefix(11500)))
                Previous patch problem: \(lastError)
                Attempt \(pass + 1)/2.
                """, jsonMode: true, patchMode: true)
            do {
                let start = response.firstIndex(of: "{")
                let end = response.lastIndex(of: "}")
                guard let start, let end, start <= end else {
                    throw ForgeError.message("AI patch is not a JSON object.")
                }
                let patch = try JSONDecoder().decode(SourcePatch.self,
                                   from: Data(response[start...end].utf8))
                guard patch.path == path || patch.path == String(path.dropFirst("Sources/".count)) else {
                    throw ForgeError.message("AI patch targets the wrong file.")
                }
                guard !patch.old.isEmpty && patch.old != patch.new &&
                      source.content.components(separatedBy: patch.old).count == 2 else {
                    throw ForgeError.message("Patch did not match one unique source span.")
                }
                var modified = project
                guard let idx = modified.files.firstIndex(where: { $0.path == path }) else {
                    throw ForgeError.message("Source file disappeared.")
                }
                let revised = source.content.replacingOccurrences(of: patch.old, with: patch.new)
                guard !revised.contains("@main") || source.content.contains("@main") else {
                    throw ForgeError.message("Patch attempted to insert an @main entrypoint.")
                }
                modified.files[idx].content = revised
                repairStatus = "Applied precise edit to \(path):\(number). Rebuilding to verify…"
                return modified
            } catch {
                lastError = error.localizedDescription
            }
        }
        throw ForgeError.message("Targeted repair could not produce a safe source patch: \(lastError)")
    }

    func fixWithAI(automatically: Bool = false) async {
        guard let project, !failureLog.isEmpty, !busyFix else {
            if !automatically { notice = "No failing build log or generated project available" }
            return
        }
        if automatically && repairAttempt >= maximumRepairAttempts { return }
        busyFix = true
        queuedRepair = false
        if automatically { repairAttempt += 1 }
        repairStatus = automatically ? "Analyzing compiler errors with AI (attempt \(repairAttempt)/\(maximumRepairAttempts))…" : "Requesting an AI code repair…"
        defer { busyFix = false }
        do {
            let swiftFiles = project.files.filter { $0.path.hasSuffix(".swift") && $0.path != "Sources/AppEntry.swift" }
            let source = swiftFiles.map { "PATH: \($0.path)\n\($0.content)" }.joined(separator: "\n\n")
            let compilerLines = failureLog.split(separator: "\n")
                .filter { $0.localizedCaseInsensitiveContains("error:") ||
                          $0.localizedCaseInsensitiveContains("fatal error") ||
                          $0.contains("##[error]") || $0.contains("BUILD FAILED") }
                .suffix(65).joined(separator: "\n")
            let corrected: ForgeProject
            if let local = ProjectFactory.repairKnownCompilerErrors(project, log: failureLog) {
                corrected = local
                repairStatus = "Fixed known SwiftUI alert syntax without an API call."
            } else if repairAttempt <= 3 || !automatically {
                // Prefer editing the exact failing file instead of asking the AI to
                // regenerate an entire application (which often truncates JSON).
                corrected = try await proposeTargetedRepair(project: project, failureLog: failureLog)
            } else {
                corrected = try await getProject(system: AIClient.codeSystem, request: """
            Fix this exact iOS \(preferences.minimumIOS) GitHub Actions compiler failure.
            Keep the original feature set and bundle ID (\(project.bundleId)) unchanged.
            Output ALL complete Swift source files, not a diff, in strict JSON. Use only iOS 16 APIs.
            User specification:
            \(codePrompt)
            ORIGINAL SWIFT FILES:
            \(String(source.prefix(90_000)))
            COMPILER REPAIR REQUIREMENTS:
            If the compiler says "unable to type-check this expression in reasonable time",
            break the whole affected SwiftUI View body into small typed subviews and modifiers.
            Verify that navigation value models conform to Hashable, especially NavigationLink(value:)
            and .navigationDestination(for:). Do NOT return the same source unchanged.
            Preserve the existing app data model/JSON storage schema.
            SPECIFIC COMPILER ERRORS:
            \(String(compilerLines.prefix(12_000)))
            LAST BUILD LOG:
            \(String(failureLog.suffix(12_000)))
            """, repair: true)
            }
            guard corrected.bundleId == project.bundleId else {
                throw ForgeError.message("AI tried to change bundle identifier; repair rejected")
            }
            let rebuilt = try ProjectFactory.scaffold(corrected, minIOS: preferences.minimumIOS)
            let oldSource = project.files.filter { $0.path.hasSuffix(".swift") }.map { $0.path + $0.content }
            let newSource = rebuilt.files.filter { $0.path.hasSuffix(".swift") }.map { $0.path + $0.content }
            guard oldSource != newSource else {
                throw ForgeError.message("AI did not change any Swift source. Automatic retries stopped; use AI Support to describe the error and request a different fix.")
            }
            self.project = rebuilt
            if automatically {
                repairStatus = "AI repaired sources. Pushing corrected files and building again…"
                await pushAndBuild(resetRepairCycle: false)
            } else {
                selectedTab = .code
                repairStatus = "Corrected files loaded into Code. Review and push to build."
            }
        } catch {
            repairStatus = "AI repair unsuccessful: \(error.localizedDescription)"
            notice = repairStatus
        }
    }


    /// Provides contextual, interactive repair help through the user's configured API.
    /// The API receives ONLY selected source snippets, compiler errors and recent chat turns.
    func askSupport(_ message: String) async {
        let input = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty && !supportBusy else { return }
        supportMessages.append(SupportMessage(role: "user", content: input))
        supportBusy = true
        defer { supportBusy = false }
        do {
            if failureLog.isEmpty, !lastCommitSHA.isEmpty, !lastOwner.isEmpty, !lastRepo.isEmpty {
                let client = github()
                if let run = try? await client.latestRun(owner: lastOwner, repo: lastRepo, sha: lastCommitSHA),
                   run.conclusion == "failure",
                   let job = try? await client.jobs(owner: lastOwner, repo: lastRepo, run: run.id),
                   let failing = job.first(where: { $0.conclusion == "failure" }),
                   let text = try? await client.jobLog(owner: lastOwner, repo: lastRepo, job: failing.id) {
                    failureLog = text
                }
            }
            let history = supportMessages.suffix(8).map { "\($0.role): \($0.content)" }
                .joined(separator: "\n\n")
            let swift = project?.files.filter {
                $0.path.hasSuffix(".swift") && $0.path != "Sources/AppEntry.swift"
            }.map { "PATH: \($0.path)\n\($0.content)" }.joined(separator: "\n\n") ?? ""
            let problems = failureLog.split(separator: "\n")
                .filter { $0.localizedCaseInsensitiveContains("error:")
                       || $0.contains("BUILD FAILED")
                       || $0.localizedCaseInsensitiveContains("fatal error") }
                .suffix(35).joined(separator: "\n")
            let diagnosis = try await repairAI().chat(system: """
                You are AppForge's iOS engineer support assistant. Answer the user's issue with
                concrete explanations grounded in the supplied code and GitHub compiler diagnostics.
                Identify the precise Swift file and likely correction, but be explicit when unverified.
                Explain the difference between an Xcode compile, successful IPA build, and running on iPhone.
                The user can click Apply AI Fix & Rebuild IPA to request a fresh code patch.
                Do not claim you have already edited files, pushed code, tested iPhone, or installed an IPA.
                Never ask for GitHub or AI secret tokens.
                """, user: """
                Project: \(project?.appName ?? "No project loaded")
                Bundle: \(project?.bundleId ?? "unknown")
                Branch: \(chosenBranch)
                Errors:
                \(String(problems.prefix(6000)))
                Latest log excerpt:
                \(String(failureLog.suffix(6500)))
                Successful reference build log:
                \(String(referenceBuildLog.suffix(5500)))
                Attached device/runtime diagnostics:
                \(String(userDiagnosticLog.suffix(7000)))
                Source build reference:
                \(selectedOrigin?.successfulCommit ?? "not selected")
                Swift source:
                \(String(swift.prefix(26000)))
                Conversation:
                \(history)
                """)
            supportMessages.append(SupportMessage(role: "assistant", content: diagnosis))
        } catch {
            supportMessages.append(SupportMessage(role: "assistant",
                content: "I could not analyze the issue: \(error.localizedDescription). Check Settings → Test AI connection."))
        }
    }


    /// User-controlled modification to a successful app. The initial passing
    /// commit is immutable; a fresh revision branch is created on the first push.
    func applyAppChange(mode: SupportEditMode) async {
        guard let original = project, !supportBusy, !busyFix, !busyPush,
              let latestInstruction = supportMessages.last(where: { $0.role == "user" })?.content,
              !latestInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notice = "Select an app and describe the requested change in AI Support."
            return
        }
        if mode == .repair, failureLog.contains("error:") {
            await applySupportRepair()
            return
        }
        busyFix = true
        defer { busyFix = false }
        do {
            let revised: ForgeProject
            if mode == .regenerate {
                repairStatus = "Regenerating all Swift source from your requested changes…"
                let files = original.files.filter { $0.path.hasSuffix(".swift")
                    && $0.path != "Sources/AppEntry.swift" }
                    .map { "PATH: \($0.path)\n\($0.content)" }.joined(separator: "\n\n")
                let request = """
                Regenerate this EXISTING \(original.appName) iOS 16 SwiftUI app.
                Keep EXACTLY this name: \(original.appName)
                Keep EXACTLY this bundleId: \(original.bundleId)
                Preserve its existing functions, accessibility, persistence, and security.
                Implement this latest user's request: \(latestInstruction)
                Previous Swift files:
                \(String(files.prefix(75_000)))
                Return all complete Swift source files in the required JSON schema.
                """
                let output = try await getProject(system: AIClient.codeSystem, request: request, repair: true)
                guard output.appName == original.appName, output.bundleId == original.bundleId else {
                    throw ForgeError.message("Regeneration changed app identity; no files were pushed.")
                }
                revised = try ProjectFactory.scaffold(output, minIOS: preferences.minimumIOS)
            } else {
                repairStatus = "Creating a small source patch to \(mode.rawValue.lowercased()) the app…"
                let files = original.files.filter { $0.path.hasSuffix(".swift")
                    && $0.path != "Sources/AppEntry.swift" }
                let source = files.map { "PATH: \($0.path)\n\($0.content)" }
                    .joined(separator: "\n\n")
                let messages = supportMessages.suffix(8)
                    .map { "\($0.role): \($0.content)" }.joined(separator: "\n")
                let response = try await repairAI().chat(system: """
                    You are an expert iOS 16 Swift engineer performing a localized source edit.
                    Respond with a JSON object with exactly path, old, new string keys.
                    path must match the exact Source file path; old is an exact contiguous source
                    substring in that file appearing ONCE; new is replacement code.
                    Preserve all unrelated source, existing features and security.
                    Do not remove features, replace a whole app or insert TODOs.
                    If the change is too large for a local edit, return old="" and new=""
                    so the client can ask the user to choose Regenerate.
                    """, user: """
                    Application: \(original.appName), bundle \(original.bundleId)
                    Requested \(mode.rawValue.lowercased()) action:
                    \(latestInstruction)
                    Conversation:
                    \(String(messages.prefix(9000)))
                    Attached device log:
                    \(String(userDiagnosticLog.suffix(8500)))
                    Successful reference build log:
                    \(String(referenceBuildLog.suffix(2500)))
                    Swift source:
                    \(String(source.prefix(80_000)))
                    """, jsonMode: true, patchMode: true)
                guard let start = response.firstIndex(of: "{"),
                      let end = response.lastIndex(of: "}"), start <= end else {
                    throw ForgeError.message("AI returned an invalid source-patch format.")
                }
                let patch = try JSONDecoder().decode(SourcePatch.self,
                                             from: Data(response[start...end].utf8))
                guard let originalFile = files.first(where: { $0.path == patch.path }),
                      !patch.old.isEmpty, patch.old != patch.new,
                      originalFile.content.components(separatedBy: patch.old).count == 2 else {
                    throw ForgeError.message("AI did not provide one safe matching change. Try a narrower request or choose Regenerate.")
                }
                var copy = original
                guard let position = copy.files.firstIndex(where: { $0.path == patch.path }) else {
                    throw ForgeError.message("Proposed edit does not match any generated file.")
                }
                copy.files[position].content = originalFile.content
                    .replacingOccurrences(of: patch.old, with: patch.new)
                revised = try ProjectFactory.scaffold(
                    ForgeProject(appName: copy.appName, bundleId: copy.bundleId,
                        files: copy.files.filter { $0.path.hasSuffix(".swift")
                            && $0.path != "Sources/AppEntry.swift" }),
                    minIOS: preferences.minimumIOS
                )
            }
            guard revised.appName == original.appName,
                  revised.bundleId == original.bundleId else {
                throw ForgeError.message("App identity mismatch; push was rejected.")
            }
            let oldSwift = original.files.filter { $0.path.hasSuffix(".swift") }
                .map { $0.path + $0.content }
            let newSwift = revised.files.filter { $0.path.hasSuffix(".swift") }
                .map { $0.path + $0.content }
            guard oldSwift != newSwift else {
                throw ForgeError.message("No source changes were generated; nothing was pushed.")
            }
            var finalized = revised
            // Never drop permissions/configuration from the successful baseline.
            if let previousPlist = original.files.first(where: { $0.path == "Info.plist" }),
               let index = finalized.files.firstIndex(where: { $0.path == "Info.plist" }) {
                finalized.files[index].content = previousPlist.content
            }
            project = try CrashDoctor.preflight(finalized)
            repairStatus = "Revised \(original.appName). Building on an isolated app branch…"
            await pushAndBuild()
            guard !lastCommitSHA.isEmpty else {
                throw ForgeError.message("No new GitHub build commit was created.")
            }
            supportMessages.append(SupportMessage(role: "assistant", content:
                "\(mode.rawValue) committed on \(chosenBranch), commit \(String(lastCommitSHA.prefix(12))). Check the Build tab for compiler verification. The original successful IPA is preserved."))
        } catch {
            repairStatus = "\(mode.rawValue) stopped: \(error.localizedDescription)"
            notice = repairStatus
            supportMessages.append(SupportMessage(role: "assistant", content: repairStatus))
        }
    }

    /// User-confirmed source repair. Never blindly commits chat text as executable Swift.
    func applySupportRepair() async {
        guard let original = project, !supportBusy, !busyFix, !busyPush,
              supportMessages.contains(where: { $0.role == "user" }) else {
            notice = "Load the matching generated project and describe its problem in AI Support first."
            return
        }
        busyFix = true
        defer { busyFix = false }
        repairStatus = "Analyzing requested changes against current source…"
        do {
            let repaired: ForgeProject
            if let known = ProjectFactory.repairKnownCompilerErrors(original, log: failureLog) {
                repaired = known
            } else if failureLog.contains("error:") {
                // Compiler errors get an exact-source patch instead of a whole-app rewrite.
                repaired = try await proposeTargetedRepair(project: original, failureLog: failureLog)
            } else {
                let source = original.files.filter {
                    $0.path.hasSuffix(".swift") && $0.path != "Sources/AppEntry.swift"
                }.map { "PATH: \($0.path)\n\($0.content)" }.joined(separator: "\n\n")
                let dialogue = supportMessages.suffix(10)
                    .map { "\($0.role): \($0.content)" }.joined(separator: "\n\n")
                repaired = try await getProject(system: AIClient.codeSystem, request: """
                    You are correcting an EXISTING iOS SwiftUI application, not designing a new one.
                    Keep its exact bundle ID \(original.bundleId), original app name
                    \(original.appName), and existing functionality/data model.
                    Return EVERY updated Swift source file, preserving unchanged Swift files too,
                    under each original path. No TODOs or incomplete output.
                    Original requirements:
                    \(String(codePrompt.prefix(8000)))
                    User support conversation and requested changes:
                    \(String(dialogue.prefix(8500)))
                    Compiler errors:
                    \(String(failureLog.split(separator: "\n").filter { $0.contains("error:") }.suffix(30).joined(separator: "\n").prefix(5500)))
                    Current Swift files:
                    \(String(source.prefix(88000)))
                    """, repair: true)
            }
            guard repaired.bundleId == original.bundleId,
                  repaired.appName == original.appName else {
                throw ForgeError.message("AI changed the app identity; no files were pushed.")
            }
            let rebuilt = try ProjectFactory.scaffold(repaired, minIOS: preferences.minimumIOS)
            let oldSwift = original.files.filter { $0.path.hasSuffix(".swift") }.map { $0.path + $0.content }
            let newSwift = rebuilt.files.filter { $0.path.hasSuffix(".swift") }.map { $0.path + $0.content }
            guard oldSwift != newSwift else {
                throw ForgeError.message("AI returned unchanged Swift code. Nothing was pushed. Describe the desired correction more specifically.")
            }
            project = rebuilt
            repairStatus = "Source updated. Pushing a new build to this app's isolated branch…"
            await pushAndBuild()
            if lastCommitSHA.isEmpty { throw ForgeError.message("No GitHub commit was created.") }
            supportMessages.append(SupportMessage(role: "assistant", content:
                "Correction committed to \(chosenBranch) at \(String(lastCommitSHA.prefix(12))). Open Build for compiler verification. Successful compilation does not guarantee correct on-device behavior."))
        } catch {
            repairStatus = "Support repair stopped: \(error.localizedDescription)"
            notice = repairStatus
            supportMessages.append(SupportMessage(role: "assistant", content: repairStatus))
        }
    }

    func loadCrashReport(_ report: String) {
        do {
            importedCrash = try CrashDoctor.analyze(report)
            repairStatus = importedCrash?.usageKey == nil
                ? "Crash report imported; AI-assisted analysis is available."
                : "Crash report imported. A safe Info.plist correction is available."
        } catch { notice = error.localizedDescription }
    }

    /// Fixes imported device crashes without manual chat assistance. Matching bundles required.
    func repairImportedCrash(build: Bool) async {
        guard let crash = importedCrash, let original = project, canRepairImportedCrash else {
            notice = "Import a crash report and load the matching generated app in Code."
            return
        }
        guard !busyFix && !busyPush else { return }
        busyFix = true
        defer { busyFix = false }
        do {
            if crash.usageKey != nil {
                project = try CrashDoctor.patch(original, for: crash)
                repairStatus = "Added the missing iOS permission to Info.plist."
            } else {
                repairStatus = "Analyzing sanitized crash details and source code with AI…"
                let swift = original.files.filter { $0.path.hasSuffix(".swift") && $0.path != "Sources/AppEntry.swift" }
                    .map { "PATH: \($0.path)\n\($0.content)" }.joined(separator: "\n\n")
                let corrected = try await getProject(system: AIClient.codeSystem, request: """
                    Repair this iOS \(preferences.minimumIOS) runtime crash.
                    Preserve app features and bundle ID \(original.bundleId).
                    Return ALL complete Swift source files in strict JSON.
                    Safe crash summary (identifiers excluded):
                    \(crash.safeReport)
                    SOURCE:
                    \(String(swift.prefix(75_000)))
                    """)
                guard corrected.bundleId.caseInsensitiveCompare(original.bundleId) == .orderedSame else {
                    throw ForgeError.message("AI changed the bundle identifier. Repair was rejected.")
                }
                project = try ProjectFactory.scaffold(corrected, minIOS: preferences.minimumIOS)
                repairStatus = "AI produced corrected code. A build is needed to validate it."
            }
            if build {
                repairStatus += " Pushing and building the corrected IPA…"
                await pushAndBuild()
            } else {
                selectedTab = .code
                repairStatus += " Open GitHub to push the updated code."
            }
        } catch {
            repairStatus = "Crash repair failed: \(error.localizedDescription)"
            notice = repairStatus
        }
    }

    /// Refreshes the selected repository and pins the IPA from the last generated app.
    /// Repo selection is independent of the previous build, avoiding silently stale results.
    /// Find successful generated IPA builds using the verified GitHub Actions run status.
    func refreshSuccessfulApps() async {
        guard !appsLoading else { return }
        let owner = preferences.githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = chosenRepo.isEmpty ? preferences.defaultRepo : chosenRepo
        guard !owner.isEmpty, !repo.isEmpty else {
            appsError = "Set your GitHub username and repository in Settings."
            return
        }
        appsLoading = true
        appsError = nil
        defer { appsLoading = false }
        do {
            successfulApps = try await github().successfulAppBuilds(owner: owner, repo: repo)
            if successfulApps.isEmpty {
                appsError = "No successful AppForge branch builds were found among recent GitHub Actions runs."
            }
        } catch {
            appsError = error.localizedDescription
        }
    }

    /// Restores a frozen, successful commit. All future changes start on a fresh
    /// unique appforge/ branch; this original app and its successful IPA are untouched.
    func loadSuccessfulApp(_ run: GitHubRun) async {
        guard !loadingSelectedApp && !busyPush && !busyFix && !supportBusy,
              run.conclusion == "success",
              let branch = run.head_branch, branch.hasPrefix("appforge/") else {
            appsError = "Choose a successful AppForge build."
            return
        }
        let owner = preferences.githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = chosenRepo.isEmpty ? preferences.defaultRepo : chosenRepo
        loadingSelectedApp = true
        appsError = nil
        defer { loadingSelectedApp = false }
        do {
            let client = github()
            let restored = try await client.successfulProject(owner: owner, repo: repo,
                    sha: run.head_sha, minimumIOS: preferences.minimumIOS)
            var compiledLog = ""
            if let jobs = try? await client.jobs(owner: owner, repo: repo, run: run.id),
               let buildJob = jobs.first(where: { $0.conclusion == "success" }),
               let fetched = try? await client.jobLog(owner: owner, repo: repo, job: buildJob.id) {
                compiledLog = String(fetched.suffix(20_000))
            }
            // Stage complete before changing active session; preserves previous app on error.
            project = restored
            selectedOrigin = AppBuildOrigin(appName: restored.appName,
                branch: branch, successfulCommit: run.head_sha, runID: run.id)
            referenceBuildLog = compiledLog
            userDiagnosticLog = ""
            supportMessages = []
            codePrompt = "Revise the existing \(restored.appName) application. Preserve functionality and bundle ID \(restored.bundleId)."
            chosenRepo = repo
            chosenBranch = ""
            lastCommitSHA = ""
            lastOwner = ""
            lastRepo = ""
            activeRun = nil
            jobs = []
            failureLog = ""
            repairAttempt = 0
            repairStatus = "Loaded successful \(restored.appName) build #\(run.run_number ?? run.id). Changes will use a NEW revision branch."
            moreSection = .support
            selectedTab = .more
        } catch {
            appsError = "Failed to open this successful build: \(error.localizedDescription)"
        }
    }

    func attachDeviceLog(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            notice = "Paste a device or application log before attaching it."
            return
        }
        userDiagnosticLog = String(text.suffix(24_000))
        repairStatus = "Attached runtime log to \(project?.appName ?? "project"). AI Support can now analyze it."
    }

    func refreshReleases() async {
        guard !downloadsRefreshing else { return }
        let owner = downloadsOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = downloadsRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repo.isEmpty else {
            downloadsError = "Select the GitHub owner and repository containing the generated build."
            return
        }
        downloadsRefreshing = true
        downloadsError = nil
        defer { downloadsRefreshing = false; downloads.reload() }
        do {
            let fetched = try await github().releases(owner: owner, repo: repo)
            releases = fetched
            downloadsCheckedAt = Date()
            let app = project?.appName ?? ""
            let sameBuildRepo = lastOwner.caseInsensitiveCompare(owner) == .orderedSame
                && lastRepo.caseInsensitiveCompare(repo) == .orderedSame

            latestProjectRelease = app.isEmpty ? nil : fetched.first { release in
                release.ipaAssets.contains { asset in
                    asset.name.lowercased() == "\(app.lowercased()).ipa"
                }
            }

            currentBuildRelease = nil
            if sameBuildRepo && !lastCommitSHA.isEmpty {
                currentBuildRelease = fetched.first { release in
                    release.target_commitish == lastCommitSHA
                        && (app.isEmpty || release.ipaAssets.contains { $0.name.lowercased() == "\(app.lowercased()).ipa" })
                }
                // Release target_commitish varies by GitHub workflow; tags give a second,
                // deterministic way to match the exact GitHub Actions run.
                if currentBuildRelease == nil,
                   let run = (activeRun?.head_sha == lastCommitSHA ? activeRun
                              : try? await github().latestRun(owner: owner, repo: repo, sha: lastCommitSHA)),
                   let number = run.run_number {
                    let attempt = run.run_attempt ?? 1
                    let expectedTags = [
                        "\(app)-build-\(number)-\(attempt)",
                        "build-\(number)"
                    ]
                    currentBuildRelease = fetched.first { expectedTags.contains($0.tag_name) }
                }
            }
        } catch {
            downloadsError = "Could not load IPAs from \(owner)/\(repo): \(error.localizedDescription)"
            releases = []
            currentBuildRelease = nil
            latestProjectRelease = nil
            downloadsCheckedAt = Date()
        }
    }

    func selectLastBuildDownloads() {
        guard !lastOwner.isEmpty, !lastRepo.isEmpty else { return }
        downloadsOwner = lastOwner
        downloadsRepo = lastRepo
    }

    var isRepairPending: Bool { busyFix || busyPush || queuedRepair }

    func clearHistoryAndCache() {
        history = []; saveHistory()
        requirement = ""; generatedPrompt = ""; codePrompt = ""; project = nil; failureLog = ""; importedCrash = nil
        repairAttempt = 0; repairStatus = ""; chosenBranch = ""; lastCommitSHA = ""; lastOwner = ""; lastRepo = ""
        selectedOrigin = nil; referenceBuildLog = ""; userDiagnosticLog = ""; successfulApps = []
        UserDefaults.standard.removeObject(forKey: "forgeBuildSession")
        notice = "Prompt history and generated code cleared. Downloads and Keychain tokens preserved"
    }
}
