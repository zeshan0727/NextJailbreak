from pathlib import Path
import plistlib

root = Path(".")
p = root / "NextAgent/NextAgent.swift"
s = p.read_text()

s = s.replace(
    "Next Agent 0.7.2 is ready with jailbreak-native background pinning for multi-app automation.",
    "Next Agent 0.7.3 is ready with daemon-held background protection and floating SpringBoard progress."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.2-bgpin1"',
    'private static let currentToolSchemaVersion = "0.7.3-daemonpin1"'
)

anchor = "    private var activeTurnID: UUID?\n"
if anchor not in s:
    raise SystemExit("v0.7.3 AppState property anchor missing")
s = s.replace(
    anchor,
    anchor + "    private var activeReturnToApp = false\n    private var progressStepCount = 0\n",
    1
)

start = s.find("    func send() async {")
end = s.find("    func forceStop()", start)
if start < 0 or end < 0:
    raise SystemExit("v0.7.3 send bounds missing")
send_block = '''    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        guard CredentialStore.loadAPIKey() != nil else {
            status = "API key missing"
            return
        }

        input = ""
        messages.append(ChatMessage(role: "user", text: text))
        busy = true
        status = "Agent working…"
        activeReturnToApp = shouldReturnToNextAgent(for: text)
        progressStepCount = 0
        publishProgress(state: "working", message: "Planning task…", progress: 0.05, returnToApp: activeReturnToApp)
        beginBackgroundTurnIfNeeded()

        let turnID = UUID()
        let turnTask = Task<String, Error> { [client] in
            try await client.runUserMessage(text)
        }
        activeTurnID = turnID
        activeTurnTask = turnTask

        defer {
            if activeTurnID == turnID {
                activeTurnTask = nil
                activeTurnID = nil
                busy = false
                endBackgroundTurn()
            }
        }

        do {
            let reply = try await turnTask.value
            guard activeTurnID == turnID else { return }
            messages.append(ChatMessage(role: "assistant", text: reply))
            status = "Ready"
            publishProgress(state: "complete", message: "Task complete", progress: 1.0, returnToApp: activeReturnToApp)
        } catch is CancellationError {
            if activeTurnID == turnID {
                status = "Stopped"
                publishProgress(state: "stopped", message: "Task stopped", progress: 1.0, returnToApp: false)
            }
        } catch {
            guard activeTurnID == turnID else { return }
            if backgroundContinuation && client.hasPendingTurn {
                status = "Turn paused — will resume automatically"
                backgroundState = "Pending"
                publishProgress(state: "working", message: "Waiting to resume…", progress: min(0.90, currentProgressEstimate()), returnToApp: activeReturnToApp)
            } else {
                messages.append(ChatMessage(role: "assistant", text: "Error: \\(error.localizedDescription)"))
                status = "Failed"
                publishProgress(state: "failed", message: "Task failed", progress: 1.0, returnToApp: true)
            }
        }
    }

'''
s = s[:start] + send_block + s[end:]

start = s.find("    func forceStop() {")
end = s.find("    func runLocalSelfTest() async {", start)
if start < 0 or end < 0:
    raise SystemExit("v0.7.3 force stop bounds missing")
force_block = '''    func forceStop() {
        activeTurnTask?.cancel()
        activeTurnTask = nil
        activeTurnID = nil
        busy = false
        status = "Force stopped — next command will start a fresh session"
        backgroundState = "Idle"
        publishProgress(state: "stopped", message: "Force stopped", progress: 1.0, returnToApp: false)
        endBackgroundTurn()

        sessionId = ""
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "nextagent.managedSessionId")
        defaults.removeObject(forKey: "nextagent.pendingTurn")
        defaults.removeObject(forKey: "nextagent.pendingBaselineAssistantId")

        messages.append(ChatMessage(role: "assistant", text: "Active task force-stopped. The next command will use a fresh tool session."))
    }

'''
s = s[:start] + force_block + s[end:]

start = s.find("    func runLocalSelfTest() async {")
end = s.find("    func handleBecameActive() async {", start)
if start < 0 or end < 0:
    raise SystemExit("v0.7.3 self-test bounds missing")
self_test_block = '''    func runLocalSelfTest() async {
        guard !busy else { return }
        busy = true
        status = "Running local tool self-test…"
        defer { busy = false }

        let pid = String(getpid())
        let protect = RootDaemonClient.request(action: "protect_pid", argument: pid)
        let protectStatus = RootDaemonClient.request(action: "protection_status")
        _ = RootDaemonClient.request(action: "unprotect_pid", argument: pid)

        let result = await tools.localSelfTest(allowSensitive: sensitiveActions)
        recordTool("local_self_test", result)
        let report = "Daemon background protector: \\(protect.success ? "PASS" : "FAIL") | \\(protectStatus.output) | Local tool self-test: \\(result.output)"
        messages.append(ChatMessage(role: "assistant", text: report))
        status = result.success && protect.success ? "Local self-test complete" : "Local self-test found failures"
    }

'''
s = s[:start] + self_test_block + s[end:]

start = s.find("    func resumePendingTurnIfNeeded() async {")
end = s.find("    private func beginBackgroundTurnIfNeeded()", start)
if start < 0 or end < 0:
    raise SystemExit("v0.7.3 resume bounds missing")
resume_block = '''    func resumePendingTurnIfNeeded() async {
        guard backgroundContinuation, !busy, client.hasPendingTurn, !sessionId.isEmpty else { return }
        busy = true
        status = "Resuming background turn…"
        publishProgress(state: "working", message: "Resuming task…", progress: max(0.12, currentProgressEstimate()), returnToApp: activeReturnToApp)
        beginBackgroundTurnIfNeeded()

        let turnID = UUID()
        let turnTask = Task<String, Error> { [client] in
            try await client.resumePendingTurn()
        }
        activeTurnID = turnID
        activeTurnTask = turnTask

        defer {
            if activeTurnID == turnID {
                activeTurnTask = nil
                activeTurnID = nil
                busy = false
                endBackgroundTurn()
            }
        }

        do {
            let reply = try await turnTask.value
            guard activeTurnID == turnID else { return }
            messages.append(ChatMessage(role: "assistant", text: reply))
            status = "Ready"
            publishProgress(state: "complete", message: "Task complete", progress: 1.0, returnToApp: activeReturnToApp)
        } catch is CancellationError {
            if activeTurnID == turnID {
                status = "Stopped"
                publishProgress(state: "stopped", message: "Task stopped", progress: 1.0, returnToApp: false)
            }
        } catch {
            if activeTurnID == turnID {
                status = "Background turn pending"
                publishProgress(state: "working", message: "Waiting to resume…", progress: min(0.90, currentProgressEstimate()), returnToApp: activeReturnToApp)
            }
        }
    }

'''
s = s[:start] + resume_block + s[end:]

start = s.find("    private func beginBackgroundTurnIfNeeded() {")
end = s.find("    func checkRootHelper()", start)
if start < 0 or end < 0:
    raise SystemExit("v0.7.3 background bounds missing")
background_block = '''    private func beginBackgroundTurnIfNeeded() {
        guard backgroundContinuation else { return }

        let pid = String(getpid())
        let daemonPinned = RootDaemonClient.request(action: "protect_pid", argument: pid)
        let localPinned = NABackgroundAssertionController.shared().start()
        let extended = BackgroundKeepAlive.shared.start()

        if daemonPinned.success {
            backgroundState = "Daemon pinned"
        } else if localPinned {
            backgroundState = "Pinned background"
        } else if extended {
            backgroundState = "Extended background"
        } else {
            backgroundState = "Protected"
        }

        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "NextAgentTurn") { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.endUIKitBackgroundTaskOnly()

                    let daemonStatus = RootDaemonClient.request(action: "protection_status")
                    if daemonStatus.success {
                        self.backgroundState = "Daemon pinned"
                    } else if NABackgroundAssertionController.shared().isValid {
                        self.backgroundState = "Pinned background"
                    } else if BackgroundKeepAlive.shared.active {
                        self.backgroundState = "Extended background"
                    } else {
                        self.backgroundState = "Background protection lost"
                    }
                }
            }
        }
    }

    private func endUIKitBackgroundTaskOnly() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func endBackgroundTurn() {
        endUIKitBackgroundTaskOnly()
        _ = RootDaemonClient.request(action: "unprotect_pid", argument: String(getpid()))
        BackgroundKeepAlive.shared.stop()
        NABackgroundAssertionController.shared().stop()
        if !client.hasPendingTurn {
            backgroundState = "Idle"
        }
    }

'''
s = s[:start] + background_block + s[end:]

start = s.find("    func recordTool(_ name: String, _ result: ToolResult) {")
end = s.find("\n}\n\n// MARK: - OpenAI Managed Agents API", start)
if start < 0 or end < 0:
    raise SystemExit("v0.7.3 recordTool bounds missing")
helpers = '''    func toolStarted(_ name: String, arguments: [String: Any]) {
        progressStepCount += 1
        let label = progressLabel(for: name, arguments: arguments)
        publishProgress(
            state: "working",
            message: label,
            progress: currentProgressEstimate(),
            returnToApp: activeReturnToApp
        )
    }

    func recordTool(_ name: String, _ result: ToolResult) {
        lastTool = name
        let stamp = ISO8601DateFormatter().string(from: Date())
        toolLog.insert("\\(stamp)  \\(name)  \\(result.success ? "OK" : "FAIL")  \\(result.output.prefix(180))", at: 0)
        if toolLog.count > 100 { toolLog.removeLast(toolLog.count - 100) }

        let label = progressLabel(for: name, arguments: [:])
        publishProgress(
            state: "working",
            message: result.success ? "\\(label) ✓" : "\\(label) — retrying",
            progress: min(0.92, currentProgressEstimate() + 0.025),
            returnToApp: activeReturnToApp
        )
    }

    private func currentProgressEstimate() -> Double {
        min(0.90, 0.10 + Double(progressStepCount) * 0.085)
    }

    private func publishProgress(state progressState: String, message: String, progress: Double, returnToApp: Bool) {
        let payload: [String: Any] = [
            "state": progressState,
            "message": String(message.prefix(90)),
            "progress": max(0, min(1, progress)),
            "return_to_app": returnToApp,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        _ = RootDaemonClient.request(action: "progress", argument: text)
    }

    private func progressLabel(for name: String, arguments: [String: Any]) -> String {
        switch name {
        case "phone_apps":
            if let action = arguments["action"] as? String, action.hasPrefix("open") { return "Opening app…" }
            return "Checking apps…"
        case "phone_screen": return "Reading screen…"
        case "phone_input":
            if (arguments["action"] as? String) == "type_text" { return "Typing…" }
            return "Interacting…"
        case "phone_files": return "Working with files…"
        case "phone_packages": return "Managing package…"
        case "phone_services": return "Running system action…"
        case "phone_automation": return "Running automation…"
        case "phone_status": return "Checking device…"
        case "phone_clipboard": return "Updating clipboard…"
        case "phone_display": return "Updating display…"
        default: return "Agent working…"
        }
    }

    private func shouldReturnToNextAgent(for text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("return to next agent") || lower.contains("come back to next agent") || lower.contains("return to the app") {
            return true
        }
        if lower.contains("stay in ") || lower.contains("leave me in ") || lower.contains("do not return") || lower.contains("don't return") {
            return false
        }

        let externalActions = [
            "open ", "launch ", "tap ", "press ", "swipe ", "type ",
            "write ", "create ", "send ", "set ", "change ", "install ",
            "remove ", "delete ", "play ", "pause ", "lock ", "respring"
        ]
        if externalActions.contains(where: { lower.contains($0) }) {
            return false
        }
        return true
    }
'''
s = s[:start] + helpers + s[end:]

drive_start = s.find("    private func driveSession(")
drive_end = s.find("    private func parseRequiredActions", drive_start)
if drive_start < 0 or drive_end < 0:
    raise SystemExit("v0.7.3 driveSession bounds missing")
segment = s[drive_start:drive_end]
needle = '                    let result = await tools.execute(action.name, arguments: action.arguments, allowSensitive: state.sensitiveActions)\n'
if needle not in segment:
    raise SystemExit("v0.7.3 driveSession tool execution marker missing")
segment = segment.replace(
    needle,
    '                    state.toolStarted(action.name, arguments: action.arguments)\n' + needle,
    1
)
s = s[:drive_start] + segment + s[drive_end:]

s = s.replace('"client_version": "0.7.2"', '"client_version": "0.7.3"')
p.write_text(s)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.2", "MARKETING_VERSION: 0.7.3")
y = y.replace("CURRENT_PROJECT_VERSION: 10", "CURRENT_PROJECT_VERSION: 11")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.3"
d["CFBundleVersion"] = "11"
plist_path.write_bytes(plistlib.dumps(d))

final = p.read_text()
assert "protect_pid" in final
assert "publishProgress" in final
assert "toolStarted(action.name" in final
assert 'currentToolSchemaVersion = "0.7.3-daemonpin1"' in final
assert "MARKETING_VERSION: 0.7.3" in project.read_text()
