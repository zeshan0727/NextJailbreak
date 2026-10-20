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
            statusMessage = "File selected: \(url.lastPathComponent). Reading from its provider…"
            let token = UUID()
            readToken = token

            // File coordination can download from iCloud Drive or Google Drive.
            // All blocking I/O and JSON decoding stay off the main thread.
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome: Result<(Data, ImportPayload), Error> = Result {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    var coordinationError: NSError?
                    var readError: Error?
                    var ownedData: Data?
                    NSFileCoordinator().coordinate(
                        readingItemAt: url, options: [],
                        error: &coordinationError
                    ) { coordinatedURL in
                        do {
                            let count = try coordinatedURL.resourceValues(
                                forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard count <= 50 * 1_024 * 1_024 else {
                                throw LedgerPickerError.tooLarge
                            }
                            ownedData = try Data(contentsOf: coordinatedURL)
                        } catch {
                            readError = error
                        }
                    }
                    if let coordinationError { throw coordinationError }
                    if let readError { throw readError }
                    guard let data = ownedData, !data.isEmpty else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    guard data.count <= 50 * 1_024 * 1_024 else {
                        throw LedgerPickerError.tooLarge
                    }
                    let payload = try ImportExportCodec.decode(data: data)
                    guard !payload.accounts.isEmpty || !payload.transactions.isEmpty else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    return (data, payload)
                }
                DispatchQueue.main.async {
                    guard readToken == token else { return }
                    reading = false
                    switch outcome {
                    case .success(let (data, payload)):
                        selectedBackup = data
                        selectedSummary = "\(url.lastPathComponent): \(payload.transactions.count) transactions, " +
                            "\(payload.accounts.count) accounts."
                        statusMessage = "File verified. Tap Merge Verified Backup to import; nothing has changed yet."
                        statusIsError = false
                    case .failure(let error):
                        selectedBackup = nil
                        selectedSummary = nil
                        statusMessage = "File was selected but could not be imported: \(error.localizedDescription)"
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
