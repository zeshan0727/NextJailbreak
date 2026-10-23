import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Accessible from both Code and Build. The user chooses a local .ips file in Files.
struct DiagnosticsView: View {
    @EnvironmentObject private var state: AppState
    @State private var importing = false
    @State private var pasteExpanded = false
    @State private var pastedReport = ""
    @State private var pickerError: String?
    private let maxBytes = 8_000_000

    private var supportedTypes: [UTType] {
        // Some iOS .ips files arrive from Files with a generic data type.
        // Accept both recognized extensions and broad document/data providers.
        var types: [UTType] = [.data, .plainText, .json, .content]
        for ext in ["ips", "crash", "log", "txt", "panic"] {
            if let type = UTType(filenameExtension: ext, conformingTo: .data) {
                types.append(type)
            }
        }
        return types
    }

    private func importURL(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let coordinator = NSFileCoordinator()
        var coordinateError: NSError?
        var readError: Error?
        var contents: Data?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinateError) { coordinatedURL in
            do {
                let size = try coordinatedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= maxBytes else {
                    throw ForgeError.message("Crash report exceeds 8 MB. Export the .ips report as text instead.")
                }
                contents = try Data(contentsOf: coordinatedURL)
            } catch {
                readError = error
            }
        }
        if let error = coordinateError ?? (readError as NSError?) {
            pickerError = "File access failed: \(error.localizedDescription)"
            return
        }
        guard let contents else {
            pickerError = "The file is not available locally. Save it to On My iPhone → Downloads and try again."
            return
        }
        guard contents.count <= maxBytes else {
            pickerError = "Crash report exceeds 8 MB."
            return
        }
        guard let report = String(data: contents, encoding: .utf8)
                ?? String(data: contents, encoding: .utf16) else {
            pickerError = "This file is not readable text. Import the original .ips/.crash report."
            return
        }
        pickerError = nil
        state.loadCrashReport(report)
    }

    var body: some View {
        List {
            Section {
                Text("Import an iOS crash report from Files. AppForge reads it locally, identifies missing permissions, and can rebuild the selected project.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    pickerError = nil
                    importing = true
                } label: {
                    Label("Choose Crash File (.ips/.crash/.txt)", systemImage: "folder")
                }
                Button {
                    guard let report = UIPasteboard.general.string, !report.isEmpty else {
                        pickerError = "No crash report text on the clipboard."
                        return
                    }
                    pickerError = nil
                    state.loadCrashReport(report)
                } label: {
                    Label("Import Copied Crash Text", systemImage: "doc.on.clipboard")
                }
                DisclosureGroup(isExpanded: $pasteExpanded) {
                    TextEditor(text: $pastedReport)
                        .frame(height: 170)
                        .font(.system(size: 12, design: .monospaced))
                        .border(.secondary.opacity(0.35))
                    Button("Analyze Pasted Crash Report") {
                        let size = pastedReport.utf8.count
                        guard size > 0 && size <= maxBytes else {
                            pickerError = "Paste a crash report no larger than 8 MB."
                            return
                        }
                        pickerError = nil
                        state.loadCrashReport(pastedReport)
                        pasteExpanded = false
                    }
                } label: {
                    Label("Paste Crash Log Manually", systemImage: "text.alignleft")
                }
                if let pickerError {
                    Text(pickerError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
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
        .fileImporter(isPresented: $importing, allowedContentTypes: supportedTypes) { result in
            switch result {
            case .success(let url):
                importURL(url)
            case .failure(let error):
                pickerError = "Unable to open Files: \(error.localizedDescription)"
            }
        }
    }
}
