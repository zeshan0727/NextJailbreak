from pathlib import Path
import plistlib

root = Path(".")
swift_path = root / "NextAgent/NextAgent.swift"
router_path = root / "NextAgent/V071Router.swift"
modern_ui_path = root / "NextAgent/ModernUI.swift"

s = swift_path.read_text()
router = router_path.read_text()
ui = modern_ui_path.read_text()

# ----- version -----
s = s.replace(
    "Next Agent 0.7.9 is ready with a generation-locked SpringBoard OCR bridge and enforced split workspace.",
    "Next Agent 0.7.10 is ready with asynchronous split workspace, resilient OCR, and System / Light / Dark appearance."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.9-sbocr-split3"',
    'private static let currentToolSchemaVersion = "0.7.10-sbocr-split4"'
)
s = s.replace('"client_version": "0.7.9"', '"client_version": "0.7.10"')
router = router.replace(
    '"router_version": "0.7.9-sbocr-split3"',
    '"router_version": "0.7.10-sbocr-split4"'
)
router = router.replace(
    'transportVersion == "0.7.9-cfmessageport1"',
    'transportVersion == "0.7.10-cfmessageport1"'
)
router = router.replace(
    'ocrTransportVersion == "0.7.9-springboard-vision1"',
    'ocrTransportVersion == "0.7.10-springboard-vision1"'
)
router = router.replace(
    'splitBridgeVersion == "0.7.9"',
    'splitBridgeVersion == "0.7.10"'
)

# ----- asynchronous split open: acknowledge immediately, then poll status -----
route_marker = '''    @MainActor
    private func routeApps(_ args: [String: Any], allowSensitive: Bool) async -> ToolResult {
'''
helper = '''    @MainActor
    private func openSplitWorkspaceAndWait(_ bundleID: String) async -> ToolResult {
        let accepted = NAScreenBridgeClient.openSplitWorkspace(secondary: bundleID)
        guard (accepted["success"] as? Bool) == true else {
            return routerJSON(accepted)
        }

        let deadline = Date().addingTimeInterval(9.0)
        repeat {
            let status = NAScreenBridgeClient.splitWorkspaceStatus()
            if (status["active"] as? Bool) == true,
               (status["secondary_host_ready"] as? Bool) == true {
                return routerJSON(status)
            }

            let opening = (status["opening"] as? Bool) ?? false
            let error = status["last_error"] as? String ?? ""
            if !opening && !error.isEmpty {
                return ToolResult(success: false, output: String(describing: status))
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        } while Date() < deadline

        let finalStatus = NAScreenBridgeClient.splitWorkspaceStatus()
        return ToolResult(
            success: false,
            output: "Split workspace timed out waiting for the target scene. Status: \\(finalStatus)"
        )
    }

'''
if route_marker not in router:
    raise SystemExit("v0.7.10 routeApps marker missing")
router = router.replace(route_marker, helper + route_marker, 1)

router = router.replace(
    'return routerJSON(NAScreenBridgeClient.openSplitWorkspace(secondary: bundleID))',
    'return await openSplitWorkspaceAndWait(bundleID)'
)
router = router.replace(
    'let response = NAScreenBridgeClient.openSplitWorkspace(secondary: secondary)\n            return routerJSON(response)',
    'return await openSplitWorkspaceAndWait(secondary)'
)

# ----- appearance system -----
old_theme = '''import SwiftUI
import UIKit

enum NATheme {
    static let cyan = Color(red: 0.03, green: 0.82, blue: 1.00)
    static let blue = Color(red: 0.12, green: 0.35, blue: 1.00)
    static let violet = Color(red: 0.50, green: 0.24, blue: 1.00)
    static let green = Color(red: 0.15, green: 0.92, blue: 0.54)
    static let pink = Color(red: 1.00, green: 0.23, blue: 0.62)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.13)
    static let panel = Color.white.opacity(0.075)
    static let stroke = Color.white.opacity(0.12)
    static let secondary = Color.white.opacity(0.62)
    static let background = LinearGradient(
        colors: [
            Color(red: 0.015, green: 0.025, blue: 0.055),
            Color(red: 0.015, green: 0.055, blue: 0.105),
            Color.black
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let accent = LinearGradient(colors: [cyan, blue, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
}
'''
new_theme = '''import SwiftUI
import UIKit

enum NAAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum NATheme {
    static let cyan = Color(red: 0.03, green: 0.82, blue: 1.00)
    static let blue = Color(red: 0.12, green: 0.35, blue: 1.00)
    static let violet = Color(red: 0.50, green: 0.24, blue: 1.00)
    static let green = Color(red: 0.15, green: 0.92, blue: 0.54)
    static let pink = Color(red: 1.00, green: 0.23, blue: 0.62)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.13)
    static let panel = Color(uiColor: .secondarySystemBackground).opacity(0.88)
    static let stroke = Color(uiColor: .separator).opacity(0.58)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let divider = Color(uiColor: .separator)
    static let field = Color(uiColor: .tertiarySystemBackground)
    static let background = LinearGradient(
        colors: [
            Color(uiColor: .systemBackground),
            Color(uiColor: .secondarySystemBackground),
            Color(uiColor: .systemBackground)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let accent = LinearGradient(colors: [cyan, blue, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
}
'''
if old_theme not in ui:
    raise SystemExit("v0.7.10 theme block missing")
ui = ui.replace(old_theme, new_theme, 1)

# Root selection follows System by default and can force Light/Dark.
root_marker = '''struct ModernRootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\\.scenePhase) private var scenePhase
'''
root_replacement = '''struct ModernRootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\\.scenePhase) private var scenePhase
    @AppStorage("nextagent.appearance") private var appearance = NAAppearance.system.rawValue
'''
if root_marker not in ui:
    raise SystemExit("v0.7.10 ModernRootView marker missing")
ui = ui.replace(root_marker, root_replacement, 1)
ui = ui.replace(
    '        .preferredColorScheme(.dark)',
    '        .preferredColorScheme(NAAppearance(rawValue: appearance)?.colorScheme)',
    1
)

# Adaptive text/cards in places that were dark-only.
ui = ui.replace('Divider().overlay(Color.white.opacity(0.10))', 'Divider().overlay(NATheme.divider)')
ui = ui.replace(
    '''Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)''',
    '''Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)'''
)
ui = ui.replace(
    '''Text(tool.title)
                                        .font(.headline)
                                        .foregroundStyle(.white)''',
    '''Text(tool.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)'''
)
ui = ui.replace(
    '''Text(item.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.white)''',
    '''Text(item.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)'''
)
ui = ui.replace(
    '.background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))',
    '.background(NATheme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))'
)
ui = ui.replace(
    '''Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)''',
    '''Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)'''
)
ui = ui.replace(
    '.background(Color.black)\n                    .navigationTitle(selectedName)',
    '.background(Color(uiColor: .systemBackground))\n                    .navigationTitle(selectedName)'
)
ui = ui.replace(
    '                    .preferredColorScheme(.dark)\n',
    ''
)

# Settings appearance control.
settings_marker = '''struct ModernSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var showAPIKey = false
'''
settings_replacement = '''struct ModernSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var showAPIKey = false
    @AppStorage("nextagent.appearance") private var appearance = NAAppearance.system.rawValue
'''
if settings_marker not in ui:
    raise SystemExit("v0.7.10 settings state marker missing")
ui = ui.replace(settings_marker, settings_replacement, 1)

connection_marker = '''                    settingsSection("CONNECTION") {
'''
appearance_section = '''                    settingsSection("APPEARANCE") {
                        label(
                            "App Theme",
                            detail: appearance == NAAppearance.system.rawValue
                                ? "Follows your iPhone Light / Dark appearance automatically"
                                : "Override the iPhone appearance for Next Agent",
                            icon: "circle.lefthalf.filled",
                            color: NATheme.violet
                        )

                        Picker("Appearance", selection: $appearance) {
                            ForEach(NAAppearance.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Next Agent appearance")
                    }

'''
if connection_marker not in ui:
    raise SystemExit("v0.7.10 settings connection marker missing")
ui = ui.replace(connection_marker, appearance_section + connection_marker, 1)

ui = ui.replace(
    "0.7.9 • RootHide • Locked Bridge • SpringBoard OCR",
    "0.7.10 • RootHide • Async Split • System Theme"
)

swift_path.write_text(s)
router_path.write_text(router)
modern_ui_path.write_text(ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.9", "MARKETING_VERSION: 0.7.10")
y = y.replace("CURRENT_PROJECT_VERSION: 17", "CURRENT_PROJECT_VERSION: 18")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.10"
d["CFBundleVersion"] = "18"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.10-sbocr-split4"' in swift_path.read_text()
assert "openSplitWorkspaceAndWait" in router_path.read_text()
assert 'transportVersion == "0.7.10-cfmessageport1"' in router_path.read_text()
assert 'NAAppearance.system.rawValue' in modern_ui_path.read_text()
assert 'Picker("Appearance"' in modern_ui_path.read_text()
assert "MARKETING_VERSION: 0.7.10" in project.read_text()
