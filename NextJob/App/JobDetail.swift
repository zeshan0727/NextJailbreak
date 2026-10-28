import MessageUI
import SwiftUI
import UIKit

struct AddJobScreen: View {
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            JobEditorView(job: nil, dismissAfterSave: false) { job in
                savedMessage = "\(job.title) was added."
            }
            .navigationTitle("Add Job")
            .alert("Job Saved", isPresented: Binding(
                get: { savedMessage != nil },
                set: { if !$0 { savedMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(savedMessage ?? "")
            }
        }
    }
}

struct JobDetailView: View {
    @EnvironmentObject private var store: JobStore
    @State private var showingEdit = false
    @State private var pickerKind: AttachmentKind?
    @State private var mailDraft: MailDraft?
    @State private var sharePayload: SharePayload?
    @State private var previewPayload: PreviewPayload?
    @State private var notice: String?

    let jobID: UUID

    private var job: AccountingJob? { store.job(id: jobID) }

    var body: some View {
        Group {
            if let job {
                ScrollView {
                    VStack(spacing: 18) {
                        jobHeader(job)
                        statusSection(job)
                        detailSection(job)
                        documentSection(job, kind: .sourceDocument)
                        documentSection(job, kind: .completedWork)
                        emailSection(job)
                        notesSection(job)
                    }
                    .padding(16)
                    .padding(.bottom, 20)
                }
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("Job Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") { showingEdit = true }
                    }
                }
                .sheet(isPresented: $showingEdit) {
                    NavigationStack {
                        JobEditorView(job: job, dismissAfterSave: true) { _ in }
                    }
                }
                .sheet(item: $pickerKind) { kind in
                    DocumentPicker(allowsMultipleSelection: true) { result in
                        pickerKind = nil
                        do {
                            let urls = try result.get()
                            try store.importFiles(urls, to: job.id, kind: kind)
                        } catch {
                            if error is DocumentPickerError { return }
                            notice = error.localizedDescription
                        }
                    }
                }
                .sheet(item: $mailDraft) { draft in
                    MailComposer(draft: draft) {
                        mailDraft = nil
                    }
                }
                .sheet(item: $sharePayload) { payload in
                    ActivityView(items: payload.items)
                }
                .sheet(item: $previewPayload) { payload in
                    QuickLookPreview(url: payload.url)
                }
                .alert("Next Job", isPresented: Binding(
                    get: { notice != nil },
                    set: { if !$0 { notice = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(notice ?? "")
                }
            } else {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Job unavailable",
                    message: "This job may have been deleted."
                )
                .padding()
            }
        }
    }

    private func jobHeader(_ job: AccountingJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.title)
                        .font(.title2.bold())
                    Text(store.typeName(for: job))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !job.clientReference.isEmpty {
                        Label(job.clientReference, systemImage: "person.text.rectangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusBadge(status: job.status)
            }

            HStack(spacing: 12) {
                valuePill(icon: "banknote.fill", text: "\(store.settings.currency) " + String(format: "%.2f", job.price), tint: AppPalette.green)
                valuePill(icon: "target", text: String(format: "%.1fh target", job.targetHours), tint: AppPalette.purple)
                valuePill(icon: "timer", text: String(format: "%.1fh actual", job.actualHours), tint: AppPalette.cyan)
            }
        }
        .glassCard()
    }

    private func valuePill(icon: String, text: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(tint.opacity(0.11), in: Capsule())
    }

    private func statusSection(_ job: AccountingJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Status")
            Picker("Job Status", selection: Binding(
                get: { job.status },
                set: { store.setStatus($0, for: job.id) }
            )) {
                ForEach(JobStatus.allCases) { status in
                    Label(status.title, systemImage: status.icon).tag(status)
                }
            }
            .pickerStyle(.menu)

            if job.status != .completed {
                Button {
                    store.setStatus(.completed, for: job.id)
                } label: {
                    Label("Mark Job Completed", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
        }
        .glassCard()
    }

    private func detailSection(_ job: AccountingJob) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Schedule")
            detailRow("Assigned", value: DateFormatter.mediumDate.string(from: job.assignedDate), icon: "calendar.badge.plus")
            detailRow("Due", value: DateFormatter.mediumDate.string(from: job.dueDate), icon: "calendar.badge.clock")
            detailRow(
                "Completed",
                value: job.completionDate.map { DateFormatter.mediumDate.string(from: $0) } ?? "Not completed",
                icon: "calendar.badge.checkmark"
            )
        }
        .glassCard()
    }

    private func detailRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private func documentSection(_ job: AccountingJob, kind: AttachmentKind) -> some View {
        let files = job.attachments.filter { $0.kind == kind }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(kind.title, subtitle: "\(files.count) file\(files.count == 1 ? "" : "s")")
                Button {
                    pickerKind = kind
                } label: {
                    Label(kind == .sourceDocument ? "Add" : "Upload", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if files.isEmpty {
                Text(kind == .sourceDocument
                     ? "Add documents received for this job."
                     : "Upload spreadsheets, reports, PDFs or other completed work files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(files) { attachment in
                    HStack(spacing: 11) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(kind == .sourceDocument ? AppPalette.orange : AppPalette.green)
                            .frame(width: 34, height: 34)
                            .background(
                                (kind == .sourceDocument ? AppPalette.orange : AppPalette.green).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(attachment.originalName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button {
                                previewPayload = PreviewPayload(url: store.fileURL(for: attachment, jobID: job.id))
                            } label: {
                                Label("Preview", systemImage: "eye")
                            }
                            Button(role: .destructive) {
                                store.removeAttachment(attachment, from: job.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                    }
                    if attachment.id != files.last?.id { Divider() }
                }
            }
        }
        .glassCard()
    }

    private func emailSection(_ job: AccountingJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Documents & Email", subtitle: "Prepare requests and completion packages")

            Button {
                requestDocuments(job)
            } label: {
                Label("Request Documents", systemImage: "envelope.badge")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                createAndShareZip(job)
            } label: {
                Label("Create & Share Job ZIP", systemImage: "doc.zipper")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                prepareCompletionEmail(job)
            } label: {
                Label("Completion Email with ZIP", systemImage: "paperplane.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
        .glassCard()
    }

    @ViewBuilder
    private func notesSection(_ job: AccountingJob) -> some View {
        if !job.requirements.isEmpty || !job.notes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                if !job.requirements.isEmpty {
                    SectionHeader("Required Documents")
                    Text(job.requirements)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !job.notes.isEmpty {
                    if !job.requirements.isEmpty { Divider() }
                    SectionHeader("Work Notes")
                    Text(job.notes)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .glassCard()
        }
    }

    private func requestDocuments(_ job: AccountingJob) {
        guard validateCompanyEmail() else { return }
        let requested = job.requirements.isEmpty
            ? "Please provide the documents required to complete this job."
            : "Please provide the following documents:\n\n\(job.requirements)"
        let body = """
        Dear \(store.settings.companyName),

        I am working on the following job:

        Job: \(job.title)
        Client / Reference: \(job.clientReference.isEmpty ? "Not provided" : job.clientReference)
        Due Date: \(DateFormatter.mediumDate.string(from: job.dueDate))

        \(requested)

        Kind regards,
        \(store.settings.senderName)
        """
        let draft = MailDraft(
            recipients: [store.settings.companyEmail],
            subject: "Documents Required - \(job.title)",
            body: body,
            attachments: []
        )
        presentMailOrFallback(draft: draft, fallbackItems: [body])
        store.setStatus(.waitingForDocuments, for: job.id)
    }

    private func createAndShareZip(_ job: AccountingJob) {
        do {
            let url = try store.makeJobPackage(jobID: job.id)
            sharePayload = SharePayload(items: [url])
        } catch {
            notice = error.localizedDescription
        }
    }

    private func prepareCompletionEmail(_ job: AccountingJob) {
        guard validateCompanyEmail() else { return }
        do {
            let zipURL = try store.makeJobPackage(jobID: job.id)
            let zipData = try Data(contentsOf: zipURL)
            let body = """
            Dear \(store.settings.companyName),

            The following job has been completed:

            Job: \(job.title)
            Client / Reference: \(job.clientReference.isEmpty ? "Not provided" : job.clientReference)
            Job Type: \(store.typeName(for: job))
            Completion Date: \(DateFormatter.mediumDate.string(from: job.completionDate ?? Date()))

            The completed work and related documents are included in the attached ZIP file.

            Kind regards,
            \(store.settings.senderName)
            """
            let draft = MailDraft(
                recipients: [store.settings.companyEmail],
                subject: "Job Completed - \(job.title)",
                body: body,
                attachments: [
                    MailAttachment(
                        data: zipData,
                        mimeType: "application/zip",
                        fileName: zipURL.lastPathComponent
                    )
                ]
            )
            presentMailOrFallback(draft: draft, fallbackItems: [body, zipURL])
            store.setStatus(.completed, for: job.id)
        } catch {
            notice = error.localizedDescription
        }
    }

    private func validateCompanyEmail() -> Bool {
        let email = store.settings.companyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            notice = "Add the KB Accountants email address in Settings before preparing an email."
            return false
        }
        return true
    }

    private func presentMailOrFallback(draft: MailDraft, fallbackItems: [Any]) {
        if MFMailComposeViewController.canSendMail() {
            mailDraft = draft
        } else {
            sharePayload = SharePayload(items: fallbackItems)
            notice = "Apple Mail is not configured on this iPhone. The Share Sheet has been opened instead."
        }
    }
}
