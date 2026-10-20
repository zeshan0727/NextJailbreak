import Foundation
import SwiftUI

// Next IPA Factory: the eight configured, saved agents retain their own presets.
// This orchestrator only routes scoped work to each corresponding saved ID.
struct FactoryAgentProgress: Identifiable {
    let role: String
    let duty: String
    var state: String = "Queued"
    var detail: String = "Waiting for preceding stage"
    var session: String = ""
    var id: String { role }
}

private struct FactoryReviewVerdict: Decodable {
    let approved: Bool
    let blocking_issues: [String]
    let notes: [String]?
    var clear: Bool { approved && blocking_issues.isEmpty }
}

@MainActor
extension FactoryCodeDelivery {
    func updateAgent(_ role: String, state: String? = nil,
                     detail: String? = nil, session: String? = nil) {
        guard let index = agentProgress.firstIndex(where: { $0.role == role }) else { return }
        if let state { agentProgress[index].state = state }
        if let detail { agentProgress[index].detail = detail }
        if let session { agentProgress[index].session = session }
    }

    private func readableAgentFailure(_ error: Error, role: String) -> String {
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("credential_id requires an attached vault") {
            return "MCP connection blocked. In OpenAI Agent Builder, remove the credential-based MCP/GitHub tool from " +
                role + " (keep the agent ID, model and saved instructions). Next IPA Factory uses its own GitHub token."
        }
        if raw.localizedCaseInsensitiveContains("requires_action") {
            return "This agent requested an external tool approval. Review its preset tools in Agent Builder: " + role
        }
        return String(raw.prefix(700))
    }

    private func perform(_ role: String, prompt: String,
                         gateway: NetworkBridge, ids: [String: String]) async throws -> String {
        guard let id = ids[role], !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIProblem(details: "No saved agent ID for " + role)
        }
        let started = Date()
        updateAgent(role, state: "Working", detail: "Opening saved agent session")
        report(role + " • Working")
        do {
            let result = try await gateway.runAgentWithProgress(
                agentID: id, task: prompt,
                onStarted: { [weak self] session in
                    self?.lastSession = session
                    self?.updateAgent(role, state: "Working", detail: "Session connected", session: session)
                },
                onStatus: { [weak self] sessionState in
                    self?.updateAgent(role, detail: "OpenAI: " + sessionState +
                        " • " + String(Int(Date().timeIntervalSince(started))) + "s elapsed")
                }
            )
            guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw APIProblem(details: role + " returned an empty response.")
            }
            let seconds = Int(Date().timeIntervalSince(started))
            updateAgent(role, state: "Completed", detail: "Finished in " + String(seconds) + "s")
            report(role + " • Completed in " + String(seconds) + "s")
            return result
        } catch {
            let interrupted = error is CancellationError || Task.isCancelled
            let summary = interrupted ? "Stopped because another agent failed." :
                readableAgentFailure(error, role: role)
            updateAgent(role, state: interrupted ? "Interrupted" : "Failed", detail: summary)
            report(role + (interrupted ? " • Interrupted" : " • Failed"))
            if interrupted { throw CancellationError() }
            throw APIProblem(details: role + ": " + summary)
        }
    }

    private func decodeManifest(_ output: String) throws -> FactoryGeneratedManifest {
        let cleaned = Self.extractJSON(output)
        guard let data = cleaned.data(using: .utf8) else {
            throw APIProblem(details: "Integrator response is not UTF-8.")
        }
        let manifest: FactoryGeneratedManifest
        do {
            manifest = try JSONDecoder().decode(FactoryGeneratedManifest.self, from: data)
        } catch {
            throw APIProblem(details: "Integrator did not return the required files JSON: " + error.localizedDescription)
        }
        let paths = manifest.files.map(\.path)
        guard (2...25).contains(paths.count),
              Set(paths).count == paths.count,
              paths.contains("project.yml"),
              paths.contains(where: { $0.hasSuffix(".swift") }) else {
            throw APIProblem(details: "Integrator returned missing or duplicate project files.")
        }
        for file in manifest.files {
            guard !file.path.contains(".."), !file.path.hasPrefix("/"),
                  !file.path.contains("\\"), !file.path.contains("\n"),
                  file.path == "project.yml" || file.path.hasPrefix("Sources/"),
                  [".swift", ".yml", ".plist", ".json", ".xcassets"].contains(where: { file.path.hasSuffix($0) }),
                  file.content.utf8.count < 100_000 else {
                throw APIProblem(details: "Unsafe or unsupported source: " + file.path)
            }
        }
        guard manifest.files.reduce(0, { $0 + $1.content.utf8.count }) < 400_000 else {
            throw APIProblem(details: "Generated project exceeds 400 KB.")
        }
        let project = manifest.files.first(where: { $0.path == "project.yml" })!.content
        guard project.contains("name: GeneratedApp"),
              project.contains("GeneratedApp:"),
              project.contains("Sources") else {
            throw APIProblem(details: "Integrator did not provide a valid GeneratedApp XcodeGen project.")
        }
        return manifest
    }

    private func sourceForReview(_ manifest: FactoryGeneratedManifest) throws -> String {
        let data = try JSONEncoder().encode(manifest)
        guard data.count <= 120_000 else {
            throw APIProblem(details: "Generated source is too large for complete agent review. Reduce the project size.")
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func review(_ role: String, original: String, requirements: String,
                        files: FactoryGeneratedManifest, previousReviews: String,
                        gateway: NetworkBridge, ids: [String: String]) async throws -> FactoryReviewVerdict {
        let source = try sourceForReview(files)
        let task = """
        Carry out your PRECONFIGURED SAVED AGENT ROLE: \(role).
        Independently inspect the complete source. Perform your assigned review duties.
        This is a source review only; GitHub has NOT compiled this source yet.
        Never invent compiler results or device testing.
        Return ONLY one JSON object with fields:
        {"approved":true,"blocking_issues":[],"notes":["concrete observation"]}.
        Set approved=false and list precise blocking_issues for any unmet requirement,
        absent user functionality, syntax/API problem, unsupported iOS 16 behavior,
        invalid XcodeGen configuration, or unresolved integration defect.
        No Markdown fences or explanatory text outside the JSON.
        Approval is only source-review approval, not proof of a successful build.

        ORIGINAL REQUEST:
        \(original)

        AGENT 1 SPECIFICATION:
        \(String(requirements.prefix(22000)))

        PRIOR REVIEW NOTES:
        \(String(previousReviews.prefix(9000)))

        FULL PROJECT SOURCES (JSON):
        \(source)
        """
        let raw = try await perform(role, prompt: task, gateway: gateway, ids: ids)
        let cleaned = Self.extractJSON(raw)
        guard let data = cleaned.data(using: .utf8) else {
            throw APIProblem(details: role + " response isn't UTF-8.")
        }
        do {
            return try JSONDecoder().decode(FactoryReviewVerdict.self, from: data)
        } catch {
            updateAgent(role, state: "Failed", detail: "Reviewer did not return structured findings.")
            throw APIProblem(details: role + " must return valid structured source-review JSON. " + error.localizedDescription)
        }
    }

    func runTeamPipeline(using factory: LocalFactoryState, reuseEditedPrompt: Bool) async {
        guard !running else { return }
        let original = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else {
            message = "Describe the app you want to create."
            return
        }
        let roles = FactoryRoles.all
        let ids = factory.agentIDs
        let missing = roles.filter {
            (ids[$0.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map(\.name)
        guard missing.isEmpty else {
            message = "Set all eight agent IDs in Settings. Missing: " + missing.joined(separator: ", ")
            return
        }
        guard !reuseEditedPrompt || !engineeredPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "No edited development prompt is available."
            return
        }

        let gateway = factory.gateway
        running = true
        approvedByTeam = false
        proposed = []
        reviewSummary = ""
        agentProgress = roles.map {
            FactoryAgentProgress(role: $0.name, duty: $0.purpose)
        }
        lastSession = ""
        startedAt = Date()
        activity = []
        report("Starting all eight saved agents")
        defer { running = false }

        do {
            // Validate all eight saved agent definitions simultaneously BEFORE
            // spending time and tokens on the Prompt Engineer.
            report("Preflight • Checking 8 saved agent configurations")
            message = "Checking saved agent IDs and known MCP credentials before running AI."
            let vaultBlocked = try await withThrowingTaskGroup(of: (String, Bool).self) { group in
                for role in roles {
                    let id = ids[role.name] ?? ""
                    group.addTask {
                        let needsVault = try await gateway.checkAgentVaultRequirement(agentID: id)
                        return (role.name, needsVault)
                    }
                }
                var blocked: [String] = []
                for try await (name, needsVault) in group {
                    if needsVault {
                        blocked.append(name)
                        updateAgent(name, state: "Blocked", detail: "Credential-based MCP tool needs an attached vault.")
                    } else {
                        updateAgent(name, detail: "Agent found; detailed tool metadata may be unavailable.")
                    }
                }
                return blocked.sorted()
            }
            guard vaultBlocked.isEmpty else {
                throw APIProblem(details:
                    "Preflight found MCP credentials requiring a vault for: " +
                    vaultBlocked.joined(separator: ", ") +
                    ". Remove the credential-based MCP/GitHub tool from these saved agents. Agent IDs and instructions stay unchanged.")
            }
            report("Preflight • No exposed credential-based MCP tools detected")
            if !reuseEditedPrompt {
                engineeredPrompt = ""
                let promptTask = """
                Fulfill your PRECONFIGURED Prompt Engineer duties.
                Translate this plain-language app idea into a precise, testable
                iOS 16 SwiftUI product specification for the other saved agents.
                Preserve the exact requested functions and constraints.
                Choose conservative defaults where unspecified. Do NOT mandate
                any optional app icon, external API, or unsupported feature.
                Supply screens, actions, persistence, architecture constraints,
                failure cases, and exact acceptance criteria. Do not write code.
                For speed and cost, return a concise actionable specification
                (at most 600 words). Do not browse, invoke external tools, or
                repeat requirements unnecessarily; use your saved role instructions.

                ORIGINAL IDEA:
                \(original)
                """
                message = "Agent 1 is preparing the app specification."
                engineeredPrompt = try await perform(
                    "Prompt Engineer", prompt: promptTask, gateway: gateway, ids: ids
                )
            } else {
                updateAgent("Prompt Engineer", state: "Reused", detail: "Using your edited specification")
                report("Using your edited Agent 1 specification")
            }
            let requirements = engineeredPrompt
            let sourceRules = """
            iOS 16+, native SwiftUI, no fabricated build results.
            Your saved agent role and preset instructions remain authoritative.
            Preserve the user's requirements and coordinate source interfaces
            with the intended GeneratedApp project. Include actual implementation
            details, not generic advice.
            """
            report("Agents 2–5 • Parallel development")
            message = "Architect, UI Developer, Core Developer, and iOS Specialist are working in parallel."
            var parallel: [String: String] = [:]
            let jobs: [(String, String)] = [
                ("Architect", """
                 Design the technical architecture, source-file layout, state management,
                 module interfaces, persistence schema, and navigation for this app.
                 Describe integration contracts for UI and core code.
                 \(sourceRules)
                 """),
                ("UI Developer", """
                 Implement the complete user-facing SwiftUI interface and screen flow.
                 Supply working code or concrete view-level implementation for every
                 visible control, including accessibility and light/dark mode.
                 \(sourceRules)
                 """),
                ("Core Developer", """
                 Implement concrete business logic, models, validation, persistence,
                 edge cases, and test cases expected by the acceptance criteria.
                 Supply usable Swift code and interface contracts for the UI team.
                 \(sourceRules)
                 """),
                ("iOS Specialist", """
                 Review iOS 16 compatibility, navigation / SwiftUI APIs,
                 permissions / entitlements, signing and TrollStore constraints,
                 and source-asset / XcodeGen requirements. Provide specific
                 compatibility corrections and tests; no fake build claims.
                 \(sourceRules)
                 """)
            ]
            try await withThrowingTaskGroup(of: (String, String).self) { group in
                for (role, focus) in jobs {
                    let work = """
                    Fulfill your SAVED AGENT DUTY as \(role).
                    ORIGINAL USER IDEA:
                    \(original)
                    AGENT 1 DETAILED ACCEPTANCE SPECIFICATION:
                    \(String(requirements.prefix(18000)))
                    TASK:
                    \(focus)
                    """
                    group.addTask { [weak self] in
                        guard let self else {
                            throw APIProblem(details: "Factory session was closed.")
                        }
                        let result = try await self.perform(role, prompt: work, gateway: gateway, ids: ids)
                        return (role, result)
                    }
                }
                for try await (role, result) in group {
                    parallel[role] = result
                }
            }
            // Never integrate against incomplete or failed parallel work.
            guard parallel.count == 4 else {
                throw APIProblem(details: "One or more development agents did not finish.")
            }
            let handoffs = jobs.map { role, _ in
                "== \(role) WORK ==\n" +
                String((parallel[role] ?? "").prefix(19000))
            }.joined(separator: "\n\n")
            let generatorTask = """
            Fulfill your PRECONFIGURED Integrator duties. Merge and reconcile
            the architecture, UI, core and iOS specialist work into one
            COMPLETE, COMPILABLE, iOS 16+ SwiftUI XcodeGen project.
            Resolve interface mismatches; keep every specified feature.
            Do not return descriptions or TODO placeholders.
            The full output must be EXACTLY one JSON object:
            {"files":[{"path":"project.yml","content":"..."},{"path":"Sources/GeneratedApp.swift","content":"..."}]}
            Include ALL needed Swift files as file entries. project.yml must
            declare name GeneratedApp, application target GeneratedApp, platform iOS,
            and sources path Sources. Exactly one @main GeneratedAppApp: App.
            No fabricated compile claims. No app icon unless requested and supported.

            ORIGINAL USER REQUEST:
            \(original)
            SPECIFICATION:
            \(String(requirements.prefix(22000)))
            PARALLEL SPECIALIST WORK:
            \(String(handoffs.prefix(74000)))
            """
            message = "Agent 6 is integrating the four specialists' work."
            var manifest = try decodeManifest(
                try await perform("Integrator", prompt: generatorTask, gateway: gateway, ids: ids)
            )
            // Source-only QA and release review; compilation happens on GitHub after approval.
            for round in 0...2 {
                let earlier = round == 0 ? "Initial independent review" : "Re-review following repair round \(round)"
                message = "Agents 7 and 8 are reviewing complete source."
                report(earlier)
                // Independent QA and release checks run concurrently for speed.
                let previous = reviewSummary
                var decisions: [String: FactoryReviewVerdict] = [:]
                try await withThrowingTaskGroup(of: (String, FactoryReviewVerdict).self) { group in
                    for role in ["QA Reviewer", "Release Reviewer"] {
                        group.addTask { [weak self] in
                            guard let self else {
                                throw APIProblem(details: "Factory session was closed.")
                            }
                            let verdict = try await self.review(
                                role, original: original, requirements: requirements,
                                files: manifest, previousReviews: previous,
                                gateway: gateway, ids: ids
                            )
                            return (role, verdict)
                        }
                    }
                    for try await (role, verdict) in group {
                        decisions[role] = verdict
                    }
                }
                guard let qa = decisions["QA Reviewer"],
                      let release = decisions["Release Reviewer"] else {
                    throw APIProblem(details: "Both reviewers must return their verdicts.")
                }
                reviewSummary = """
                QA: \(qa.clear ? "Approved" : "Changes needed")
                \(qa.blocking_issues.joined(separator: "\n"))
                Release: \(release.clear ? "Source-review approved" : "Changes needed")
                \(release.blocking_issues.joined(separator: "\n"))
                """
                if qa.clear && release.clear {
                    approvedByTeam = true
                    proposed = manifest.files
                    report("All eight agents finished; independent reviews approved source")
                    message = "8-agent development and source reviews completed. " +
                        String(manifest.files.count) +
                        " files are ready for your GitHub approval. Compilation remains unverified."
                    return
                }
                guard round < 2 else {
                    throw APIProblem(details: "QA or Release Review still reports blockers after two repairs. " +
                                     String(reviewSummary.prefix(2000)))
                }
                report("QA/Release issues detected • Integrator repair " + String(round + 1))
                message = "Repairing source defects found by QA and Release Review."
                let oldSource = try sourceForReview(manifest)
                let repairTask = """
                Fulfill your SAVED Integrator role. Correct EVERY concrete
                blocking issue found by the independent QA and release agents.
                Keep the user's requested functions intact; do not remove
                features to silence errors. Return ONLY complete replacement
                JSON with {"files":[{"path":"project.yml","content":"..."}, ...]}.
                No explanations, Markdown, placeholders, or fabricated tests.

                ORIGINAL USER IDEA:
                \(original)
                ACCEPTANCE CRITERIA:
                \(String(requirements.prefix(19000)))
                ISSUES TO FIX:
                \(reviewSummary)
                CURRENT FULL SOURCE:
                \(oldSource)
                """
                manifest = try decodeManifest(
                    try await perform("Integrator", prompt: repairTask, gateway: gateway, ids: ids)
                )
            }
        } catch {
            proposed = []
            approvedByTeam = false
            // Replace in-progress rows with a truthful interrupted state.
            for row in agentProgress where row.state == "Working" {
                updateAgent(row.role, state: "Interrupted", detail: "Pipeline stopped; check activity log")
            }
            report("Development stopped: " + error.localizedDescription)
            message = "8-agent pipeline stopped: " + String(error.localizedDescription.prefix(900))
        }
    }
}
