from pathlib import Path
import plistlib

root = Path(".")
swift_path = root / "NextAgent/NextAgent.swift"
router_path = root / "NextAgent/V071Router.swift"
modern_ui_path = root / "NextAgent/ModernUI.swift"

s = swift_path.read_text()
router = router_path.read_text()
ui = modern_ui_path.read_text()

# ---- Product/version: internal stability build, HUD discontinued ----
s = s.replace(
    "Next Agent 0.7.19 is ready with a SpringBoard-anchored system HUD and full-screen app automation.",
    "Next Agent 0.7.20 is focused on internal stability: automatic managed-session recovery, cleaner API errors, and reliable full-screen automation."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.19-springboard-hud13"',
    'private static let currentToolSchemaVersion = "0.7.20-session-recovery14"'
)
s = s.replace('"client_version": "0.7.19"', '"client_version": "0.7.20"')

router = router.replace(
    '"router_version": "0.7.19-springboard-hud13"',
    '"router_version": "0.7.20-session-recovery14"'
)

# HUD project is discontinued. Remove HUD from local self-test rather than
# allowing a non-core experiment to fail otherwise healthy phone automation.
hud_start = router.find('        let hudRaw = NAScreenBridgeClient.hudStatus()')
if hud_start >= 0:
    hud_end = router.find('\n\n', hud_start)
    if hud_end < 0:
        raise SystemExit("v0.7.20 HUD self-test end missing")
    router = router[:hud_start] + router[hud_end + 2:]

# Remove manual HUD test logic from AppState.
hud_func_start = s.find('    func testSystemHUD() {')
if hud_func_start >= 0:
    hud_func_end = s.find('    func clearWorkspaceOverlay()', hud_func_start)
    if hud_func_end < 0:
        raise SystemExit("v0.7.20 testSystemHUD end missing")
    s = s[:hud_func_start] + s[hud_func_end:]

# ---- Managed agent: conflict recovery ----
# Track whether a turn already executed device-side actions. We only
# transparently replay a conflicted turn when no tool has executed, preventing
# duplicate taps/writes/sends.
client_marker = '    private let savedAgentId = "agent_a8bca3810e67406a8076559d2ba2e10f1379810a596e4d3082"\n'
if client_marker not in s:
    raise SystemExit("v0.7.20 managed-agent property marker missing")
if "currentTurnToolExecutionCount" not in s:
    s = s.replace(
        client_marker,
        client_marker + '    private var currentTurnToolExecutionCount = 0\n',
        1
    )

run_start = s.find('    @MainActor\n    func runUserMessage(_ message: String) async throws -> String {')
run_end = s.find('    private func createSession(initialMessage: String) async throws -> [String: Any] {', run_start)
if run_start < 0 or run_end < 0:
    raise SystemExit("v0.7.20 runUserMessage bounds missing")

run_block = '''    @MainActor
    func runUserMessage(_ message: String) async throws -> String {
        guard state != nil else { throw NSError(domain: "NextAgent", code: 2) }
        currentTurnToolExecutionCount = 0

        do {
            return try await runUserMessageAttempt(message)
        } catch {
            guard isSessionConflict(error) else {
                throw normalizeAPIError(error)
            }

            // A stale/broken managed session is safe to recreate only before
            // any device action has executed in this turn.
            if currentTurnToolExecutionCount > 0 {
                resetManagedSessionState()
                throw NSError(
                    domain: "NextAgent.Session",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey:
                        "The agent session expired after a device action. I reset the session to avoid repeating that action. Send the command once more."
                    ]
                )
            }

            resetManagedSessionState()
            try? await Task.sleep(nanoseconds: 250_000_000)

            do {
                return try await runUserMessageAttempt(message)
            } catch {
                if isSessionConflict(error) {
                    resetManagedSessionState()
                }
                throw normalizeAPIError(error)
            }
        }
    }

    @MainActor
    private func runUserMessageAttempt(_ message: String) async throws -> String {
        guard let state else { throw NSError(domain: "NextAgent", code: 2) }

        let baselineAssistantId: String?
        if state.sessionId.isEmpty {
            baselineAssistantId = nil
            let created = try await createSession(initialMessage: message)
            try Task.checkCancellation()
            guard let id = created["id"] as? String, !id.isEmpty else {
                throw apiShape("Managed session response had no session id", created)
            }
            state.sessionId = id
            UserDefaults.standard.set(id, forKey: "nextagent.managedSessionId")
        } else {
            baselineAssistantId = try await latestAssistantMessage(sessionId: state.sessionId)?.id
            try await sendUserMessage(sessionId: state.sessionId, text: message)
            try Task.checkCancellation()
        }

        markPending(baselineAssistantId: baselineAssistantId)
        return try await driveSession(
            sessionId: state.sessionId,
            baselineAssistantId: baselineAssistantId
        )
    }

    @MainActor
    private func resetManagedSessionState() {
        state?.sessionId = ""
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "nextagent.managedSessionId")
        defaults.removeObject(forKey: "nextagent.pendingTurn")
        defaults.removeObject(forKey: "nextagent.pendingBaselineAssistantId")
        clearPending()
    }

    private func isSessionConflict(_ error: Error) -> Bool {
        let ns = error as NSError
        let text = ns.localizedDescription.lowercased()
        return ns.code == 409
            || text.contains("conflict_error")
            || text.contains("session startup failed")
            || text.contains("create a new session")
            || text.contains("session conflict")
    }

    private func normalizeAPIError(_ error: Error) -> Error {
        let ns = error as NSError
        let raw = ns.localizedDescription

        if let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let apiError = object["error"] as? [String: Any],
           let message = apiError["message"] as? String,
           !message.isEmpty {
            return NSError(
                domain: ns.domain,
                code: ns.code,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        return error
    }

'''
s = s[:run_start] + run_block + s[run_end:]

# Count actual tool execution. A session conflict after this point is not
# automatically replayed.
tool_marker = '''                    state.toolStarted(action.name, arguments: action.arguments)
                    let result = await tools.execute(action.name, arguments: action.arguments, allowSensitive: state.sensitiveActions)
'''
if tool_marker not in s:
    raise SystemExit("v0.7.20 tool execution marker missing")
s = s.replace(
    tool_marker,
    '''                    state.toolStarted(action.name, arguments: action.arguments)
                    currentTurnToolExecutionCount += 1
                    let result = await tools.execute(action.name, arguments: action.arguments, allowSensitive: state.sensitiveActions)
''',
    1
)

# API error envelopes are normalized in runUserMessage via normalizeAPIError().
# Keep the proven request transport unchanged to avoid destabilizing networking.

# ---- Make background diagnostics truthful ----
self_start = s.find('    func runLocalSelfTest() async {')
self_end = s.find('    func handleBecameActive() async {', self_start)
if self_start < 0 or self_end < 0:
    raise SystemExit("v0.7.20 self-test bounds missing")

self_block = '''    func runLocalSelfTest() async {
        guard !busy else { return }
        busy = true
        status = "Running local tool self-test…"
        defer { busy = false }

        let pid = String(getpid())
        let protect = RootDaemonClient.request(action: "protect_pid", argument: pid)
        let protectStatus = RootDaemonClient.request(action: "protection_status")
        _ = RootDaemonClient.request(action: "unprotect_pid", argument: pid)

        var assertionValid = false
        var processAlive = false
        if let data = protectStatus.output.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            assertionValid = (object["assertion_valid"] as? NSNumber)?.intValue == 1
            processAlive = (object["process_alive"] as? NSNumber)?.boolValue == true
        }

        let protectionLabel: String
        if assertionValid {
            protectionLabel = "VERIFIED"
        } else if protect.success && processAlive {
            protectionLabel = "PARTIAL — process alive, no valid background assertion"
        } else {
            protectionLabel = "FAIL"
        }

        let result = await tools.localSelfTest(allowSensitive: sensitiveActions)
        recordTool("local_self_test", result)

        let report =
            "Daemon background protection: \\(protectionLabel) | \\(protectStatus.output) | " +
            "Local tool self-test: \\(result.output)"
        messages.append(ChatMessage(role: "assistant", text: report))

        if !result.success {
            status = "Local self-test found failures"
        } else if assertionValid {
            status = "Local self-test complete"
        } else {
            status = "Local self-test complete with background warning"
        }
    }

'''
s = s[:self_start] + self_block + s[self_end:]

# ---- UI cleanup: remove discontinued HUD controls ----
quick = '''            HStack(spacing: 10) {
                actionTile("Show HUD", "rectangle.topthird.inset.filled", NATheme.cyan) {
                    state.testSystemHUD()
                }
                actionTile("Clear Split", "rectangle.split.1x2.slash.fill", NATheme.orange) {
                    state.clearWorkspaceOverlay()
                }
            }
'''
ui = ui.replace(quick, "", 1)

settings_start = ui.find('                    settingsSection("SYSTEM-WIDE HUD") {')
if settings_start >= 0:
    settings_end = ui.find('                    settingsSection("OPENAI AGENT") {', settings_start)
    if settings_end < 0:
        raise SystemExit("v0.7.20 HUD settings end missing")
    ui = ui[:settings_start] + ui[settings_end:]

ui = ui.replace(
    "0.7.19 • RootHide • SpringBoard HUD • Full-Screen Apps",
    "0.7.20 • RootHide • Session Recovery • Full-Screen Apps"
)

swift_path.write_text(s)
router_path.write_text(router)
modern_ui_path.write_text(ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.19", "MARKETING_VERSION: 0.7.20")
y = y.replace("CURRENT_PROJECT_VERSION: 27", "CURRENT_PROJECT_VERSION: 28")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.20"
d["CFBundleVersion"] = "28"
plist_path.write_bytes(plistlib.dumps(d))

final_s = swift_path.read_text()
final_r = router_path.read_text()
final_ui = modern_ui_path.read_text()
assert 'currentToolSchemaVersion = "0.7.20-session-recovery14"' in final_s
assert '"router_version": "0.7.20-session-recovery14"' in final_r
assert "isSessionConflict" in final_s
assert "currentTurnToolExecutionCount" in final_s
assert "PARTIAL — process alive, no valid background assertion" in final_s
assert "status_hud_springboard" not in final_r
assert 'actionTile("Show HUD"' not in final_ui
assert 'settingsSection("SYSTEM-WIDE HUD")' not in final_ui
assert "MARKETING_VERSION: 0.7.20" in project.read_text()
