import MessageUI
import SwiftUI
import UIKit

struct JobEditorView: View {
    @EnvironmentObject private var store: JobStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: JobDraft
    @State private var didApplyDefaultType = false

    let dismissAfterSave: Bool
    let onSaved: (AccountingJob) -> Void

    init(
        job: AccountingJob?,
        dismissAfterSave: Bool,
        onSaved: @escaping (AccountingJob) -> Void
    ) {
        _draft = State(initialValue: job.map { JobDraft(job: $0) } ?? JobDraft())
        self.dismissAfterSave = dismissAfterSave
        self.onSaved = onSaved
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Job") {
                TextField("Job title", text: $draft.title)
                TextField("Client / reference", text: $draft.clientReference)
                Picker("Job type", selection: $draft.jobTypeID) {
                    Text("Custom / Unspecified").tag(UUID?.none)
                    ForEach(store.jobTypes.filter { !$0.isArchived }) { type in
                        Text(type.name).tag(Optional(type.id))
                    }
                }
                if draft.jobTypeID == nil {
                    TextField("Custom job type", text: $draft.customTypeName)
                }
                Picker("Status", selection: $draft.status) {
                    ForEach(JobStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
            }

            Section("Schedule") {
                DatePicker("Assigned date", selection: $draft.assignedDate, displayedComponents: .date)
                DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
                Toggle("Record completion date", isOn: $draft.completionDateEnabled)
                if draft.completionDateEnabled {
                    DatePicker("Completion date", selection: $draft.completionDate, displayedComponents: .date)
                }
            }

            Section("Price & Time") {
                HStack {
                    Text("Job price")
                    Spacer()
                    Text(store.settings.currency)
                        .foregroundStyle(.secondary)
                    TextField("0.00", value: $draft.price, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                }
                HStack {
                    Text("Target hours")
                    Spacer()
                    TextField("0", value: $draft.targetHours, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                }
                HStack {
                    Text("Actual hours")
                    Spacer()
                    TextField("0", value: $draft.actualHours, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                }
            }

            Section("Required Documents") {
                TextEditor(text: $draft.requirements)
                    .frame(minHeight: 90)
            }

            Section("Work Notes") {
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 110)
            }

            Section {
                Button {
                    save()
                } label: {
                    Label(draft.id == nil ? "Add Job" : "Save Changes", systemImage: "checkmark.circle.fill")
                }
                .disabled(!canSave)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(draft.id == nil ? "New Job" : "Edit Job")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if dismissAfterSave {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .onAppear {
            applyDefaultTypeIfNeeded()
        }
        .onChange(of: draft.jobTypeID) { newValue in
            guard didApplyDefaultType, let type = store.type(id: newValue) else { return }
            draft.price = type.defaultPrice
            draft.targetHours = type.targetHours
        }
        .onChange(of: draft.status) { newValue in
            if newValue == .completed {
                draft.completionDateEnabled = true
                if draft.completionDate > Date() { draft.completionDate = Date() }
            }
        }
    }

    private func applyDefaultTypeIfNeeded() {
        guard !didApplyDefaultType else { return }
        didApplyDefaultType = true
        if draft.id == nil, draft.jobTypeID == nil, let first = store.jobTypes.first(where: { !$0.isArchived }) {
            draft.jobTypeID = first.id
            draft.price = first.defaultPrice
            draft.targetHours = first.targetHours
        }
    }

    private func save() {
        guard canSave else { return }
        let job = draft.makeJob()
        store.upsert(job)
        onSaved(job)
        if dismissAfterSave {
            dismiss()
        } else {
            draft = JobDraft()
            didApplyDefaultType = false
            applyDefaultTypeIfNeeded()
        }
    }
}
