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
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: ForgeTab = .requirement
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
    @Published var notice: String?
    @Published var repositories: [GitHubRepo] = []
    @Published var branches: [GitHubBranch] = []
    @Published var chosenRepo = "" { didSet { persistBuildSession() } }
    @Published var chosenBranch = "main" { didSet { persistBuildSession() } }
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
    let maximumRepairAttempts = 2
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
            chosenBranch = session.branch
            lastOwner = session.owner
            lastRepo = session.repo
            lastCommitSHA = session.commitSHA
            repairAttempt = session.repairs
            repairStatus = session.repairStatus
        }

        downloadsOwner = lastOwner.isEmpty ? preferences.githubUsername : lastOwner
        downloadsRepo = lastRepo.isEmpty ? (chosenRepo.isEmpty ? preferences.defaultRepo : chosenRepo) : lastRepo
        restoringBuildSession = false
    }

    private func persistBuildSession() {
        guard !restoringBuildSession else { return }
        let session = SavedForgeSession(project: project, codePrompt: codePrompt, owner: lastOwner,
            repo: lastRepo.isEmpty ? chosenRepo : lastRepo, branch: chosenBranch,
            commitSHA: lastCommitSHA, repairs: repairAttempt, repairStatus: repairStatus)
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

    private func getProject(system: String, request: String) async throws -> ForgeProject {
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
            let answer = try await ai().chat(system: system, user: instruction, jsonMode: true)
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
            repairStatus = "Code generation complete. JSON response validated."
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
            await refreshBranches()
        } catch { notice = error.localizedDescription }
    }
    func refreshBranches() async {
        guard !chosenRepo.isEmpty else { branches = []; return }
        let repo = repositories.first { $0.name == chosenRepo }
        chosenBranch = repo?.default_branch ?? "main"
        do { branches = try await github().branches(owner: preferences.githubUsername, repo: chosenRepo) }
        catch { notice = error.localizedDescription }
    }
    func createRepo(name: String, isPrivate: Bool) async {
        do {
            let new = try await github().createRepo(name: name, isPrivate: isPrivate)
            preferences.githubUsername = new.full_name.split(separator: "/").first.map(String.init) ?? preferences.githubUsername
            await refreshRepos()
            chosenRepo = new.name
            chosenBranch = new.default_branch
            await refreshBranches()
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
            let initialBranch = repositories.first(where: { $0.name == repo })?.default_branch ?? "main"
            let sha = try await github().push(project: project, owner: owner, repo: repo,
                                              branch: chosenBranch, message: commitMessage,
                                              sourceBranch: initialBranch)
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
                if missingRunChecks >= 4 && !fallbackDispatched {
                    fallbackDispatched = true
                    do { try await client.dispatch(owner: lastOwner, repo: lastRepo, branch: chosenBranch) }
                    catch { notice = "Push completed, but no run found yet. Manual dispatch unavailable: \(error.localizedDescription)" }
                }
            }
        } catch { notice = error.localizedDescription }
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
            let corrected = try await getProject(system: AIClient.codeSystem, request: """
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
            """)
            guard corrected.bundleId == project.bundleId else {
                throw ForgeError.message("AI tried to change bundle identifier; repair rejected")
            }
            self.project = try ProjectFactory.scaffold(corrected, minIOS: preferences.minimumIOS)
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
        repairAttempt = 0; repairStatus = ""; lastCommitSHA = ""; lastOwner = ""; lastRepo = ""
        UserDefaults.standard.removeObject(forKey: "forgeBuildSession")
        notice = "Prompt history and generated code cleared. Downloads and Keychain tokens preserved"
    }
}
