from pathlib import Path
import plistlib

root = Path(".")
swift_path = root / "NextAgent/NextAgent.swift"
screen_path = root / "NextAgent/ScreenVision.swift"
router_path = root / "NextAgent/V071Router.swift"

s = swift_path.read_text()
screen = screen_path.read_text()
router = router_path.read_text()

s = s.replace(
    "Next Agent 0.7.4 is ready with SpringBoard-held background protection, visible progress, and real-screen capture.",
    "Next Agent 0.7.5 is ready with IOSurface real-screen capture, a system-level progress pill, and stricter background vision."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.4-screenbridge1"',
    'private static let currentToolSchemaVersion = "0.7.5-iosurface1"'
)
s = s.replace('"client_version": "0.7.4"', '"client_version": "0.7.5"')

old_capture = '''    func captureScreen() -> UIImage? {
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
'''
new_capture = '''    func captureScreen() -> UIImage? {
        if let image = captureFromSpringBoard() {
            return image
        }

        // Never pretend the backgrounded Next Agent window is the current
        // foreground screen. That false-positive was enough for Astra to plan
        // taps against stale/incorrect pixels after launching another app.
        guard UIApplication.shared.applicationState == .active else {
            lastCaptureSource = "springboard_capture_failed_background"
            return nil
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
            lastCaptureSource = "nextagent_foreground_fallback"
        } else {
            lastCaptureSource = "capture_failed"
        }
        return result
    }
'''
if old_capture not in screen:
    raise SystemExit("v0.7.5 ScreenVision capture marker missing")
screen = screen.replace(old_capture, new_capture, 1)

# The direct self-test must prove the bridge can capture through SpringBoard,
# not merely that the injected overlay wrote its status file.
old_overlay_test = '''        let overlay = RootDaemonClient.request(action: "overlay_status")
        results.append([
            "tool": "springboard_overlay",
            "success": overlay.success,
            "output": String(overlay.output.prefix(1200))
        ])

        for (toolName, args) in checks {
'''
new_overlay_test = '''        let overlay = RootDaemonClient.request(action: "overlay_status")
        results.append([
            "tool": "springboard_overlay",
            "success": overlay.success,
            "output": String(overlay.output.prefix(1200))
        ])

        let realScreen = RootDaemonClient.request(action: "screen_capture_real")
        results.append([
            "tool": "real_screen_bridge",
            "success": realScreen.success,
            "output": String(realScreen.output.prefix(1600))
        ])

        for (toolName, args) in checks {
'''
if old_overlay_test not in router:
    raise SystemExit("v0.7.5 router overlay self-test marker missing")
router = router.replace(old_overlay_test, new_overlay_test, 1)

# Make the model treat a real-screen failure as a blocking diagnostic condition,
# never as permission to continue with guessed coordinates.
instruction = '''              After opening an app, allow it a short moment to render, then use phone_screen action=describe/find_text before the next interaction. If screen vision fails, do not treat the app launch as task completion. Report the actual screen-capture/OCR failure. For Notes tasks, opening Notes alone is never success when the user also requested creating or typing a note.
'''
replacement = instruction + '''              When phone_screen reports source=springboard_capture_failed_background or a real-screen bridge failure, stop coordinate interaction for that step and report the capture failure rather than guessing. A screenshot from Next Agent's own backgrounded window is never valid evidence of another foreground app.
'''
if instruction not in s:
    raise SystemExit("v0.7.5 instruction marker missing")
s = s.replace(instruction, replacement, 1)

swift_path.write_text(s)
screen_path.write_text(screen)
router_path.write_text(router)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.4", "MARKETING_VERSION: 0.7.5")
y = y.replace("CURRENT_PROJECT_VERSION: 12", "CURRENT_PROJECT_VERSION: 13")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.5"
d["CFBundleVersion"] = "13"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.5-iosurface1"' in swift_path.read_text()
assert "springboard_capture_failed_background" in screen_path.read_text()
assert "real_screen_bridge" in router_path.read_text()
assert "MARKETING_VERSION: 0.7.5" in project.read_text()
