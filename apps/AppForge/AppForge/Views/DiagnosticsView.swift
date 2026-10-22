import SwiftUI
import UniformTypeIdentifiers

/// Accessible from both Code and Build. The user chooses a local .ips file in Files.
struct DiagnosticsView: View {
    @EnvironmentObject private var state: AppState
    @State private var importing = false

    var body: some View {
        List {
            Section {
                Text("Import an iOS crash report from Files. AppForge reads it locally, identifies missing permissions, and can rebuild the selected project.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    importing = true
                } label: {
                    Label("Import .ips / .crash / .txt", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Crash report")
            } footer: {
                Text("On iPhone: Settings → Privacy & Security → Analytics & Improvements → Analytics Data → choose your app crash → Share → Save to Files. Then import it here.")
            }
            if let crash = state.importedCrash {
                Section("Diagnosis") {
                    LabeledContent("App", value: crash.appName)
                    if !crash.bundleID.isEmpty {
                        LabeledContent("Bundle ID", value: crash.bundleID)
                    }
                    Text(crash.cause).textSelection(.enabled)
                    if let key = crash.usageKey {
                        Label("Automatic Info.plist fix available: \(key)", systemImage: "checkmark.shield.fill")
                            .font(.footnote).foregroundStyle(.green)
                    } else {
                        Text("No known deterministic fix. AI will review the sanitized crash summary and generated Swift source.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Selected project") {
                    if let project = state.project {
                        Text("\(project.appName) • \(project.bundleId)")
                        if !crash.bundleID.isEmpty &&
                            crash.bundleID.caseInsensitiveCompare(project.bundleId) != .orderedSame {
                            Label("This report belongs to a different app. Load the matching project in Code first.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("No generated project loaded. Create or restore the app in Code first.")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Button {
                        Task { await state.repairImportedCrash(build: false) }
                    } label: {
                        Label("Apply Fix to Code", systemImage: "wand.and.stars")
                    }
                    .disabled(state.busyFix || !state.canRepairImportedCrash)
                    Button {
                        Task { await state.repairImportedCrash(build: true) }
                    } label: {
                        HStack {
                            Label("Fix & Push New IPA Build", systemImage: "hammer.fill")
                            if state.busyFix { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(state.busyFix || state.busyPush || !state.canRepairImportedCrash)
                    if !state.repairStatus.isEmpty {
                        Text(state.repairStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Crash Diagnostics")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? 0) < 3_000_000 else {
                    throw ForgeError.message("Crash report exceeds the 3 MB safety limit.")
                }
                let data = try Data(contentsOf: url)
                guard let report = String(data: data, encoding: .utf8) else {
                    throw ForgeError.message("Crash report must contain UTF-8 text.")
                }
                state.loadCrashReport(report)
            } catch {
                state.notice = error.localizedDescription
            }
        }
    }
}
