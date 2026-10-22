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
    @Published var releases: [GitHubRelease] = []
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
        var response = try await ai().chat(system: system, user: request)
        do { return try ProjectFactory.parseModelJSON(response) }
        catch {
            // Exactly one repair attempt for invalid or incorrectly structured JSON.
            response = try await ai().chat(system: system, user: """
            Your last response could not be accepted: \(error.localizedDescription).
            Return complete valid JSON matching the required schema, no code fences.
            Original request:\n\(request)
            Previous response:\n\(String(response.prefix(45_000)))
            """)
            return try ProjectFactory.parseModelJSON(response)
        }
    }

    func generateCode() async {
        guard !codePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notice = "Enter or send a generation prompt"; return
        }
        busyCode = true; defer { busyCode = false }
        do {
            let generated = try await getProject(system: AIClient.codeSystem, request: codePrompt)
            project = try ProjectFactory.scaffold(generated, minIOS: preferences.minimumIOS)
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

    func refreshReleases() async {
        let owner = lastOwner.isEmpty ? preferences.githubUsername : lastOwner
        let repo = lastRepo.isEmpty ? chosenRepo : lastRepo
        guard !owner.isEmpty, !repo.isEmpty else { return }
        do { releases = try await github().releases(owner: owner, repo: repo) }
        catch { notice = error.localizedDescription }
        downloads.reload()
    }

    var isRepairPending: Bool { busyFix || busyPush || queuedRepair }

    func clearHistoryAndCache() {
        history = []; saveHistory()
        requirement = ""; generatedPrompt = ""; codePrompt = ""; project = nil; failureLog = ""
        repairAttempt = 0; repairStatus = ""; lastCommitSHA = ""; lastOwner = ""; lastRepo = ""
        UserDefaults.standard.removeObject(forKey: "forgeBuildSession")
        notice = "Prompt history and generated code cleared. Downloads and Keychain tokens preserved"
    }
}
