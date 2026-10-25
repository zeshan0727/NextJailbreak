import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Drafts never modify Windows AccountantsNext.db.
// Local files use iOS Complete file protection when an iPhone passcode is configured.
struct ReceiptAttachment: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var originalName: String
    var storedName: String
}

struct ReceiptDraft: Codable, Identifiable {
    var id = UUID()
    var entityID: Int64
    var company: String
    var receivedFrom: String
    var receivedBy: String
    var amount: Double
    var currency: String
    var date: Date
    var purpose: String
    var notes: String
    var attachments: [ReceiptAttachment]
    var createdAt: Date = Date()
}

@MainActor
final class ReceiptDraftStore: ObservableObject {
    @Published private(set) var items: [ReceiptDraft] = []
    private let fm = FileManager.default

    private var root: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AccountantsMobile/Drafts", isDirectory: true)
    }
    private var index: URL { root.appendingPathComponent("receipts.json") }
    private var attachmentsRoot: URL { root.appendingPathComponent("attachments", isDirectory: true) }

    init() {
        do {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let folder = base.appendingPathComponent("AccountantsMobile/Drafts", isDirectory: true)
            let indexFile = folder.appendingPathComponent("receipts.json")
            if fm.fileExists(atPath: indexFile.path) {
                items = try JSONDecoder().decode([ReceiptDraft].self, from: Data(contentsOf: indexFile))
            }
        } catch {
            // Never overwrite an unreadable draft file: a recovery copy may be needed.
            loadError = error.localizedDescription
        }
    }
    @Published var loadError = ""

    private func ensureStorage() throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: attachmentsRoot, withIntermediateDirectories: true)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: attachmentsRoot.path)
    }
    func save(_ draft: ReceiptDraft) throws {
        guard draft.amount > 0, draft.amount.isFinite,
              !draft.receivedFrom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.receivedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw DraftError.invalidFields }
        guard loadError.isEmpty else { throw DraftError.unreadableExistingData }
        try ensureStorage()
        var updated = items
        if let index = updated.firstIndex(where: { $0.id == draft.id }) {
            updated[index] = draft
        } else {
            updated.insert(draft, at: 0)
        }
        let data = try JSONEncoder().encode(updated)
        try data.write(to: index, options: [.atomic, .completeFileProtection])
        items = updated
    }
    func addAttachment(from source: URL) throws -> ReceiptAttachment {
        try ensureStorage()
        let scope = source.startAccessingSecurityScopedResource()
        defer { if scope { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw DraftError.invalidAttachment }
        guard (values.fileSize ?? Int.max) <= 15 * 1024 * 1024 else { throw DraftError.oversize }
        let ext = source.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        let targetName = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let target = attachmentsRoot.appendingPathComponent(targetName)
        try fm.copyItem(at: source, to: target)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
        return ReceiptAttachment(originalName: source.lastPathComponent, storedName: targetName)
    }
    func attachmentURL(_ attachment: ReceiptAttachment) -> URL? {
        let path = attachmentsRoot.appendingPathComponent(attachment.storedName)
        return fm.fileExists(atPath: path.path) ? path : nil
    }


}
enum DraftError: LocalizedError {
    case invalidFields, oversize, invalidAttachment, unreadableExistingData
    var errorDescription: String? {
        switch self {
        case .invalidFields: return "Enter a positive amount, Received From and Received By."
        case .oversize: return "Attachments must be 15 MB or smaller."
        case .invalidAttachment: return "Select a regular document file."
        case .unreadableExistingData: return "Saved receipt drafts could not be read. The original file has been preserved for recovery."
        }
    }
}

struct ReceiptDraftForm: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var drafts: ReceiptDraftStore
    @Environment(\.dismiss) private var dismiss
    @State private var receivedFrom = ""
    @State private var receivedBy = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var purpose = ""
    @State private var notes = ""
    @State private var attachments: [ReceiptAttachment] = []
    @State private var importingFile = false
    @State private var errorMessage = ""

    private var valid: Bool {
        guard let n = Double(amount.replacingOccurrences(of: ",", with: "")) else { return false }
        return n.isFinite && n > 0 && !receivedFrom.trimmingCharacters(in: .whitespaces).isEmpty
            && !receivedBy.trimmingCharacters(in: .whitespaces).isEmpty
            && store.selectedEntity != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Company") {
                    Text(store.selectedEntity?.name ?? "Select a company first")
                        .foregroundStyle(.secondary)
                    DatePicker("Receipt date", selection: $date, displayedComponents: .date)
                }
                Section("Receipt details") {
                    TextField("Received From", text: $receivedFrom)
                    TextField("Received By", text: $receivedBy)
                    HStack {
                        Text(store.selectedEntity?.currency ?? "QAR")
                        TextField("Amount", text: $amount).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Purpose", text: $purpose)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
                }
                Section("Supporting documents") {
                    ForEach(attachments) { a in
                        Label(a.originalName, systemImage: "paperclip").lineLimit(1)
                    }
                    Button { importingFile = true } label: {
                        Label("Attach file (max 15 MB)", systemImage: "plus")
                    }
                }
                Section {
                    Text("This is a local draft, not a posted receipt. The Windows application remains unchanged until an approved sync workflow is available.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Receipt Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!valid)
                }
            }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                do {
                    if case .success(let urls) = result, let source = urls.first {
                        attachments.append(try drafts.addAttachment(from: source))
                    }
                    if case .failure(let err) = result { errorMessage = err.localizedDescription }
                } catch { errorMessage = error.localizedDescription }
            }
            .alert("Receipt Draft", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage) }
        }
    }
    private func save() {
        guard let entity = store.selectedEntity,
              let value = Double(amount.replacingOccurrences(of: ",", with: "")) else { return }
        let record = ReceiptDraft(
            entityID: entity.id, company: entity.name,
            receivedFrom: receivedFrom.trimmingCharacters(in: .whitespacesAndNewlines),
            receivedBy: receivedBy.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: value, currency: entity.currency.isEmpty ? "QAR" : entity.currency,
            date: date, purpose: purpose, notes: notes, attachments: attachments
        )
        do { try drafts.save(record); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct ReceiptDraftDetail: View {
    @EnvironmentObject private var store: ReceiptDraftStore
    let draft: ReceiptDraft
    @State private var shareURL: URL?
    @State private var errorMessage = ""
    var body: some View {
        List {
            Section("Local draft") {
                LabeledContent("Company", value: draft.company)
                LabeledContent("Received From", value: draft.receivedFrom)
                LabeledContent("Received By", value: draft.receivedBy)
                LabeledContent("Amount", value: "\(draft.currency) \(String(format: "%.2f", draft.amount))")
                LabeledContent("Purpose", value: draft.purpose)
                if !draft.notes.isEmpty { Text(draft.notes) }
            }
            Section("Supportings") {
                if draft.attachments.isEmpty {
                    Text("No attachments").foregroundStyle(.secondary)
                }
                ForEach(draft.attachments) { file in
                    if let url = store.attachmentURL(file) {
                        Button(file.originalName) { shareURL = url }
                    } else {
                        Text("\(file.originalName) — missing").foregroundStyle(.orange)
                    }
                }
            }
            Section("Desktop-compatible export") {
                Label("PC format only", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                Text("This receipt is an unposted iPhone draft. The desktop receipt template and numbering service have not been imported, so a substitute PDF is deliberately not generated. Supporting files can still be shared unchanged.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Receipt Draft")
        .sheet(item: Binding(
            get: { shareURL.map { ExportableURL(url: $0) } },
            set: { if $0 == nil { shareURL = nil } }
        )) { selection in
            ShareActivity(items: [selection.url])
        }
        .alert("Unable to export", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage) }
    }
}

private struct ExportableURL: Identifiable {
    let url: URL
    var id: String { url.path }
}
private struct ShareActivity: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
