import Foundation
import SwiftUI

/// A self-contained, visible restore flow for pages embedded in NavigationStack.
/// Never requires presenting a second modal from a dismissed document picker.
/// Selection only previews the backup: merging requires another explicit tap.
struct LedgerRestoreImportControl: View {
    @EnvironmentObject private var store: LedgerStore

    let title: String
    let symbol: String

    @State private var pickerPresented = false
    @State private var selectedBackup: Data?
    @State private var selectedSummary: String?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var merging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                statusMessage = "Choose a JSON backup from Files, iCloud Drive, or Google Drive."
                statusIsError = false
                pickerPresented = true
            } label: {
                Label(title, systemImage: symbol)
            }
            .disabled(merging)
            .accessibilityIdentifier("ledger.restore.choose")

            if let selectedSummary, selectedBackup != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backup Ready to Review")
                        .font(.subheadline.bold())
                    Text(selectedSummary)
                        .font(.subheadline)
                    Text("Nothing has been imported yet. Merging adds missing records by ID; backup settings may also update your preferences. Your existing records are not replaced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            mergeSelectedBackup()
                        } label: {
                            Label("Merge Verified Backup", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(merging)
                        .accessibilityIdentifier("ledger.restore.merge")

                        Button("Cancel") {
                            selectedBackup = nil
                            self.selectedSummary = nil
                            statusMessage = "Import cancelled. Your ledger was not changed."
                            statusIsError = false
                        }
                        .disabled(merging)
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }

            if merging {
                ProgressView("Merging verified backup…")
                    .font(.caption)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ledger.restore.status")
            }
        }
        // The picker and its result belong to the visible Backup & Sync page,
        // not the Settings navigation root. Results are rendered inline.
        .sheet(isPresented: $pickerPresented) {
            LedgerBackupImportPicker { result in
                pickerPresented = false
                handleSelection(result)
            }
        }
    }

    private func handleSelection(_ result: Result<Data, Error>) {
        switch result {
        case .success(let data):
            do {
                let payload = try ImportExportCodec.decode(data: data)
                guard !payload.accounts.isEmpty || !payload.transactions.isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                selectedBackup = data
                selectedSummary = "Verified file: \(payload.transactions.count) transactions, " +
                    "\(payload.accounts.count) accounts."
                statusMessage = "Review the counts above. Tap Merge Verified Backup to import."
                statusIsError = false
            } catch {
                selectedBackup = nil
                selectedSummary = nil
                statusMessage = "Backup was not imported: \(error.localizedDescription)"
                statusIsError = true
            }
        case .failure(let error):
            if case LedgerPickerError.cancelled = error {
                statusMessage = "No file selected. Your ledger was not changed."
                statusIsError = false
            } else {
                selectedBackup = nil
                selectedSummary = nil
                statusMessage = "Could not read the selected file: \(error.localizedDescription)"
                statusIsError = true
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
            statusMessage = "Import failed; retry only after checking your backup: " +
                error.localizedDescription
            statusIsError = true
        }
    }
}
