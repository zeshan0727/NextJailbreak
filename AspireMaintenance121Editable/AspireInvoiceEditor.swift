import SwiftUI

/// Edits the actual issued invoice, not the PDF layout template.
/// All changes go through AspireStore so iCloud backup and device sync observe them.
struct AspireInvoiceEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss

    let original: Invoice
    var onSaved: (Bool) -> Void

    @State private var lineItems: [InvoiceLineItem]
    @State private var dueDate: Date
    @State private var notes: String
    @State private var employeeID: UUID?
    @State private var pendingRemovalID: UUID?
    @State private var showingSaveConfirmation = false
    @State private var errorMessage: String?

    init(invoice: Invoice, onSaved: @escaping (Bool) -> Void) {
        original = invoice
        self.onSaved = onSaved
        _lineItems = State(initialValue: invoice.lineItems)
        _dueDate = State(initialValue: invoice.dueDate)
        _notes = State(initialValue: invoice.notes)
        _employeeID = State(initialValue: invoice.employeeID)
    }

    private var total: Double {
        lineItems.reduce(0) { $0 + $1.amount }
    }

    private var validForSave: Bool {
        !lineItems.isEmpty && lineItems.allSatisfy { item in
            !item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            item.quantity.isFinite && item.quantity > 0 &&
            item.unitPrice.isFinite &&
            (item.unitPrice >= 0 || original.lineItems.contains(where: {
                $0.id == item.id && $0.unitPrice < 0
            }))
        } && total.isFinite && total > 0 &&
        total + 0.005 >= original.amountPaid
    }

    private var hasChanges: Bool {
        lineItems != original.lineItems ||
        dueDate != original.dueDate ||
        notes.trimmingCharacters(in: .whitespacesAndNewlines) != original.notes ||
        employeeID != original.employeeID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invoice") {
                    LabeledContent("Number", value: original.number)
                    LabeledContent(
                        "Customer",
                        value: store.customer(id: original.customerID)?.name ?? "Unknown customer"
                    )
                    LabeledContent("Status", value: original.status.title)
                    LabeledContent("Issued", value: DateFormatter.shortDate.string(from: original.issueDate))
                    DatePicker("Due date", selection: $dueDate, in: original.issueDate..., displayedComponents: .date)
                    Picker("Job done by", selection: $employeeID) {
                        Text("Not selected").tag(UUID?.none)
                        ForEach(store.activeEmployees) { employee in
                            Text(employee.name).tag(Optional(employee.id))
                        }
                    }
                }

                Section("Invoice Items") {
                    ForEach(lineItems.map(\.id), id: \.self) { itemID in
                        if let item = lineItems.first(where: { $0.id == itemID }) {
                            let binding = lineBinding(for: itemID)
                            VStack(alignment: .leading, spacing: 9) {
                                TextField("Item / service", text: binding.description, axis: .vertical)
                                    .lineLimit(1...3)
                                TextField("Details (optional)", text: detailsBinding(for: itemID), axis: .vertical)
                                    .lineLimit(1...4)
                                if let catalogID = item.catalogItemID,
                                   let catalog = store.catalogItem(id: catalogID),
                                   !catalog.availableVariants.isEmpty {
                                    Picker("Option", selection: variantBinding(for: itemID)) {
                                        Text("Not selected").tag("")
                                        ForEach(catalog.availableVariants, id: \.self) { option in
                                            Text(option).tag(option)
                                        }
                                    }
                                }
                                TextField("Variant / color (optional)", text: variantBinding(for: itemID))
                                HStack(spacing: 12) {
                                    TextField(
                                        "Quantity", value: binding.quantity,
                                        format: .number.precision(.fractionLength(0...2))
                                    )
                                    .keyboardType(.decimalPad)
                                    TextField(
                                        "Unit price", value: binding.unitPrice,
                                        format: .number.precision(.fractionLength(2))
                                    )
                                    .keyboardType(.decimalPad)
                                }
                                HStack {
                                    Text("Amount")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(store.currency(item.amount))
                                        .font(.subheadline.weight(.semibold))
                                }
                                if lineItems.count > 1 {
                                    Button(role: .destructive) {
                                        pendingRemovalID = itemID
                                    } label: {
                                        Label("Remove Item", systemImage: "trash")
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }
                            }
                            .id(itemID)
                            .padding(.vertical, 4)
                        }
                    }

                    Menu {
                        ForEach(store.activeCatalogItems) { item in
                            Button {
                                lineItems.append(InvoiceLineItem(
                                    description: item.name,
                                    quantity: 1,
                                    unitPrice: item.unitPrice,
                                    details: item.details.isEmpty ? nil : item.details,
                                    variant: item.availableVariants.count == 1 ? item.availableVariants[0] : nil,
                                    catalogItemID: item.id
                                ))
                            } label: {
                                Text("\(item.name) • \(store.currency(item.unitPrice))")
                            }
                        }
                    } label: {
                        Label("Add from Price List", systemImage: "list.bullet.rectangle")
                    }
                    .disabled(store.activeCatalogItems.isEmpty)

                    Button {
                        lineItems.append(InvoiceLineItem(description: "", quantity: 1, unitPrice: 0))
                    } label: {
                        Label("Add Custom Item", systemImage: "plus.circle.fill")
                    }
                }

                Section("Total & Payment") {
                    LabeledContent("Revised total", value: store.currency(total))
                    if original.amountPaid > 0 {
                        LabeledContent("Already received", value: store.currency(original.amountPaid))
                    }
                    LabeledContent("Remaining", value: store.currency(max(0, total - original.amountPaid)))
                    TextField("Terms / notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if original.status == .sent || original.status == .partial {
                    Section {
                        Label("The invoice number and payment history stay unchanged.", systemImage: "checkmark.shield")
                        Text("After saving, send the revised invoice PDF to your customer.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Changes") {
                        if original.status == .sent || original.status == .partial {
                            showingSaveConfirmation = true
                        } else {
                            save()
                        }
                    }
                    .disabled(!validForSave || !hasChanges)
                }
            }
            .confirmationDialog(
                "Update issued invoice \(original.number)?",
                isPresented: $showingSaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Save Revised Invoice") { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This updates the existing invoice. The original version is kept in edit history. Send the updated PDF again after saving.")
            }
            .confirmationDialog(
                "Remove this invoice item?",
                isPresented: Binding(
                    get: { pendingRemovalID != nil },
                    set: { if !$0 { pendingRemovalID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Item", role: .destructive) {
                    if let id = pendingRemovalID {
                        lineItems.removeAll { $0.id == id }
                    }
                    pendingRemovalID = nil
                }
                Button("Cancel", role: .cancel) { pendingRemovalID = nil }
            }
            .alert(
                "Cannot Update Invoice",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func lineBinding(for id: UUID) -> Binding<InvoiceLineItem> {
        Binding(
            get: {
                lineItems.first(where: { $0.id == id }) ??
                InvoiceLineItem(id: id, description: "", quantity: 1, unitPrice: 0)
            },
            set: { updated in
                guard let index = lineItems.firstIndex(where: { $0.id == id }) else { return }
                lineItems[index] = updated
            }
        )
    }

    private func detailsBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { lineItems.first(where: { $0.id == id })?.details ?? "" },
            set: { value in
                guard let index = lineItems.firstIndex(where: { $0.id == id }) else { return }
                lineItems[index].details = value
            }
        )
    }

    private func variantBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { lineItems.first(where: { $0.id == id })?.variant ?? "" },
            set: { value in
                guard let index = lineItems.firstIndex(where: { $0.id == id }) else { return }
                lineItems[index].variant = value
            }
        )
    }

    private func save() {
        guard validForSave else { return }
        do {
            let changed = try store.reviseInvoice(
                original: original, lineItems: lineItems,
                dueDate: dueDate, notes: notes, employeeID: employeeID
            )
            onSaved(changed)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
