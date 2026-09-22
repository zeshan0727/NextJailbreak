from pathlib import Path
import plistlib
import re

ROOT = Path("lara-src")

# Rebrand build metadata without touching the exploit/decrypt implementation.
pbx = ROOT / "lara.xcodeproj" / "project.pbxproj"
s = pbx.read_text()
s = s.replace("com.roooot.lara", "cn.gblw.AppsDump.DarkSword")
s = re.sub(r"MARKETING_VERSION = [^;]+;", "MARKETING_VERSION = 4.1.0;", s)
pbx.write_text(s)

info = ROOT / "lara" / "Info.plist"
with info.open("rb") as f:
    p = plistlib.load(f)
p["CFBundleDisplayName"] = "AppsDump DS"
p["CFBundleName"] = "AppsDump DS"
p["UIFileSharingEnabled"] = True
with info.open("wb") as f:
    plistlib.dump(p, f, fmt=plistlib.FMT_XML, sort_keys=False)

# Focus the app on the DarkSword + app-decrypt path needed by AppsDump.
content = r'''import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var mgr: laramgr
    @State private var fetchingKernelcache = false
    @State private var showLogs = false

    private var osText: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("System", value: osText)
                    LabeledContent("DarkSword") {
                        statusView(ready: mgr.dsready, running: mgr.dsrunning, failed: mgr.dsfailed)
                    }
                    LabeledContent("Kernel offsets") {
                        Image(systemName: mgr.hasOffsets ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(mgr.hasOffsets ? .green : .secondary)
                    }
                    LabeledContent("Sandbox") {
                        statusView(ready: mgr.sbxready, running: mgr.sbxrunning, failed: mgr.sbxfailed)
                    }
                } header: {
                    Label("AppsDump DarkSword", systemImage: "shield.lefthalf.filled")
                } footer: {
                    Text("iOS 17 test backend. DarkSword provides kernel read/write; the sandbox escape exposes installed app bundles; the decrypt engine copies decrypted executable pages into an IPA.")
                }

                Section("Setup") {
                    Button {
                        offsets_init()
                        mgr.run()
                    } label: {
                        HStack {
                            Label(mgr.dsready ? "DarkSword Ready" : "1. Run DarkSword", systemImage: "bolt.shield")
                            Spacer()
                            if mgr.dsrunning {
                                Text("\(Int(mgr.dsprogress * 100))%")
                                    .foregroundStyle(.secondary)
                                ProgressView()
                            }
                        }
                    }
                    .disabled(mgr.dsready || mgr.dsrunning || isdebugged())

                    if !mgr.hasOffsets {
                        Button {
                            guard !fetchingKernelcache else { return }
                            fetchingKernelcache = true
                            DispatchQueue.global(qos: .userInitiated).async {
                                let fetched = fetchkcache()
                                let loaded = fetched ? dlkcache() : false
                                DispatchQueue.main.async {
                                    mgr.hasOffsets = loaded
                                    fetchingKernelcache = false
                                }
                            }
                        } label: {
                            HStack {
                                Label("2. Fetch Kernel Offsets", systemImage: "arrow.down.circle")
                                Spacer()
                                if fetchingKernelcache { ProgressView() }
                            }
                        }
                        .disabled(!mgr.dsready || fetchingKernelcache)
                    }

                    Button {
                        mgr.sbxescape()
                    } label: {
                        HStack {
                            Label(mgr.sbxready ? "Sandbox Escaped" : "3. Escape Sandbox", systemImage: "lock.open")
                            Spacer()
                            if mgr.sbxrunning { ProgressView() }
                        }
                    }
                    .disabled(!mgr.dsready || !mgr.hasOffsets || mgr.sbxready || mgr.sbxrunning)
                }

                Section("Dump Apps") {
                    NavigationLink {
                        DecryptView()
                    } label: {
                        Label("Installed Apps", systemImage: "square.stack.3d.up")
                    }
                    .disabled(!mgr.dsready || !mgr.sbxready)

                    if !mgr.sbxready {
                        Text("Run the three setup steps first. Once ready, AppsDump will list installed apps and export decrypted IPAs through the share sheet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Safety") {
                    Label("Do not force-close AppsDump while DarkSword kernel access is active. Use a normal reboot if the exploit becomes unstable.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Section {
                    Button(showLogs ? "Hide Logs" : "Show Logs") {
                        showLogs.toggle()
                    }
                    if showLogs {
                        ScrollView {
                            Text(mgr.log.isEmpty ? "No logs yet." : mgr.log)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 140, maxHeight: 280)
                    }
                } header: {
                    Label("Diagnostics", systemImage: "terminal")
                }
            }
            .navigationTitle("AppsDump DS")
        }
    }

    @ViewBuilder
    private func statusView(ready: Bool, running: Bool, failed: Bool) -> some View {
        if ready {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if running {
            ProgressView()
        } else if failed {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else {
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }
}
'''
(ROOT / "lara" / "views" / "app" / "ContentView.swift").write_text(content)

# Keep Lara's proven initialization code, but remove toolbox tabs so the test
# build opens directly to the AppsDump flow.
main = r'''import SwiftUI
import UniformTypeIdentifiers

enum taboptions { case applying, tweaks, files, logs }
let g_isunsupported: Bool = isunsupported()
var weonadebugbuild_pjbweouttahereexclamationmark: Bool = false

@main
struct lara: App {
    @StateObject private var mgr = laramgr.shared
    @Environment(\.scenePhase) private var scenephase
    @AppStorage("keepAlive") private var keepalive: Bool = false

    init() {
        #if DEBUG
        weonadebugbuild_pjbweouttahereexclamationmark = true
        #endif
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        if keepalive { toggleka() }
        globallogger.capture()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mgr)
                .onAppear {
                    if !isunsupported() {
                        init_offsets()
                        offsets_init()
                        mgr.hasOffsets = emergencyfixfunctiontobereplacedlateronquestionmark()
                    } else {
                        Alertinator.shared.alert(
                            title: "Unsupported device",
                            body: "This DarkSword test build targets supported iOS 17 devices. A19/M5 and patched iOS builds are not supported.",
                            actionLabel: "Exit App",
                            action: { exitinator() }
                        )
                    }
                }
                .onChange(of: scenephase) { phase in
                    if phase == .active { globallogger.capture() }
                    else { globallogger.stopcapture() }
                }
        }
    }
}

extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

extension String: @retroactive Error {}
'''
(ROOT / "lara" / "lara.swift").write_text(main)

print("AppsDump DarkSword patches applied")
