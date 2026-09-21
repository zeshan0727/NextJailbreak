from pathlib import Path
import plistlib

root = Path(".")
swift_path = root / "NextAgent/NextAgent.swift"
router_path = root / "NextAgent/V071Router.swift"
v07_path = root / "NextAgent/V07Tools.swift"
modern_ui_path = root / "NextAgent/ModernUI.swift"

s = swift_path.read_text()
router = router_path.read_text()
v07 = v07_path.read_text()
ui = modern_ui_path.read_text()

# ----- version -----
s = s.replace(
    "Next Agent 0.7.15 is ready with an in-app HUD verification probe and SpringBoard scene-manager recovery for app launches.",
    "Next Agent 0.7.16 is ready with a standalone system-wide HUD tweak and reliable full-screen app automation."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.15-hudprobe-scenes9"',
    'private static let currentToolSchemaVersion = "0.7.16-hudtweak-fullscreen10"'
)
s = s.replace('"client_version": "0.7.15"', '"client_version": "0.7.16"')

router = router.replace(
    '"router_version": "0.7.15-hudprobe-scenes9"',
    '"router_version": "0.7.16-hudtweak-fullscreen10"'
)
router = router.replace(
    'transportVersion == "0.7.15-cfmessageport1"',
    'transportVersion == "0.7.16-cfmessageport1"'
)
router = router.replace(
    'ocrTransportVersion == "0.7.15-springboard-vision1"',
    'ocrTransportVersion == "0.7.16-springboard-vision1"'
)
router = router.replace(
    'splitBridgeVersion == "0.7.15"',
    'splitBridgeVersion == "0.7.16"'
)
router = router.replace(
    'hidBridgeVersion == "0.7.15"',
    'hidBridgeVersion == "0.7.16"'
)
router = router.replace(
    'hudBridgeVersion == "0.7.15"',
    'hudBridgeVersion == "0.7.16"'
)
v07 = v07.replace(
    '"input_path": "springboard_iohid_v0715"',
    '"input_path": "springboard_iohid_v0716"'
)

# ----- normal app launch is full-screen again -----
# Split hosting stays available only through the explicit split_open action.
route_start = router.find('        case "open_bundle":')
route_end = router.find('        case "open_sequence":', route_start)
if route_start < 0 or route_end < 0:
    raise SystemExit("v0.7.16 app-route bounds missing")
new_routes = '''        case "open_bundle":
            guard let bundleID = args["bundle_id"] as? String else { return routerBadArgs() }
            _ = NAScreenBridgeClient.closeSplitWorkspace()
            return await execute(
                "open_app",
                arguments: ["bundle_id": bundleID],
                allowSensitive: allowSensitive
            )
        case "open_name":
            guard let appName = args["name"] as? String else { return routerBadArgs() }
            _ = NAScreenBridgeClient.closeSplitWorkspace()
            return await execute(
                "open_app_by_name",
                arguments: ["name": appName],
                allowSensitive: allowSensitive
            )
'''
router = router[:route_start] + new_routes + router[route_end:]

router = router.replace(
    '"Application/router tool. open_bundle and open_name now open the target inside the SpringBoard-hosted 50/50 workspace so Next Agent stays foreground. Use foreground_open_* only when the user explicitly wants to leave Next Agent and view one app full-screen."',
    '"Application/router tool. open_bundle and open_name launch the requested app normally in full-screen. split_open is an explicit diagnostic/special workspace action only; never use split mode for routine app automation."'
)

old_policy = '''              For any interactive task in another app, phone_apps open_name/open_bundle now automatically creates the split workspace; do not use the foreground_open_* actions unless the user explicitly asked to leave Next Agent and view only that app. After the split opens, use phone_screen OCR/describe/find_text before every coordinate-sensitive step. The OCR path is SpringBoard-native and must return actual text observations; do not treat a successful screenshot alone as vision success. Close the split workspace when the task is complete.
'''
new_policy = '''              For routine interactive tasks in another app, use phone_apps open_name/open_bundle to launch that app normally full-screen, then use phone_screen OCR and SpringBoard HID. Do not use split_open unless the user explicitly asks for split workspace testing. The system-wide HUD tweak provides task status across apps, so split hosting is not needed to keep status visible. Before every coordinate-sensitive step, use OCR/describe/find_text and verify the expected visible result.
'''
if old_policy in s:
    s = s.replace(old_policy, new_policy, 1)

# ----- stale split cleanup at the start of every new user task -----
send_marker = '''        input = ""
        messages.append(ChatMessage(role: "user", text: text))
'''
if send_marker not in s:
    raise SystemExit("v0.7.16 send marker missing")
s = s.replace(
    send_marker,
    '''        _ = NAScreenBridgeClient.closeSplitWorkspace()
        input = ""
        messages.append(ChatMessage(role: "user", text: text))
''',
    1
)

# ----- user-visible HUD controls -----
progress_marker = '''    private func publishProgress(state progressState: String, message: String, progress: Double, returnToApp: Bool) {
'''
if progress_marker not in s:
    raise SystemExit("v0.7.16 publishProgress marker missing")
hud_methods = '''    func testSystemHUD() {
        _ = NAScreenBridgeClient.closeSplitWorkspace()
        status = "Testing system-wide HUD…"
        publishProgress(
            state: "working",
            message: "HUD test • visible system-wide",
            progress: 0.42,
            returnToApp: false
        )

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard let self else { return }
            self.publishProgress(
                state: "complete",
                message: "HUD test complete",
                progress: 1.0,
                returnToApp: false
            )
            self.status = "HUD test complete"
        }
    }

    func clearWorkspaceOverlay() {
        let result = NAScreenBridgeClient.closeSplitWorkspace()
        status = (result["success"] as? Bool) == true
            ? "Split overlay cleared"
            : "Split overlay reset requested"
    }

'''
s = s.replace(progress_marker, hud_methods + progress_marker, 1)

# Quick Actions: add a second row with explicit HUD and workspace-reset controls.
quick_marker = '''                actionTile("Apps", "square.grid.2x2.fill", NATheme.violet) {
                    run("List installed apps with names and bundle identifiers.")
                }
            }
'''
quick_replacement = '''                actionTile("Apps", "square.grid.2x2.fill", NATheme.violet) {
                    run("List installed apps with names and bundle identifiers.")
                }
            }

            HStack(spacing: 10) {
                actionTile("Show HUD", "rectangle.topthird.inset.filled", NATheme.cyan) {
                    state.testSystemHUD()
                }
                actionTile("Clear Split", "rectangle.split.1x2.slash.fill", NATheme.orange) {
                    state.clearWorkspaceOverlay()
                }
            }
'''
if quick_marker not in ui:
    raise SystemExit("v0.7.16 quick-action marker missing")
ui = ui.replace(quick_marker, quick_replacement, 1)

# Settings also exposes the HUD test so it is easy to verify the tweak independently.
settings_anchor = '''                    settingsSection("OPENAI AGENT") {
'''
settings_section = '''                    settingsSection("SYSTEM-WIDE HUD") {
                        Button {
                            state.testSystemHUD()
                        } label: {
                            label(
                                "Show HUD Test",
                                detail: "Displays the standalone RootHide HUD tweak in Next Agent. The same HUD follows active tasks into other UIKit apps.",
                                icon: "rectangle.topthird.inset.filled",
                                color: NATheme.cyan
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            state.clearWorkspaceOverlay()
                        } label: {
                            label(
                                "Clear Split Overlay",
                                detail: "Emergency cleanup for any stale experimental split-workspace window.",
                                icon: "rectangle.split.1x2.slash.fill",
                                color: NATheme.orange
                            )
                        }
                        .buttonStyle(.plain)
                    }

'''
if settings_anchor not in ui:
    raise SystemExit("v0.7.16 settings anchor missing")
ui = ui.replace(settings_anchor, settings_section + settings_anchor, 1)

ui = ui.replace(
    "0.7.15 • RootHide • HUD Probe • Scene Recovery",
    "0.7.16 • RootHide • System HUD Tweak • Full-Screen Apps"
)

swift_path.write_text(s)
router_path.write_text(router)
v07_path.write_text(v07)
modern_ui_path.write_text(ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.15", "MARKETING_VERSION: 0.7.16")
y = y.replace("CURRENT_PROJECT_VERSION: 23", "CURRENT_PROJECT_VERSION: 24")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.16"
d["CFBundleVersion"] = "24"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.16-hudtweak-fullscreen10"' in swift_path.read_text()
assert '"router_version": "0.7.16-hudtweak-fullscreen10"' in router_path.read_text()
assert "testSystemHUD()" in swift_path.read_text()
assert 'actionTile("Show HUD"' in modern_ui_path.read_text()
assert 'settingsSection("SYSTEM-WIDE HUD")' in modern_ui_path.read_text()
assert 'return await execute(\n                "open_app",' in router_path.read_text()
assert "MARKETING_VERSION: 0.7.16" in project.read_text()
