from pathlib import Path
import plistlib

root = Path(".")
swift_path = root / "NextAgent/NextAgent.swift"
screen_path = root / "NextAgent/ScreenVision.swift"
router_path = root / "NextAgent/V071Router.swift"

s = swift_path.read_text()
screen = screen_path.read_text()
router = router_path.read_text()

# Version/session schema.
s = s.replace(
    "Next Agent 0.7.3 is ready with daemon-held background protection and floating SpringBoard progress.",
    "Next Agent 0.7.4 is ready with SpringBoard-held background protection, visible progress, and real-screen capture."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.3-daemonpin1"',
    'private static let currentToolSchemaVersion = "0.7.4-screenbridge1"'
)
s = s.replace('"client_version": "0.7.3"', '"client_version": "0.7.4"')

# SpringBoard protection handshake. v0.7.3 published progress before this method,
# so the overlay already knows our PID when we wait for its RBS assertion.
old = '''        let daemonPinned = RootDaemonClient.request(action: "protect_pid", argument: pid)
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
'''
new = '''        let daemonPinned = RootDaemonClient.request(action: "protect_pid", argument: pid)
        let overlayStatus = RootDaemonClient.request(action: "overlay_status")
        let springBoardPinned = overlayStatus.success
            ? RootDaemonClient.request(action: "overlay_wait_pin", argument: pid)
            : ToolResult(success: false, output: overlayStatus.output)
        let localPinned = NABackgroundAssertionController.shared().start()
        let extended = BackgroundKeepAlive.shared.start()

        if springBoardPinned.success {
            backgroundState = "SpringBoard pinned"
        } else if daemonPinned.success {
            backgroundState = "Daemon pinned"
        } else if localPinned {
            backgroundState = "Pinned background"
        } else if extended {
            backgroundState = "Extended background"
        } else {
            backgroundState = "Protection unavailable"
        }
'''
if old not in s:
    raise SystemExit("v0.7.4 background handshake marker missing")
s = s.replace(old, new, 1)

# When the UIKit background assertion expires, report SpringBoard state first.
old = '''                    let daemonStatus = RootDaemonClient.request(action: "protection_status")
                    if daemonStatus.success {
                        self.backgroundState = "Daemon pinned"
                    } else if NABackgroundAssertionController.shared().isValid {
'''
new = '''                    let overlayPin = RootDaemonClient.request(action: "overlay_wait_pin", argument: String(getpid()))
                    let daemonStatus = RootDaemonClient.request(action: "protection_status")
                    if overlayPin.success {
                        self.backgroundState = "SpringBoard pinned"
                    } else if daemonStatus.success {
                        self.backgroundState = "Daemon pinned"
                    } else if NABackgroundAssertionController.shared().isValid {
'''
if old not in s:
    raise SystemExit("v0.7.4 expiration status marker missing")
s = s.replace(old, new, 1)

# Explicit model requirement: app launch is only the first step.
needle = '''              Opening an app is NOT completion when the user asked to do something inside that app. After opening the target app, continue the same turn with phone_screen and phone_input until every requested step is completed or a tool returns a real failure. For example, "open Notes, create a note, and type text" must continue after Notes launches: inspect the Notes screen, locate/create the note, focus the editor, type the requested text, then verify the visible result before reporting success.
'''
replacement = needle + '''              After opening an app, allow it a short moment to render, then use phone_screen action=describe/find_text before the next interaction. If screen vision fails, do not treat the app launch as task completion. Report the actual screen-capture/OCR failure. For Notes tasks, opening Notes alone is never success when the user also requested creating or typing a note.
'''
if needle not in s:
    raise SystemExit("v0.7.4 instruction marker missing")
s = s.replace(needle, replacement, 1)

# Prefer SpringBoard real-screen capture before any app-local private API.
old_capture = '''    func captureScreen() -> UIImage? {
        var result: UIImage?
        let block = {
            result = self.captureOnMainThread()
        }
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
        return result
    }
'''
new_capture = '''    private(set) var lastCaptureSource = "none"

    func captureScreen() -> UIImage? {
        if let image = captureFromSpringBoard() {
            return image
        }

        var result: UIImage?
        let block = {
            result = self.captureOnMainThread()
        }
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
        if result != nil {
            lastCaptureSource = "app_fallback"
        }
        return result
    }

    private func captureFromSpringBoard() -> UIImage? {
        let result = RootDaemonClient.request(action: "screen_capture_real")
        guard result.success,
              let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["success"] as? Bool) == true,
              let path = json["path"] as? String,
              let image = UIImage(contentsOfFile: path) else {
            return nil
        }

        lastCaptureSource = (json["source"] as? String) ?? "springboard"
        return image
    }
'''
if old_capture not in screen:
    raise SystemExit("v0.7.4 ScreenVision capture marker missing")
screen = screen.replace(old_capture, new_capture, 1)

# Screen capture tool result includes the real source so failures are diagnosable.
old_meta = '''        return v07JSON(["success": true, "capture": metadata])
'''
new_meta = '''        return v07JSON([
            "success": true,
            "source": NAScreenVision.shared.lastCaptureSource,
            "capture": metadata
        ])
'''
if old_meta not in (root / "NextAgent/V07Tools.swift").read_text():
    raise SystemExit("v0.7.4 V07 screen metadata marker missing")
v07 = (root / "NextAgent/V07Tools.swift").read_text().replace(old_meta, new_meta, 1)
(root / "NextAgent/V07Tools.swift").write_text(v07)

# Direct self-test must verify the SpringBoard overlay is actually injected.
old_loop = '''        var results: [[String: Any]] = []
        for (toolName, args) in checks {
'''
new_loop = '''        var results: [[String: Any]] = []

        let overlay = RootDaemonClient.request(action: "overlay_status")
        results.append([
            "tool": "springboard_overlay",
            "success": overlay.success,
            "output": String(overlay.output.prefix(1200))
        ])

        for (toolName, args) in checks {
'''
if old_loop not in router:
    raise SystemExit("v0.7.4 router self-test marker missing")
router = router.replace(old_loop, new_loop, 1)
router = router.replace(
    'let passed = results.filter { ($0["success"] as? Bool) == true }.count',
    'let passed = results.filter { ($0["success"] as? Bool) == true }.count',
    1
)

swift_path.write_text(s)
screen_path.write_text(screen)
router_path.write_text(router)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.3", "MARKETING_VERSION: 0.7.4")
y = y.replace("CURRENT_PROJECT_VERSION: 11", "CURRENT_PROJECT_VERSION: 12")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.4"
d["CFBundleVersion"] = "12"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.4-screenbridge1"' in swift_path.read_text()
assert "captureFromSpringBoard" in screen_path.read_text()
assert "springboard_overlay" in router_path.read_text()
assert "MARKETING_VERSION: 0.7.4" in project.read_text()
