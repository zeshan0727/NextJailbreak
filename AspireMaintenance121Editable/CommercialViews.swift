import SwiftUI

// MARK: - Contracts, Job Segments & Quotations

struct ContractsCenterView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var showingNewQuotation = false

    private func count(_ type: CustomerType) -> Int {
        store.customers.filter { $0.resolvedType == type }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                HStack(spacing: 10) {
                    CommercialCountCard(title: "Monthly", value: count(.monthlyMaintenance), icon: CustomerType.monthlyMaintenance.icon)
                    CommercialCountCard(title: "One-Time", value: count(.oneTimeJob), icon: CustomerType.oneTimeJob.icon)
                    CommercialCountCard(title: "Projects", value: count(.project), icon: CustomerType.project.icon)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Customer Segments", subtitle: "Keep scheduled maintenance separate from one-time and project work")
                    ForEach(CustomerType.allCases) { type in
                        NavigationLink { CustomerTypeListView(type: type) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.icon)
                                    .foregroundStyle(Color.aspireGreen)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text(type == .monthlyMaintenance ? "Tracked in Visit Center" : "Manual quotes and invoices")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(count(type))").font(.headline).foregroundStyle(Color.aspireGreen)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        if type != CustomerType.allCases.last { Divider() }
                    }
                }
                .aspirePanel()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeader(title: "Quotations", subtitle: "Printable Aspire quotations with discounts")
                        Spacer()
                        Button { showingNewQuotation = true } label: {
                            Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.aspireGreen)
                        }
                    }

                    if store.quotations.isEmpty {
                        EmptyInlineView(icon: "doc.text.magnifyingglass", text: "No quotations created")
                    } else {
                        ForEach(store.quotations) { quotation in
                            NavigationLink { QuotationDetailView(quotationID: quotation.id) } label: {
                                QuotationRow(quotation: quotation)
                            }
                            .buttonStyle(.plain)
                            if quotation.id != store.quotations.last?.id { Divider() }
                        }
                    }
                }
                .aspirePanel()
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Contracts & Quotations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingNewQuotation = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingNewQuotation) { QuotationEditorView() }
    }
}

struct CommercialCountCard: View {
    let title: String
    let value: Int
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(Color.aspireGreen)
            Text("\(value)").font(.title3.bold())
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CustomerTypeListView: View {
    @EnvironmentObject private var store: AspireStore
    let type: CustomerType

    private var customers: [Customer] {
        store.customers.filter { $0.resolvedType == type }
    }

    var body: some View {
        List {
            if customers.isEmpty {
                EmptyInlineView(icon: type.icon, text: "No \(type.rawValue.lowercased()) customers")
            } else {
                ForEach(customers) { customer in
                    NavigationLink { CustomerDetailView(customerID: customer.id) } label: {
                        EnhancedCustomerRow(customer: customer)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(type.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct QuotationRow: View {
    @EnvironmentObject private var store: AspireStore
    let quotation: Quotation

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.aspireGreen.opacity(0.10))
                Image(systemName: "doc.text.fill").foregroundStyle(Color.aspireGreen)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.customer(id: quotation.customerID)?.name ?? "Unknown Customer")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(quotation.number).font(.caption2.monospaced()).foregroundStyle(.secondary)
                Text(quotation.jobType.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(store.currency(quotation.total)).font(.subheadline.weight(.bold))
                Text(quotation.status.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(quotation.status == .accepted ? Color.aspireGreen : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct QuotationEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss

    var existing: Quotation? = nil

    @State private var customerID: UUID?
    @State private var jobType: JobType
    @State private var issueDate: Date
    @State private var validUntil: Date
    @State private var lineItems: [InvoiceLineItem]
    @State private var discountMode: QuoteDiscountMode
    @State private var discountValue: Double
    @State private var notes: String
    @State private var employeeID: UUID?
    @State private var showingNewCustomer = false
    @State private var showingNewCatalogItem = false
    @State private var previewItem: GeneratedPDFPreviewItem?
    @State private var pendingRemovalID: UUID?

    init(existing: Quotation? = nil) {
        self.existing = existing
        _customerID = State(initialValue: existing?.customerID)
        _jobType = State(initialValue: existing?.jobType ?? .project)
        _issueDate = State(initialValue: existing?.issueDate ?? Date())
        _validUntil = State(initialValue: existing?.validUntil ?? (Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()))
        _lineItems = State(initialValue: existing?.lineItems ?? [InvoiceLineItem(description: "", quantity: 1, unitPrice: 0)])
        _discountMode = State(initialValue: existing?.discountMode ?? .none)
        _discountValue = State(initialValue: existing?.discountValue ?? 0)
        _notes = State(initialValue: existing?.notes ?? "")
        _employeeID = State(initialValue: existing?.employeeID)
    }

    private var validItems: [InvoiceLineItem] {
        lineItems.filter { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.quantity > 0 && $0.unitPrice >= 0 }
    }
    private var subtotal: Double { validItems.reduce(0) { $0 + $1.amount } }
    private var discount: Double {
        switch discountMode {
        case .none: return 0
        case .percentage: return subtotal * min(max(discountValue, 0), 100) / 100
        case .amount: return min(max(discountValue, 0), subtotal)
        }
    }
    private var total: Double { max(0, subtotal - discount) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer & Work") {
                    Picker("Customer", selection: $customerID) {
                        Text("Select customer").tag(UUID?.none)
                        ForEach(store.activeCustomers) { customer in Text(customer.name).tag(Optional(customer.id)) }
                    }
                    Button { showingNewCustomer = true } label: {
                        Label("Customer not listed? Create Customer", systemImage: "person.badge.plus")
                    }
                    Picker("Work type", selection: $jobType) {
                        ForEach(JobType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    DatePicker("Quotation date", selection: $issueDate, displayedComponents: .date)
                    DatePicker("Valid until", selection: $validUntil, in: issueDate..., displayedComponents: .date)
                    Picker("Prepared / job by", selection: $employeeID) {
                        Text("Not selected").tag(UUID?.none)
                        ForEach(store.activeEmployees) { employee in Text(employee.name).tag(Optional(employee.id)) }
                    }
                }

                Section("Items / Services") {
                    // Iterate over stable IDs and resolve the binding at edit time.
                    // This avoids stale array-index bindings when SwiftUI re-renders a Form
                    // while quantity, price, details or variants are being edited.
                    ForEach(lineItems.map(\.id), id: \.self) { itemID in
                        if let item = lineItems.first(where: { $0.id == itemID }) {
                            let itemBinding = lineItemBinding(itemID)
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Item / service name", text: itemBinding.description, axis: .vertical)
                                    .lineLimit(1...3)
                                TextField("Item details — shown in grey below the item name", text: detailsBinding(itemID), axis: .vertical)
                                    .lineLimit(1...4)

                                if let catalog = catalogForLineItem(item), !catalog.availableVariants.isEmpty {
                                    Picker("Variant / Color / Option", selection: variantBinding(itemID)) {
                                        Text("Not selected").tag("")
                                        ForEach(catalog.availableVariants, id: \.self) { variant in
                                            Text(variant).tag(variant)
                                        }
                                    }
                                }
                                TextField("Variant / color / option (optional)", text: variantBinding(itemID))

                                HStack {
                                    TextField("Qty", value: itemBinding.quantity, format: .number.precision(.fractionLength(0...2)))
                                        .keyboardType(.decimalPad)
                                    TextField("Unit price", value: itemBinding.unitPrice, format: .number.precision(.fractionLength(2)))
                                        .keyboardType(.decimalPad)
                                }
                                if lineItems.count > 1 {
                                    Button(role: .destructive) { pendingRemovalID = itemID } label: {
                                        Label("Remove Item", systemImage: "trash")
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }
                            }
                            .id(itemID)
                            .padding(.vertical, 3)
                        }
                    }

                    Menu {
                        ForEach(store.activeCatalogItems) { catalog in
                            Button {
                                appendCatalogItem(catalog)
                            } label: { Text("\(catalog.name) • \(store.currency(catalog.unitPrice))") }
                        }
                    } label: { Label("Add from Price List", systemImage: "list.bullet.rectangle") }
                    .disabled(store.activeCatalogItems.isEmpty)

                    Button { showingNewCatalogItem = true } label: {
                        Label("Item not listed? Create Price-List Item", systemImage: "plus.rectangle.on.rectangle")
                    }

                    Button { addBlankItem() } label: {
                        Label("Add Custom Item", systemImage: "plus.circle")
                    }
                }

                Section("Discount") {
                    Picker("Discount type", selection: $discountMode) {
                        ForEach(QuoteDiscountMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if discountMode != .none {
                        TextField(discountMode == .percentage ? "Discount %" : "Discount amount", value: $discountValue, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                    }
                    LabeledContent("Subtotal", value: store.currency(subtotal))
                    if discount > 0 { LabeledContent("Discount", value: "-\(store.currency(discount))") }
                    LabeledContent("Quotation Total", value: store.currency(total))
                }

                Section("Terms / Notes") {
                    TextField("Quotation notes, scope, exclusions or validity terms", text: $notes, axis: .vertical).lineLimit(3...8)
                }

                Section("Document") {
                    Button { previewQuotation() } label: {
                        Label("Preview Quotation PDF", systemImage: "eye.fill")
                    }
                    .disabled(customerID == nil || validItems.isEmpty || total <= 0)
                    Text("Preview uses the current unsaved edits, item details and selected variants.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existing == nil ? "New Quotation" : "Edit Quotation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Save" : "Update") { save() }.disabled(customerID == nil || validItems.isEmpty || total <= 0)
                }
            }
            .onChange(of: customerID) { id in
                guard existing == nil, let id, let customer = store.customer(id: id) else { return }
                jobType = JobType(customerType: customer.resolvedType)
            }
            .onChange(of: issueDate) { date in
                if validUntil < date { validUntil = Calendar.current.date(byAdding: .day, value: 30, to: date) ?? date }
            }
            .sheet(isPresented: $showingNewCustomer) {
                CustomerEditorView { customer in
                    customerID = customer.id
                    jobType = JobType(customerType: customer.resolvedType)
                }
            }
            .sheet(isPresented: $showingNewCatalogItem) {
                CatalogItemEditorView { item in appendCatalogItem(item) }
            }
            .sheet(item: $previewItem) { GeneratedPDFPreviewSheet(item: $0) }
            .confirmationDialog("Remove this quotation item?", isPresented: Binding(
                get: { pendingRemovalID != nil },
                set: { if !$0 { pendingRemovalID = nil } }
            ), titleVisibility: .visible) {
                Button("Remove Item", role: .destructive) {
                    if let id = pendingRemovalID { removeLineItem(id) }
                    pendingRemovalID = nil
                }
                Button("Cancel", role: .cancel) { pendingRemovalID = nil }
            } message: {
                Text("Quantity, price and item editing will never remove a line automatically.")
            }
        }
    }

    private func lineItemBinding(_ id: UUID) -> Binding<InvoiceLineItem> {
        Binding(
            get: {
                lineItems.first(where: { $0.id == id })
                    ?? InvoiceLineItem(id: id, description: "", quantity: 1, unitPrice: 0)
            },
            set: { updated in
                guard let index = lineItems.firstIndex(where: { $0.id == id }) else { return }
                // Replace by stable identity instead of retaining an index captured by a previous render.
                lineItems[index] = updated
            }
        )
    }

    private func detailsBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { lineItems.first(where: { $0.id == id })?.details ?? "" },
            set: { value in
                guard let index = lineItems.firstIndex(where: { $0.id == id }) else { return }
                lineItems[index].details = value
            }
        )
    }

    private func variantBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { lineItems.first(where: { $0.id == id })?.variant ?? "" },
            set: { value in
                guard let index = lineItems.firstIndex(where: { $0.id == id }) else { return }
                lineItems[index].variant = value
            }
        )
    }

    private func catalogForLineItem(_ item: InvoiceLineItem) -> CatalogItem? {
        guard let catalogItemID = item.catalogItemID else { return nil }
        return store.catalogItem(id: catalogItemID)
    }

    private func addBlankItem() {
        lineItems.append(InvoiceLineItem(description: "", quantity: 1, unitPrice: 0))
    }

    private func removeLineItem(_ id: UUID) {
        lineItems.removeAll { $0.id == id }
        if lineItems.isEmpty { addBlankItem() }
    }

    private func appendCatalogItem(_ catalog: CatalogItem) {
        lineItems.append(InvoiceLineItem(
            description: catalog.name,
            quantity: 1,
            unitPrice: catalog.unitPrice,
            details: catalog.details.isEmpty ? nil : catalog.details,
            variant: catalog.availableVariants.count == 1 ? catalog.availableVariants[0] : nil,
            catalogItemID: catalog.id
        ))
    }

    private func previewQuotation() {
        guard let customerID, let customer = store.customer(id: customerID) else { return }
        let quotation = Quotation(
            id: existing?.id ?? UUID(),
            number: existing?.number ?? "PREVIEW",
            customerID: customerID,
            jobType: jobType,
            issueDate: issueDate,
            validUntil: validUntil,
            lineItems: validItems,
            discountMode: discountMode,
            discountValue: max(0, discountValue),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            status: existing?.status ?? .draft,
            employeeID: employeeID,
            convertedInvoiceID: existing?.convertedInvoiceID,
            acceptedAt: existing?.acceptedAt,
            createdAt: existing?.createdAt ?? Date()
        )
        let data = QuotationPDFService().makePDF(
            quotation: quotation,
            customer: customer,
            company: store.company,
            settings: store.quotationPDFSettings,
            bankAccount: store.defaultBankAccount,
            appLogoData: store.appLogoData,
            employeeName: store.employee(id: employeeID)?.name
        )
        previewItem = GeneratedPDFPreviewItem(title: existing?.number ?? "Quotation Preview", data: data)
    }

    private func save() {
        guard let customerID, let customer = store.customer(id: customerID) else { return }
        if var updated = existing {
            updated.customerID = customerID
            updated.jobType = jobType
            updated.issueDate = issueDate
            updated.validUntil = validUntil
            updated.lineItems = validItems
            updated.discountMode = discountMode
            updated.discountValue = max(0, discountValue)
            updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.employeeID = employeeID
            store.updateQuotation(updated)
        } else {
            _ = store.makeQuotation(
                for: customer,
                jobType: jobType,
                issueDate: issueDate,
                validUntil: validUntil,
                lineItems: validItems,
                discountMode: discountMode,
                discountValue: max(0, discountValue),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                employeeID: employeeID
            )
        }
        dismiss()
    }
}

struct QuotationInvoiceConversionView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let quotation: Quotation
    let onCreated: (UUID) -> Void

    @State private var customerID: UUID?
    @State private var issueDate = Date()
    @State private var showingNewCustomer = false

    init(quotation: Quotation, onCreated: @escaping (UUID) -> Void) {
        self.quotation = quotation
        self.onCreated = onCreated
        _customerID = State(initialValue: quotation.customerID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Assign Invoice To") {
                    Picker("Customer", selection: $customerID) {
                        Text("Select customer").tag(UUID?.none)
                        ForEach(store.activeCustomers) { customer in Text(customer.name).tag(Optional(customer.id)) }
                    }
                    Button { showingNewCustomer = true } label: {
                        Label("Customer not listed? Create Customer", systemImage: "person.badge.plus")
                    }
                    DatePicker("Invoice date", selection: $issueDate, displayedComponents: .date)
                }
                Section("From Quotation") {
                    LabeledContent("Quotation", value: quotation.number)
                    LabeledContent("Total", value: store.currency(quotation.total))
                    Text("The quotation items, discount, notes and assigned employee will be carried into the invoice.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Invoice") { create() }.disabled(customerID == nil)
                }
            }
            .sheet(isPresented: $showingNewCustomer) {
                CustomerEditorView { customer in customerID = customer.id }
            }
        }
    }

    private func create() {
        guard let customerID, let customer = store.customer(id: customerID) else { return }
        let invoice = store.createInvoice(from: quotation, for: customer, issueDate: issueDate)
        onCreated(invoice.id)
        dismiss()
    }
}

struct QuotationDetailView: View {
    @EnvironmentObject private var store: AspireStore
    let quotationID: UUID
    @State private var shareItems: ShareItems?
    @State private var confirmDelete = false
    @State private var showingConversion = false
    @State private var createdInvoiceID: UUID?
    @State private var message: String?
    @State private var showingEditQuotation = false
    @State private var previewItem: GeneratedPDFPreviewItem?

    var body: some View {
        Group {
            if let quotation = store.quotation(id: quotationID), let customer = store.customer(id: quotation.customerID) {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        quotationHeader(quotation: quotation, customer: customer)
                        quotationItems(quotation: quotation)

                        if !quotation.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionHeader(title: "Terms / Notes", subtitle: nil)
                                Text(quotation.notes).font(.subheadline)
                            }
                            .aspirePanel()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Document Workflow", subtitle: "Quotation → Invoice → Payment → Receipt")
                            ActionButton(title: "Preview Quotation PDF", icon: "eye.fill", style: .green) {
                                previewItem = GeneratedPDFPreviewItem(title: quotation.number, data: quotationPDF(quotation: quotation, customer: customer))
                            }
                            ActionButton(title: "Download / Share Quotation PDF", icon: "arrow.down.doc.fill", style: .neutral) {
                                shareQuotationPDF(quotation: quotation, customer: customer)
                            }

                            if quotation.status == .accepted && quotation.convertedInvoiceID == nil {
                                ActionButton(title: "Create Invoice from Accepted Quote", icon: "doc.badge.plus", style: .gold) {
                                    showingConversion = true
                                }
                            } else if quotation.status != .accepted && quotation.convertedInvoiceID == nil {
                                Label("Mark the quotation Accepted to enable invoice creation.", systemImage: "info.circle")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }

                            if let invoiceID = quotation.convertedInvoiceID, let invoice = store.invoice(id: invoiceID), let invoiceCustomer = store.customer(id: invoice.customerID) {
                                Divider()
                                Label("Invoice created: \(invoice.number)", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.bold)).foregroundStyle(Color.aspireGreen)
                                NavigationLink { InvoiceDetailView(invoiceID: invoice.id) } label: {
                                    Label("Open Invoice", systemImage: "doc.text.fill").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent).tint(.aspireGreen)
                                ActionButton(title: "Preview Invoice PDF", icon: "eye", style: .neutral) {
                                    previewItem = GeneratedPDFPreviewItem(title: invoice.number, data: invoicePDF(invoice: invoice, customer: invoiceCustomer))
                                }
                                ActionButton(title: "Download / Share Invoice PDF", icon: "arrow.down.doc", style: .neutral) {
                                    shareInvoicePDF(invoice: invoice, customer: invoiceCustomer)
                                }
                                if invoice.status == .paid {
                                    ActionButton(title: "Preview Payment Receipt", icon: "eye.fill", style: .green) {
                                        previewItem = GeneratedPDFPreviewItem(title: "Receipt - \(invoice.number)", data: receiptPDF(invoice: invoice, customer: invoiceCustomer))
                                    }
                                    ActionButton(title: "Download Payment Receipt", icon: "checkmark.seal.fill", style: .green) {
                                        shareReceiptPDF(invoice: invoice, customer: invoiceCustomer)
                                    }
                                } else {
                                    Label("Mark the invoice paid to enable the payment receipt.", systemImage: "banknote")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .aspirePanel()

                        Menu {
                            ForEach(QuotationStatus.allCases) { status in
                                Button(status.rawValue) { setStatus(status, quotation: quotation) }
                            }
                        } label: {
                            Label("Change Status", systemImage: "checkmark.seal")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete Quotation", systemImage: "trash").frame(maxWidth: .infinity)
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Quotation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showingEditQuotation = true } label: { Label("Edit", systemImage: "pencil") }
                    }
                }
                .sheet(item: $shareItems) { ShareSheet(items: $0.items) }
                .sheet(item: $previewItem) { GeneratedPDFPreviewSheet(item: $0) }
                .sheet(isPresented: $showingEditQuotation) { QuotationEditorView(existing: quotation) }
                .sheet(isPresented: $showingConversion) {
                    QuotationInvoiceConversionView(quotation: quotation) { invoiceID in
                        createdInvoiceID = invoiceID
                        message = "Invoice created successfully."
                    }
                }
                .confirmationDialog("Delete this quotation?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete Quotation", role: .destructive) { store.deleteQuotation(quotation.id) }
                    Button("Cancel", role: .cancel) {}
                }
                .alert("Quotation", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: { Text(message ?? "") }
            } else {
                FullEmptyView(title: "Quotation Not Found", icon: "doc.badge.ellipsis", message: "This quotation is no longer available.")
            }
        }
    }

    private func quotationHeader(quotation: Quotation, customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(quotation.number).font(.headline.monospaced())
                    Text(customer.name).font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.8)
                    Text(quotation.jobType.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(quotation.status.rawValue.uppercased())
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.aspireGreen.opacity(0.10), in: Capsule())
                    .foregroundStyle(quotation.status == .accepted ? Color.aspireGreen : .secondary)
            }
            Divider()
            LabeledContent("Quotation date", value: DateFormatter.shortDate.string(from: quotation.issueDate))
            LabeledContent("Valid until", value: DateFormatter.shortDate.string(from: quotation.validUntil))
        }
        .aspirePanel()
    }

    private func quotationItems(quotation: Quotation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Items", subtitle: nil)
            ForEach(quotation.lineItems) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.description).font(.subheadline.weight(.semibold))
                        if item.hasSecondaryText {
                            Text(item.secondaryDisplayText)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(item.quantity, specifier: "%.2f") × \(store.currency(item.unitPrice))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(store.currency(item.amount)).font(.subheadline.weight(.semibold))
                }
                if item.id != quotation.lineItems.last?.id { Divider() }
            }
            Divider()
            LabeledContent("Subtotal", value: store.currency(quotation.subtotal))
            if quotation.discountAmount > 0 { LabeledContent("Discount", value: "-\(store.currency(quotation.discountAmount))") }
            LabeledContent("Total", value: store.currency(quotation.total)).font(.headline)
        }
        .aspirePanel()
    }

    private func setStatus(_ status: QuotationStatus, quotation: Quotation) {
        var updated = quotation
        updated.status = status
        if status == .accepted { updated.acceptedAt = updated.acceptedAt ?? Date() }
        store.updateQuotation(updated)
    }

    private func quotationPDF(quotation: Quotation, customer: Customer) -> Data {
        QuotationPDFService().makePDF(
            quotation: quotation,
            customer: customer,
            company: store.company,
            settings: store.quotationPDFSettings,
            bankAccount: store.defaultBankAccount,
            appLogoData: store.appLogoData,
            employeeName: store.employee(id: quotation.employeeID)?.name
        )
    }

    private func invoicePDF(invoice: Invoice, customer: Customer) -> Data {
        InvoicePDFService().makePDF(
            invoice: invoice,
            customer: customer,
            company: store.company,
            settings: store.invoicePDFSettings,
            bankAccount: store.defaultBankAccount,
            appLogoData: store.appLogoData,
            employeeName: store.employee(id: invoice.employeeID)?.name
        )
    }

    private func receiptPDF(invoice: Invoice, customer: Customer) -> Data {
        PaymentReceiptPDFService().makePDF(
            invoice: invoice,
            customer: customer,
            company: store.company,
            settings: store.receiptPDFSettings,
            bankAccount: store.defaultBankAccount,
            appLogoData: store.appLogoData,
            employeeName: store.employee(id: invoice.employeeID)?.name
        )
    }

    private func shareQuotationPDF(quotation: Quotation, customer: Customer) {
        share(data: quotationPDF(quotation: quotation, customer: customer), fileName: "\(quotation.number).pdf")
    }

    private func shareInvoicePDF(invoice: Invoice, customer: Customer) {
        share(data: invoicePDF(invoice: invoice, customer: customer), fileName: "\(invoice.number).pdf")
    }

    private func shareReceiptPDF(invoice: Invoice, customer: Customer) {
        share(data: receiptPDF(invoice: invoice, customer: customer), fileName: "Receipt-\(invoice.number).pdf")
    }

    private func share(data: Data, fileName: String) {
        do {
            let url = try TemporaryFileService.write(data: data, fileName: fileName)
            shareItems = ShareItems(items: [url])
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Price Book

struct PriceBookView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var adding = false
    @State private var editing: CatalogItem?
    @State private var searchText = ""

    private var items: [CatalogItem] {
        guard !searchText.isEmpty else { return store.catalogItems }
        return store.catalogItems.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.details.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if items.isEmpty {
                EmptyInlineView(icon: "list.bullet.rectangle", text: searchText.isEmpty ? "Add reusable products and services for quotations" : "No matching price-list items")
            } else {
                ForEach(items) { item in
                    Button { editing = item } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.isActive ? "checkmark.circle.fill" : "pause.circle")
                                .foregroundStyle(item.isActive ? Color.aspireGreen : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                if !item.details.isEmpty { Text(item.details).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                HStack(spacing: 6) {
                                    if !item.category.isEmpty { Text(item.category) }
                                    if !item.unit.isEmpty { Text("• \(item.unit)") }
                                }
                                .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(store.currency(item.unitPrice)).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for offset in offsets { store.deleteCatalogItem(items[offset].id) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Items & Price List")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Item, service or category")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { CatalogItemEditorView() }
        .sheet(item: $editing) { CatalogItemEditorView(existing: $0) }
    }
}

struct CatalogItemEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    var existing: CatalogItem? = nil
    var onSave: ((CatalogItem) -> Void)? = nil

    @State private var name = ""
    @State private var details = ""
    @State private var unit = "Each"
    @State private var unitPrice = 0.0
    @State private var category = ""
    @State private var variantsText = ""
    @State private var isActive = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Item / Service") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $details, axis: .vertical).lineLimit(2...5)
                    TextField("Category", text: $category)
                    TextField("Unit (Each, m², visit, etc.)", text: $unit)
                    TextField("Variants / colors / options — one per line or comma-separated", text: $variantsText, axis: .vertical)
                        .lineLimit(2...6)
                    Text("Example: White, Beige, Black — or stone size / finish options. These become selectable when adding the item to a quotation.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Unit price", value: $unitPrice, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                    Toggle("Active in quotation picker", isOn: $isActive)
                }
            }
            .navigationTitle(existing == nil ? "New Price Item" : "Edit Price Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unitPrice < 0) }
            }
            .onAppear {
                guard let existing else { return }
                name = existing.name
                details = existing.details
                unit = existing.unit
                unitPrice = existing.unitPrice
                category = existing.category
                variantsText = existing.availableVariants.joined(separator: "\n")
                isActive = existing.isActive
            }
        }
    }

    private var parsedVariants: [String] {
        var seen = Set<String>()
        return variantsText
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private func save() {
        let item = CatalogItem(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
            unitPrice: max(0, unitPrice),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            isActive: isActive,
            createdAt: existing?.createdAt ?? Date(),
            variants: parsedVariants.isEmpty ? nil : parsedVariants
        )
        if existing == nil { store.addCatalogItem(item) } else { store.updateCatalogItem(item) }
        onSave?(item)
        dismiss()
    }
}
