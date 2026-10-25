import SwiftUI

struct MobileBackupCenter: View {
    @EnvironmentObject private var store: MobileStore
    @Binding var showImporter: Bool
    @State private var showRestoreConfirmation = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Local Recovery", systemImage: "externaldrive.badge.checkmark")
                        .font(.title3.bold())
                        .foregroundStyle(MobilePalette.accent)
                    Text("Import a verified Windows full-backup ZIP or AccountantsNext.db. The iPhone opens a separate read-only copy, leaving the Windows data untouched.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
            }

            Section("Current mobile snapshot") {
                if let info = store.currentSnapshotInfo {
                    LabeledContent("Source", value: info.sourceName)
                    LabeledContent("Imported", value: info.importedAt)
                    LabeledContent("SQLite", value: ByteCountFormatter.string(fromByteCount: info.databaseBytes, countStyle: .file))
                    LabeledContent("Included files", value: "\(info.fileCount)")
                    Label("SQLite validation passed", systemImage: "checkmark.shield.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else if store.currentDatabaseURL != nil {
                    LabeledContent("Source", value: store.snapshotName)
                    Text("Legacy 0.2.0 snapshot. It remains usable; new imports receive a full validation manifest.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("No Windows snapshot imported", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                Button { showImporter = true } label: {
                    Label("Import Windows Backup", systemImage: "square.and.arrow.down.fill")
                }
                .disabled(store.isBusy)
                Button { Task { await store.scanDocumentsForBackup() } } label: {
                    Label("Scan App Documents", systemImage: "folder.badge.gearshape")
                }
                .disabled(store.isBusy)
            }

            Section("Recovery points") {
                if store.hasPreviousSnapshot {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Previous verified snapshot").font(.headline)
                        if let info = store.previousSnapshotInfo {
                            Text(info.sourceName).font(.subheadline)
                            Text(info.importedAt).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Snapshot from previous installation/import")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button(role: .none) { showRestoreConfirmation = true } label: {
                        Label("Restore previous snapshot", systemImage: "arrow.uturn.backward.circle")
                    }.disabled(store.isBusy)
                } else {
                    Text("After a new backup import, the previous mobile snapshot remains available for recovery.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let older = ImportedSnapshotInfo.load(at: store.olderSnapshotRoot) {
                    LabeledContent("Older recovery copy", value: older.sourceName)
                }
            }

            Section("Protection & limits") {
                LabeledContent("Windows database", value: "Never modified")
                LabeledContent("Snapshot access", value: "Read-only")
                LabeledContent("Receipt drafts", value: "Stored separately")
                LabeledContent("Import validation", value: "Archive + SQLite")
                LabeledContent("File encryption", value: "iOS device protection")
                Text("Importing a new PC backup does not delete your separately saved iPhone receipt drafts. Keep the original full backup on your PC or trusted storage; this mobile copy is not a replacement for your recovery archive.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Sync status") {
                Label("Offline snapshot — not live synchronized", systemImage: "wifi.slash")
                    .font(.subheadline)
                Text("The Windows Cloud Backup feature is a recovery tool, not a live two-way sync protocol. Future cloud access will use independent authenticated synchronization and change tracking.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("App version", value: "0.3.0 (3)")
            }
        }
        .navigationTitle("Backup & Recovery")
        .confirmationDialog(
            "Restore previous mobile snapshot?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Previous Snapshot") {
                Task { await store.restorePreviousMobileSnapshot() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This changes only the active iPhone read-only data copy. Your current snapshot becomes the previous restore point. Local receipt drafts remain unchanged.")
        }
    }
}
