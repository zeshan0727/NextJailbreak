import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Restore is a two-stage process: Files selection and review, then an
/// explicit merge. Picking/reading a backup NEVER modifies stored ledger data.
struct LedgerRestoreImportControl: View {
    @EnvironmentObject private var store: LedgerStore

    let title: String
    let symbol: String

    @State private var pickerPresented = false
    @State private var selectedBackup: Data?
    @State private var selectedSummary: String?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var reading = false
    @State private var merging = false
    @State private var readToken = UUID()
    @State private var inboxFiles = [URL]()

    private var inboxURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                selectedBackup = nil
                selectedSummary = nil
                statusMessage = "Opening iOS Files picker for JSON backups…"
                statusIsError = false
                pickerPresented = true
            } label: {
                Label(title, systemImage: symbol)
            }
            .disabled(merging || reading)
            .accessibilityIdentifier("ledger.restore.choose")

            Button {
                refreshInbox()
            } label: {
                Label("Find JSON in App Imports Folder", systemImage: "folder")
            }
            .disabled(merging || reading)
            .accessibilityIdentifier("ledger.restore.inbox")

            if !inboxFiles.isEmpty {
                ForEach(inboxFiles, id: \.path) { url in
                    Button {
                        loadBackupURL(url)
                    } label: {
                        Label(url.lastPathComponent, systemImage: "doc.text")
                            .lineLimit(2)
                    }
                    .disabled(merging || reading)
                }
            }
            Text("Picker alternative: in Files, move/copy the JSON to On My iPhone → Next Ledger → Imports, then tap Find JSON in App Imports Folder.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if reading {
                ProgressView("Reading selected backup from Files…")
                    .font(.caption)
            }

            if let selectedSummary, selectedBackup != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backup Ready to Review")
                        .font(.subheadline.bold())
                    Text(selectedSummary)
                        .font(.subheadline)
                    Text("Nothing has been imported yet. Merging adds missing transactions/accounts by ID; backup settings may also update your preferences.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            mergeSelectedBackup()
                        } label: {
                            Label("Merge Verified Backup", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(merging || reading)
                        .accessibilityIdentifier("ledger.restore.merge")

                        Button("Cancel") {
                            selectedBackup = nil
                            self.selectedSummary = nil
                            statusMessage = "Import cancelled. Existing ledger data is unchanged."
                            statusIsError = false
                        }
                        .disabled(merging)
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }

            if merging { ProgressView("Merging verified backup…") }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ledger.restore.status")
            }
        }
        // Build 94 wrapped UIDocumentPickerViewController in a SwiftUI .sheet
        // and used .item alone as its document type. On-device, tapping JSON
        // could leave that UIKit picker open without a delegate callback.
        // Use SwiftUI's native FILE IMPORTER instead, with recognized JSON/text
        // content types and the scoped URL delivered by its own completion.
        .fileImporter(
            isPresented: $pickerPresented,
            allowedContentTypes: [.json, .plainText, .data, .content]
        ) { result in
            onFileImporterResult(result)
        }
        .onAppear { ensureInbox() }
    }

    private func ensureInbox() {
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
    }

    private func refreshInbox() {
        do {
            try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
            inboxFiles = try FileManager.default.contentsOfDirectory(
                at: inboxURL, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ).filter { url in
                ["json", "txt", "csv"].contains(url.pathExtension.lowercased())
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            statusIsError = false
            statusMessage = inboxFiles.isEmpty
                ? "Imports folder is empty. Copy your .json file to On My iPhone → Next Ledger → Imports in the Files app, then refresh."
                : "Found \(inboxFiles.count) backup file(s). Tap one below to preview before merging."
        } catch {
            statusIsError = true
            statusMessage = "Cannot read app Imports folder: \(error.localizedDescription)"
        }
    }

    private func onFileImporterResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            loadBackupURL(url)
        case .failure(let error):
            reading = false
            statusIsError = false
            statusMessage = "No backup selected. \(error.localizedDescription)"
        }
    }

    private func loadBackupURL(_ url: URL) {
        selectedBackup = nil
        selectedSummary = nil
        reading = true
        statusIsError = false
        statusMessage = "Selected \(url.lastPathComponent). Starting direct read…"
        let token = UUID()
        readToken = token

        // A third-party Files provider can indefinitely block
        // NSFileCoordinator.coordinate(), as seen with the user's 1.8 MB
        // Google Drive backup on Build 95. Do NOT coordinate this import:
        // fileImporter returns a security-scoped URL. Read its bytes directly
        // while security scope is held on the worker queue.
        //
        // A provider might still stall on direct I/O (e.g., offline download).
        // Bound the VISIBLE wait; late completions are discarded using token.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            guard readToken == token, reading else { return }
            readToken = UUID()
            reading = false
            selectedBackup = nil
            selectedSummary = nil
            statusIsError = true
            statusMessage = "File provider did not return the backup within 12 seconds. " +
                "The import was NOT applied. Copy the JSON to On My iPhone → " +
                "Next Ledger → Imports, then tap Find JSON in App Imports Folder. " +
                "You can also retry from Files once Google Drive finishes downloading."
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: Result<(Data, ImportPayload), Error> = Result {
                let needsScope = !url.path.hasPrefix(
                    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path + "/"
                )
                let accessGranted = needsScope ? url.startAccessingSecurityScopedResource() : false
                defer {
                    if accessGranted { url.stopAccessingSecurityScopedResource() }
                }

                // No NSFileCoordinator here: that was the blocking operation.
                // The actual backup JSON is small (~1.8 MB), so an ordinary
                // Data read and off-main JSON decode should complete promptly.
                // Avoid querying provider metadata before the read: some
                // Drive extensions block even resourceValues indefinitely.
                let data = try Data(contentsOf: url)
                guard !data.isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                guard data.count <= 50 * 1_024 * 1_024 else {
                    throw LedgerPickerError.tooLarge
                }
                DispatchQueue.main.async {
                    guard readToken == token, reading else { return }
                    statusMessage = "Read \(data.count) bytes from \(url.lastPathComponent). " +
                        "Validating Next Ledger records…"
                }
                let payload = try ImportExportCodec.decode(data: data)
                guard !payload.accounts.isEmpty || !payload.transactions.isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return (data, payload)
            }
            DispatchQueue.main.async {
                guard readToken == token, reading else { return }
                reading = false
                switch outcome {
                case .success(let (data, payload)):
                    selectedBackup = data
                    selectedSummary = "\(url.lastPathComponent): " +
                        "\(payload.transactions.count) transactions, " +
                        "\(payload.accounts.count) accounts."
                    statusMessage = "Backup verified. Review counts and tap " +
                        "Merge Verified Backup when ready. No data has changed yet."
                    statusIsError = false
                case .failure(let error):
                    selectedBackup = nil
                    selectedSummary = nil
                    statusMessage = "Could not read or decode selected backup: " +
                        error.localizedDescription +
                        ". Try On My iPhone → Next Ledger → Imports if the Google Drive provider is unavailable."
                    statusIsError = true
                }
            }
        }
    }

    private func mergeSelectedBackup() {
        guard let data = selectedBackup, !merging else { return }
        merging = true
        defer { merging = false }
        do {
            let summary = try store.importData(data)
            selectedBackup = nil
            selectedSummary = nil
            statusMessage = "Import complete: \(summary.transactionCount) transactions and " +
                "\(summary.accountCount) accounts added. Matching existing IDs were not duplicated."
            statusIsError = false
        } catch {
            statusMessage = "Import failed; existing ledger was not intentionally replaced: " +
                error.localizedDescription
            statusIsError = true
        }
    }
}
