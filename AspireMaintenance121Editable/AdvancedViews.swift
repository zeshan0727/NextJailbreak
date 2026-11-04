import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Editable Aspire Branding

struct EditableAspireHeaderCard: View {
    @EnvironmentObject private var store: AspireStore
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    StoredLogoView(data: store.appLogoData)
                        .frame(maxWidth: 300, minHeight: 110, maxHeight: 150)
                    Image(systemName: "photo.badge.plus")
                        .font(.caption.weight(.bold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(4)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change Aspire dashboard logo")

            Text(loading ? "Updating logo…" : "Tap the logo to change it from Photos")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Garden Maintenance • Customers • Invoices • Profit & Loss")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .aspirePanel()
        .onChange(of: selectedPhoto) { item in
            guard let item else { return }
            loading = true
            Task {
                defer { loading = false }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let optimized = ImageUtilities.normalizedImageData(data) {
                    store.updateAppLogoData(optimized)
                }
            }
        }
    }
}

struct StoredLogoView: View {
    var data: Data?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image("AspireLogo").resizable().scaledToFit()
            }
        }
        .accessibilityLabel("Aspire Green Garden logo")
    }
}

// MARK: - Enhanced Customers

struct EnhancedCustomerRow: View {
    @EnvironmentObject private var store: AspireStore
    let customer: Customer

    private var completedVisits: Int {
        guard customer.resolvedType == .monthlyMaintenance else { return 0 }
        return store.visits(for: customer.id, in: Date()).count
    }
    private var outstanding: Double { store.outstanding(for: customer.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.aspireGreen.opacity(0.12))
                Text(customer.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased())
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.aspireGreen)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 6) {
                Text(customer.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Label(customer.resolvedType.shortTitle, systemImage: customer.resolvedType.icon)
                    Text(customer.isActive ? "ACTIVE" : "INACTIVE")
                        .font(.system(size: 8, weight: .heavy))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((customer.isActive ? Color.aspireGreen : .gray).opacity(0.12), in: Capsule())
                        .foregroundStyle(customer.isActive ? Color.aspireGreen : .secondary)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

                if !customer.address.isEmpty {
                    Label(customer.address, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if !customer.phone.isEmpty {
                    Label(customer.phone, systemImage: "phone")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }

                HStack(spacing: 10) {
                    if customer.resolvedType == .monthlyMaintenance {
                        Label("\(completedVisits)/\(customer.plannedVisitsPerMonth) visits", systemImage: "leaf.fill")
                        Text(store.currency(customer.monthlyRate) + "/month")
                    } else {
                        Label("Manual billing", systemImage: "doc.badge.plus")
                    }
                    if outstanding > 0 { Text("Due \(store.currency(outstanding))") }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(outstanding > 0 ? Color.orange : .secondary)
            }

            Spacer(minLength: 2)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 16)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Receivables & Advance Collections

struct ReceivableListView: View {
    @EnvironmentObject private var store: AspireStore
    let kind: ReceivableDashboardKind

    private var invoices: [Invoice] {
        switch kind {
        case .outstanding: return store.invoices.filter { $0.status != .void && $0.outstanding > 0 }
        case .overdue: return store.overdueInvoices()
        case .longOverdue: return store.longOverdueInvoices()
        case .advances: return []
        }
    }

    var body: some View {
        List {
            if kind == .advances {
                Section("Total • \(store.currency(store.advanceTotal()))") {
                    if store.advancePayments.isEmpty {
                        EmptyInlineView(icon: "banknote", text: "No advance collections recorded")
                    } else {
                        ForEach(store.advancePayments) { payment in
                            AdvancePaymentRow(payment: payment)
                        }
                    }
                }
            } else {
                Section("\(invoices.count) invoice(s) • \(store.currency(invoices.reduce(0) { $0 + $1.outstanding }))") {
                    if invoices.isEmpty {
                        EmptyInlineView(icon: "checkmark.seal", text: "No matching receivables")
                    } else {
                        ForEach(invoices) { invoice in
                            NavigationLink { InvoiceDetailView(invoiceID: invoice.id) } label: { InvoiceRow(invoice: invoice) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AdvancePaymentRow: View {
    @EnvironmentObject private var store: AspireStore
    let payment: AdvancePayment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "banknote.fill")
                .foregroundStyle(Color.aspireGreen)
                .frame(width: 34, height: 34)
                .background(Color.aspireGreen.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.customer(id: payment.customerID)?.name ?? "Unknown Customer").font(.subheadline.weight(.semibold))
                Text(DateFormatter.shortDate.string(from: payment.date) + (payment.reference.isEmpty ? "" : " • \(payment.reference)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.currency(payment.amount)).font(.subheadline.weight(.bold)).foregroundStyle(Color.aspireGreen)
        }
    }
}

struct AdvancePaymentEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let preselectedCustomer: Customer?

    @State private var customerID: UUID?
    @State private var date = Date()
    @State private var amountText = ""
    @State private var paymentAccount = "Cash / Bank"
    @State private var reference = ""
    @State private var notes = ""
    @State private var employeeID: UUID?
    @State private var error: String?

    init(preselectedCustomer: Customer? = nil) {
        self.preselectedCustomer = preselectedCustomer
        _customerID = State(initialValue: preselectedCustomer?.id)
    }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    Picker("Customer", selection: $customerID) {
                        Text("Select customer").tag(UUID?.none)
                        ForEach(store.customers) { Text($0.name).tag(Optional($0.id)) }
                    }
                    DatePicker("Collection date", selection: $date, displayedComponents: .date)
                }
                Section("Advance Collection") {
                    TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                    TextField("Received into", text: $paymentAccount)
                    TextField("Reference / receipt no.", text: $reference)
                    Picker("Collected by", selection: $employeeID) {
                        Text("Not selected").tag(UUID?.none)
                        ForEach(store.activeEmployees) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Collect Advance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(customerID == nil || (parsedAmount ?? 0) <= 0) }
            }
            .alert("Advance Not Saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func save() {
        guard let customerID, let amount = parsedAmount, amount > 0 else { return }
        let payment = AdvancePayment(
            customerID: customerID,
            date: date,
            amount: amount,
            paymentAccount: paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines),
            reference: reference.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            employeeID: employeeID
        )
        if store.addAdvancePayment(payment) { dismiss() }
        else { error = store.lastErrorMessage ?? "Unable to save advance collection." }
    }
}

// MARK: - Expense Review, Refund & Delete

struct ExpenseDetailView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let expenseID: UUID
    @State private var showingRefund = false
    @State private var showingDeleteReview = false

    var body: some View {
        Group {
            if let expense = store.expense(id: expenseID) {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(expense.vendor.isEmpty ? expense.category.rawValue : expense.vendor).font(.title3.bold())
                                    Text(expense.category.rawValue).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(store.currency(store.netAmount(for: expense))).font(.title2.bold()).foregroundStyle(Color.aspireGreen)
                            }
                            Divider()
                            LabeledContent("Original amount", value: store.currency(expense.amount))
                            LabeledContent("Date", value: DateFormatter.shortDate.string(from: expense.date))
                            LabeledContent("Paid from", value: expense.paymentAccount)
                            if !expense.notes.isEmpty { Text(expense.notes).font(.subheadline).foregroundStyle(.secondary) }
                        }.aspirePanel()

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Refund History", subtitle: "Refunds reduce net expenses in the month they are received")
                            let refunds = store.refunds(for: expense.id)
                            if refunds.isEmpty { EmptyInlineView(icon: "arrow.uturn.backward.circle", text: "No refunds recorded") }
                            else {
                                ForEach(refunds) { refund in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(DateFormatter.shortDate.string(from: refund.date)).font(.subheadline.weight(.semibold))
                                            if !refund.notes.isEmpty { Text(refund.notes).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer()
                                        Text("-\(store.currency(refund.amount))").font(.subheadline.weight(.bold)).foregroundStyle(.orange)
                                    }
                                }
                            }
                        }.aspirePanel()

                        HStack(spacing: 10) {
                            ActionButton(title: "Refund", icon: "arrow.uturn.backward.circle.fill", style: .gold) { showingRefund = true }
                            ActionButton(title: "Delete", icon: "trash.fill", style: .neutral) { showingDeleteReview = true }
                        }
                    }.padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Expense Review")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingRefund) { ExpenseRefundEditorView(expense: expense) }
                .confirmationDialog("Review before deleting", isPresented: $showingDeleteReview, titleVisibility: .visible) {
                    Button("Delete Expense Permanently", role: .destructive) { store.deleteExpense(expense.id); dismiss() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove the expense and any refund records linked to it.")
                }
            } else {
                FullEmptyView(title: "Expense Not Found", icon: "receipt", message: "This expense is no longer available.")
            }
        }
    }
}

struct ExpenseRefundEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let expense: Expense
    @State private var date = Date()
    @State private var amountText = ""
    @State private var notes = ""
    @State private var error: String?

    private var refunded: Double { store.refunds(for: expense.id).reduce(0) { $0 + $1.amount } }
    private var remaining: Double { max(0, expense.amount - refunded) }
    private var parsed: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    LabeledContent("Original", value: store.currency(expense.amount))
                    LabeledContent("Already refunded", value: store.currency(refunded))
                    LabeledContent("Refundable balance", value: store.currency(remaining))
                }
                Section("Refund") {
                    DatePicker("Refund date", selection: $date, displayedComponents: .date)
                    TextField("Refund amount", text: $amountText).keyboardType(.decimalPad)
                    TextField("Reason / reference", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Record Refund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled((parsed ?? 0) <= 0 || (parsed ?? 0) > remaining + 0.005) }
            }
            .alert("Refund Not Saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func save() {
        guard let amount = parsed else { return }
        if store.addExpenseRefund(ExpenseRefund(expenseID: expense.id, date: date, amount: amount, notes: notes)) { dismiss() }
        else { error = store.lastErrorMessage ?? "Unable to save refund." }
    }
}

// MARK: - Reports

struct ReportsView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var month = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    MonthPicker(month: $month)
                    NavigationLink { VisitsReportView(month: month) } label: {
                        ReportCard(title: "Visits Done", value: "\(store.monthlyMaintenanceVisits(in: month).count)", subtitle: "Maintenance visits completed this month", icon: "leaf.circle.fill")
                    }.buttonStyle(.plain)
                    NavigationLink { ExpensesReportView(month: month) } label: {
                        ReportCard(title: "Expenses Report", value: store.currency(store.expensesTotal(in: month)), subtitle: "Gross costs less refunds", icon: "receipt.fill")
                    }.buttonStyle(.plain)
                    NavigationLink { ReceivablesReportView() } label: {
                        ReportCard(title: "Receivables Report", value: store.currency(store.outstandingTotal()), subtitle: "Outstanding invoices and aging", icon: "tray.full.fill")
                    }.buttonStyle(.plain)
                    NavigationLink { ReceivableListView(kind: .advances) } label: {
                        ReportCard(title: "Advance Collections", value: store.currency(store.advanceTotal(in: month)), subtitle: "Customer money collected in advance", icon: "banknote.fill")
                    }.buttonStyle(.plain)
                    NavigationLink { ContractsCenterView() } label: {
                        ReportCard(title: "Contracts & Quotations", value: "\(store.quotations.count) quotes", subtitle: "Monthly, one-time and project work with printable quotations", icon: "doc.text.magnifyingglass")
                    }.buttonStyle(.plain)
                    NavigationLink { PriceBookView() } label: {
                        ReportCard(title: "Items & Price List", value: "\(store.activeCatalogItems.count) items", subtitle: "Reusable products and services for quotations and manual invoices", icon: "list.bullet.rectangle.portrait.fill")
                    }.buttonStyle(.plain)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reports")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { NavigationLink { SettingsView() } label: { Image(systemName: "gearshape.fill") } } }
        }
    }
}

struct ReportCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.aspireGreen)
                .frame(width: 48, height: 48).background(Color.aspireGreen.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(value).font(.title3.bold()).foregroundStyle(Color.aspireGreen)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }.aspirePanel()
    }
}

struct VisitsReportView: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date
    private var monthVisits: [MaintenanceVisit] { store.monthlyMaintenanceVisits(in: month) }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Visits completed", value: "\(monthVisits.count)")
                LabeledContent("Monthly customers", value: "\(store.monthlyMaintenanceCustomers.count)")
                let planned = store.monthlyMaintenanceCustomers.reduce(0) { $0 + $1.plannedVisitsPerMonth }
                LabeledContent("Planned visits", value: "\(planned)")
            }
            Section("Visit Details") {
                if monthVisits.isEmpty { EmptyInlineView(icon: "leaf", text: "No visits recorded for this month") }
                else {
                    ForEach(monthVisits) { visit in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(store.customer(id: visit.customerID)?.name ?? "Unknown Customer").font(.headline)
                                Spacer()
                                Text(DateFormatter.shortDate.string(from: visit.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(visit.workDone).font(.subheadline)
                            let employee = store.employee(id: visit.employeeID)?.name ?? visit.staffName
                            if !employee.isEmpty { Label(employee, systemImage: "person.fill").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("Visits • \(DateFormatter.monthAndYear.string(from: month))")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ExpensesReportView: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date
    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Gross expenses", value: store.currency(store.grossExpensesTotal(in: month)))
                LabeledContent("Refunds received", value: store.currency(store.refundsTotal(in: month)))
                LabeledContent("Net expenses", value: store.currency(store.expensesTotal(in: month)))
            }
            Section("Expenses") {
                if store.expensesForMonth(month).isEmpty { EmptyInlineView(icon: "receipt", text: "No expenses this month") }
                else {
                    ForEach(store.expensesForMonth(month)) { expense in
                        NavigationLink { ExpenseDetailView(expenseID: expense.id) } label: { ExpenseRow(expense: expense) }
                    }
                }
            }
            if !store.refundsForMonth(month).isEmpty {
                Section("Refunds") {
                    ForEach(store.refundsForMonth(month)) { refund in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(store.expense(id: refund.expenseID)?.vendor ?? "Expense Refund").font(.subheadline.weight(.semibold))
                                Text(DateFormatter.shortDate.string(from: refund.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("-\(store.currency(refund.amount))").foregroundStyle(.orange).fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .navigationTitle("Expenses • \(DateFormatter.monthAndYear.string(from: month))")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ReceivablesReportView: View {
    @EnvironmentObject private var store: AspireStore
    var body: some View {
        List {
            Section("Aging") {
                AgingRow(label: "Current / Not Due", amount: store.agingSummary().current)
                AgingRow(label: "1–30 Days", amount: store.agingSummary().days1To30)
                AgingRow(label: "31–60 Days", amount: store.agingSummary().days31To60)
                AgingRow(label: "61–90 Days", amount: store.agingSummary().days61To90)
                AgingRow(label: "Over 90 Days", amount: store.agingSummary().over90, warning: store.agingSummary().over90 > 0)
            }
            Section("Outstanding Invoices") {
                let invoices = store.invoices.filter { $0.status != .void && $0.outstanding > 0 }
                if invoices.isEmpty { EmptyInlineView(icon: "checkmark.seal", text: "No outstanding receivables") }
                else { ForEach(invoices) { invoice in NavigationLink { InvoiceDetailView(invoiceID: invoice.id) } label: { InvoiceRow(invoice: invoice) } } }
            }
        }
        .navigationTitle("Receivables Report")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Settings Hub

struct SettingsView: View {
    var body: some View {
        List {
            Section("Company") {
                NavigationLink { CompanyInformationSettingsView() } label: { SettingsRow(icon: "building.2.fill", title: "Company Information", subtitle: "Legal name, contact details and tax number") }
                NavigationLink { BankAccountsSettingsView() } label: { SettingsRow(icon: "building.columns.fill", title: "Bank Accounts", subtitle: "Add and manage payment accounts") }
                NavigationLink { EmployeesSettingsView() } label: { SettingsRow(icon: "person.3.fill", title: "Employees", subtitle: "Employee details, salary and active status") }
            }
            Section("Invoices & Printing") {
                NavigationLink { InvoiceSettingsView() } label: { SettingsRow(icon: "doc.text.fill", title: "Invoice Settings", subtitle: "Prefix, currency, terms and overdue days") }
                NavigationLink { PrintCenterView() } label: { SettingsRow(icon: "printer.fill", title: "Print Center", subtitle: "Invoice, quotation and receipt PDF editors with live drag & drop") }
            }
            Section("Dashboard & Appearance") {
                NavigationLink { ThemeAppearanceSettingsView() } label: { SettingsRow(icon: "paintpalette.fill", title: "Theme & Appearance", subtitle: "Professional Green, Corporate Blue, Premium Gold, Minimal Light and Dark Mode") }
                NavigationLink { DashboardSettingsView() } label: { SettingsRow(icon: "square.grid.2x2.fill", title: "Dashboard & Home Screen", subtitle: "Choose style, show or hide sections and reorder the Hybrid dashboard") }
            }
            Section("Connectivity & Data") {
                NavigationLink { EmailAndDataSettingsView() } label: { SettingsRow(icon: "envelope.badge.fill", title: "Email, Alerts & Backup", subtitle: "Gmail connection, notifications and data backup") }
            }
            Section("Application") {
                LabeledContent("App", value: "Aspire Maintenance")
                LabeledContent("Version", value: "1.2.0")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.aspireGreen).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }
}

struct CompanyInformationSettingsView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var company = CompanyProfile.aspireDefault
    @State private var saved = false
    var body: some View {
        Form {
            Section("Company Identity") {
                TextField("Full legal company name", text: $company.fullName, axis: .vertical)
                TextField("Trading name", text: $company.tradingName)
                TextField("Address", text: $company.address, axis: .vertical)
                TextField("Phone", text: $company.phone)
                TextField("Company email", text: $company.email).textInputAutocapitalization(.never)
                TextField("Website", text: $company.website).textInputAutocapitalization(.never)
                TextField("TRN / Tax number", text: $company.taxRegistrationNumber)
            }
            Section { Button("Save Company Information") { store.updateCompany(company); saved = true }.frame(maxWidth: .infinity) }
        }
        .navigationTitle("Company Information")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { company = store.company }
        .alert("Saved", isPresented: $saved) { Button("OK", role: .cancel) {} } message: { Text("Company information updated.") }
    }
}

struct InvoiceSettingsView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var company = CompanyProfile.aspireDefault
    @State private var saved = false
    var body: some View {
        Form {
            Section("Invoice Rules") {
                TextField("Invoice prefix", text: $company.invoicePrefix)
                TextField("Currency", text: $company.currencyCode)
                Stepper("Payment terms: \(company.paymentTermsDays) days", value: $company.paymentTermsDays, in: 0...90)
                Stepper("Long overdue: \(company.longOverdueDays) days", value: $company.longOverdueDays, in: 7...180)
                TextField("Default invoice terms", text: $company.invoiceTerms, axis: .vertical).lineLimit(3...7)
            }
            Section { Button("Save Invoice Settings") { store.updateCompany(company); saved = true }.frame(maxWidth: .infinity) }
        }
        .navigationTitle("Invoice Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { company = store.company }
        .alert("Saved", isPresented: $saved) { Button("OK", role: .cancel) {} }
    }
}

// MARK: Bank Accounts

struct BankAccountsSettingsView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var editing: BankAccount?
    @State private var adding = false
    @State private var deleteID: UUID?

    var body: some View {
        List {
            Section {
                if store.bankAccounts.isEmpty { EmptyInlineView(icon: "building.columns", text: "No bank account added") }
                else {
                    ForEach(store.bankAccounts) { account in
                        Button { editing = account } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack { Text(account.label.isEmpty ? account.bankName : account.label).font(.headline); if account.isDefault { Text("DEFAULT").font(.caption2.bold()).foregroundStyle(Color.aspireGreen) } }
                                    Text([account.bankName, account.iban].filter { !$0.isEmpty }.joined(separator: " • ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }.buttonStyle(.plain)
                        .swipeActions { Button(role: .destructive) { deleteID = account.id } label: { Label("Delete", systemImage: "trash") } }
                    }
                }
            } footer: { Text("The default account appears on generated invoice PDFs.") }
        }
        .navigationTitle("Bank Accounts")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { BankAccountEditorView(existing: nil) }
        .sheet(item: $editing) { account in BankAccountEditorView(existing: account) }
        .confirmationDialog("Delete bank account?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let deleteID { store.deleteBankAccount(deleteID) }; deleteID = nil }
            Button("Cancel", role: .cancel) { deleteID = nil }
        }
    }
}

struct BankAccountEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let existing: BankAccount?
    @State private var label = "Main Account"
    @State private var bankName = ""
    @State private var holder = ""
    @State private var number = ""
    @State private var iban = ""
    @State private var swift = ""
    @State private var currency = "AED"
    @State private var isDefault = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Account label", text: $label)
                    TextField("Bank name", text: $bankName)
                    TextField("Account holder", text: $holder)
                    TextField("Account number", text: $number)
                    TextField("IBAN", text: $iban).textInputAutocapitalization(.characters)
                    TextField("SWIFT", text: $swift).textInputAutocapitalization(.characters)
                    TextField("Currency", text: $currency).textInputAutocapitalization(.characters)
                    Toggle("Default invoice account", isOn: $isDefault)
                }
            }
            .navigationTitle(existing == nil ? "Add Bank Account" : "Edit Bank Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(bankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear {
                guard let existing else { return }
                label = existing.label; bankName = existing.bankName; holder = existing.accountHolderName; number = existing.accountNumber
                iban = existing.iban; swift = existing.swiftCode; currency = existing.currencyCode; isDefault = existing.isDefault
            }
        }
    }
    private func save() {
        let account = BankAccount(id: existing?.id ?? UUID(), label: label, bankName: bankName, accountHolderName: holder, accountNumber: number, iban: iban, swiftCode: swift, currencyCode: currency, isDefault: isDefault)
        if existing == nil { store.addBankAccount(account) } else { store.updateBankAccount(account) }
        dismiss()
    }
}

// MARK: Employees

struct EmployeesSettingsView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var adding = false
    @State private var editing: Employee?
    @State private var deleteID: UUID?

    var body: some View {
        List {
            if store.employees.isEmpty { EmptyInlineView(icon: "person.3", text: "Add employees to assign visits and invoices") }
            else {
                ForEach(store.employees) { employee in
                    Button { editing = employee } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(employee.isActive ? Color.aspireGreen : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(employee.name).font(.headline)
                                Text([employee.role, store.currency(employee.monthlySalary) + "/month"].filter { !$0.isEmpty }.joined(separator: " • ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Text(employee.isActive ? "Active" : "Inactive").font(.caption2.bold()).foregroundStyle(employee.isActive ? Color.aspireGreen : .secondary)
                        }
                    }.buttonStyle(.plain)
                    .swipeActions { Button(role: .destructive) { deleteID = employee.id } label: { Label("Delete", systemImage: "trash") } }
                }
            }
        }
        .navigationTitle("Employees")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { EmployeeEditorView(existing: nil) }
        .sheet(item: $editing) { EmployeeEditorView(existing: $0) }
        .confirmationDialog("Delete employee record?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let deleteID { store.deleteEmployee(deleteID) }; deleteID = nil }
            Button("Cancel", role: .cancel) { deleteID = nil }
        }
    }
}

struct EmployeeEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let existing: Employee?
    @State private var name = ""
    @State private var role = "Gardener"
    @State private var phone = ""
    @State private var email = ""
    @State private var salaryText = ""
    @State private var joiningDate = Date()
    @State private var isActive = true
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Employee") {
                    TextField("Full name", text: $name)
                    TextField("Role / position", text: $role)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    DatePicker("Joining date", selection: $joiningDate, displayedComponents: .date)
                    Toggle("Active employee", isOn: $isActive)
                }
                Section("Salary") { TextField("Monthly salary", text: $salaryText).keyboardType(.decimalPad) }
                Section("Notes") { TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5) }
            }
            .navigationTitle(existing == nil ? "Add Employee" : "Edit Employee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear {
                guard let existing else { return }
                name = existing.name; role = existing.role; phone = existing.phone; email = existing.email
                salaryText = String(format: "%.2f", existing.monthlySalary); joiningDate = existing.joiningDate; isActive = existing.isActive; notes = existing.notes
            }
        }
    }
    private func save() {
        let salary = Double(salaryText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let employee = Employee(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), role: role, phone: phone, email: email, monthlySalary: max(0, salary), joiningDate: joiningDate, isActive: isActive, notes: notes)
        if existing == nil { store.addEmployee(employee) } else { store.updateEmployee(employee) }
        dismiss()
    }
}

// MARK: Email, Alerts & Backup

struct EmailAndDataSettingsView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var config = EmailConfiguration.aspireDefault
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var message: String?
    @State private var importing = false
    @State private var shareItems: ShareItems?

    var body: some View {
        Form {
            Section("Invoice Email Delivery") {
                Picker("Preferred method", selection: $config.preferredMode) { ForEach(EmailDeliveryMode.allCases) { Text($0.title).tag($0) } }
                TextField("Scheduler HTTPS URL", text: $config.schedulerEndpoint).textInputAutocapitalization(.never).keyboardType(.URL)
                SecureField("Scheduler API key", text: $apiKey)
                TextField("Email signature", text: $config.signature, axis: .vertical).lineLimit(3...6)
                if config.connectorID.isEmpty {
                    Button { connect() } label: { Label(isConnecting ? "Connecting…" : "Connect Gmail", systemImage: "envelope.badge") }
                        .disabled(isConnecting || config.schedulerEndpoint.isEmpty || apiKey.isEmpty)
                } else {
                    LabeledContent("Connected", value: config.connectedEmail)
                    Button("Disconnect Gmail", role: .destructive) { disconnect() }
                }
                Button("Save Email Settings") { save() }
            }
            Section("Alerts") {
                Button { Task { await store.requestNotificationsAndRefresh() } } label: { Label("Enable Overdue Alerts", systemImage: "bell.badge.fill") }
            }
            Section("iCloud Automatic Backup") {
                Toggle("Automatic iCloud Backup", isOn: Binding(
                    get: { store.automaticCloudBackupEnabled },
                    set: { store.setAutomaticCloudBackupEnabled($0) }
                ))
                LabeledContent("Status", value: store.cloudBackupStatus)
                LabeledContent("Installed Bundle ID", value: Bundle.main.bundleIdentifier ?? "Unknown")
                Text("Cloud Container: iCloud.com.aspiregroup.maintenance")
                    .font(.caption).foregroundStyle(.secondary)
                Button { store.checkICloudAccess() } label: {
                    Label("Check iCloud Access", systemImage: "checkmark.icloud")
                }
                Text(store.iCloudAccessDiagnostic)
                    .font(.caption).foregroundStyle(.secondary)
                if let last = store.lastCloudBackupAt {
                    LabeledContent("Last Backup", value: DateFormatter.backupDateTime.string(from: last))
                    LabeledContent("Location", value: store.lastCloudBackupLocation)
                }
                Button { store.backupNowToICloud() } label: { Label("Back Up Now", systemImage: "icloud.and.arrow.up.fill") }
                Button { store.restoreLatestAutomaticBackup() } label: { Label("Restore Latest Automatic Backup", systemImage: "icloud.and.arrow.down.fill") }
                Text("Aspire keeps the latest 10 automatic JSON snapshots. When iCloud Drive is unavailable, a local safety backup is created instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Manual Backup") {
                Button { exportBackup() } label: { Label("Export Complete Backup", systemImage: "square.and.arrow.up") }
                Button { importing = true } label: { Label("Import Backup", systemImage: "square.and.arrow.down") }
            }
        }
        .navigationTitle("Email, Alerts & Backup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { config = store.emailConfiguration; apiKey = SecureStore.load(account: "scheduler-api-key") }
        .sheet(item: $shareItems) { ShareSheet(items: $0.items) }
        .sheet(isPresented: $importing) {
            AspireBackupDocumentPicker { url in
                importing = false
                importBackup(from: url)
            } onCancel: {
                importing = false
            }
            .ignoresSafeArea()
        }
        .alert("Aspire Maintenance", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }

    private func importBackup(from url: URL) {
        do {
            let backupData = try AspireBackupFileReader.readData(from: url)
            try store.importData(backupData)
            config = store.emailConfiguration
            message = "Backup imported successfully. \(store.customers.count) customer(s), \(store.invoices.count) invoice(s), \(store.visits.count) visit(s) and \(store.expenses.count) expense(s) restored."
        } catch {
            message = "Backup import failed: \(error.localizedDescription)"
        }
    }

    private func save() {
        store.updateEmailConfiguration(config)
        do {
            if apiKey.isEmpty { SecureStore.delete(account: "scheduler-api-key") } else { try SecureStore.save(apiKey, account: "scheduler-api-key") }
            message = "Email settings saved."
        } catch { message = error.localizedDescription }
    }
    private func connect() {
        save(); isConnecting = true
        Task {
            do {
                let record = try await GmailOAuthClient.shared.connect(configuration: config, apiKey: apiKey)
                config.connectorID = record.connectorID; config.connectedEmail = record.emailAddress; store.updateEmailConfiguration(config); message = "Gmail connected: \(record.emailAddress)"
            } catch { message = error.localizedDescription }
            isConnecting = false
        }
    }
    private func disconnect() {
        isConnecting = true
        Task {
            do { try await GmailOAuthClient.shared.disconnect(configuration: config, apiKey: apiKey); config.connectorID = ""; config.connectedEmail = ""; store.updateEmailConfiguration(config); message = "Gmail disconnected." }
            catch { message = error.localizedDescription }
            isConnecting = false
        }
    }
    private func exportBackup() {
        do {
            let data = try store.exportData(); let url = try TemporaryFileService.write(data: data, fileName: "Aspire-Maintenance-Backup-\(DateFormatter.invoiceMonth.string(from: Date())).json"); shareItems = ShareItems(items: [url])
        } catch { message = error.localizedDescription }
    }
}

// MARK: - Print Center & Live PDF Editors

struct PrintCenterView: View {
    var body: some View {
        List {
            Section {
                Text("Open any document editor to change text, visibility, logo, photos, section position and size. Drag the marked areas directly on the live PDF preview.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("PDF Formats") {
                ForEach(PrintDocumentKind.allCases) { kind in
                    NavigationLink { DocumentReportCenterView(kind: kind) } label: {
                        SettingsRow(icon: kind.icon, title: "\(kind.rawValue) Format", subtitle: "Live preview • drag & drop • editable sections")
                    }
                }
            }
        }
        .navigationTitle("Print Center")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OverlaySelection: Identifiable { let id: UUID }

struct InvoiceReportCenterView: View {
    let sampleInvoiceID: UUID?
    var body: some View { DocumentReportCenterView(kind: .invoice, sampleInvoiceID: sampleInvoiceID) }
}

struct DocumentReportCenterView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let kind: PrintDocumentKind
    var sampleInvoiceID: UUID? = nil
    var sampleQuotationID: UUID? = nil

    @State private var draft = InvoicePDFSettings.aspireDefault
    @State private var previewImage: UIImage?
    @State private var selectedZone: PDFEditableZone?
    @State private var overlaySelection: OverlaySelection?
    @State private var addPhotoItem: PhotosPickerItem?
    @State private var importingImage = false
    @State private var message: String?
    @State private var previewTask: Task<Void, Never>?

    private var sampleCustomer: Customer {
        Customer(name: "Sample Garden Customer", address: "Abu Dhabi, UAE", email: "customer@example.com", phone: "+971 50 000 0000", monthlyRate: 600, plannedVisitsPerMonth: 3, notes: "", isActive: true)
    }

    private var sampleInvoice: (Invoice, Customer) {
        if let sampleInvoiceID, let invoice = store.invoice(id: sampleInvoiceID), let customer = store.customer(id: invoice.customerID) { return (invoice, customer) }
        if kind == .receipt, let invoice = store.invoices.first(where: { $0.status == .paid }), let customer = store.customer(id: invoice.customerID) { return (invoice, customer) }
        if let invoice = store.invoices.first, let customer = store.customer(id: invoice.customerID) {
            if kind == .receipt {
                var paid = invoice; paid.status = .paid; paid.amountPaid = paid.total; paid.paidAt = paid.paidAt ?? Date(); return (paid, customer)
            }
            return (invoice, customer)
        }
        let customer = sampleCustomer
        let invoice = Invoice(number: "ASP-SAMPLE-001", customerID: customer.id, issueDate: Date(), dueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(), serviceMonth: Date(), lineItems: [InvoiceLineItem(description: "Garden Maintenance Charges", quantity: 1, unitPrice: 600)], status: kind == .receipt ? .paid : .sent, amountPaid: kind == .receipt ? 600 : 0, notes: store.company.invoiceTerms, sentAt: Date(), paidAt: kind == .receipt ? Date() : nil)
        return (invoice, customer)
    }

    private var sampleQuotation: (Quotation, Customer) {
        if let sampleQuotationID, let quote = store.quotation(id: sampleQuotationID), let customer = store.customer(id: quote.customerID) { return (quote, customer) }
        if let quote = store.quotations.first, let customer = store.customer(id: quote.customerID) { return (quote, customer) }
        let customer = sampleCustomer
        let quote = Quotation(number: "QT-SAMPLE-001", customerID: customer.id, jobType: .project, issueDate: Date(), validUntil: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date(), lineItems: [InvoiceLineItem(description: "Garden Landscaping Project", quantity: 1, unitPrice: 3500)], discountMode: .percentage, discountValue: 5, notes: "Quotation valid for 30 days.", status: .accepted)
        return (quote, customer)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $addPhotoItem, matching: .images) { Label("Add Photo", systemImage: "photo.badge.plus") }
                            .buttonStyle(.borderedProminent).tint(.aspireGreen)
                        Button { importingImage = true } label: { Label("Add from Files", systemImage: "folder.badge.plus") }.buttonStyle(.bordered)
                        Spacer()
                        Button("Reset") { draft = defaultSettings; schedulePreview() }.buttonStyle(.bordered)
                    }
                    .font(.caption.weight(.semibold))

                    Text("Tap a marked area to edit it. Drag any marked section or photo directly on the page to reposition it. Position and size can also be fine-tuned inside each editor.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)

                    PDFEditablePreview(image: previewImage, settings: $draft, onZone: { selectedZone = $0 }, onOverlay: { overlaySelection = OverlaySelection(id: $0) })
                        .frame(maxWidth: 520)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Visible PDF Sections", subtitle: "Fast switches for \(kind.rawValue)")
                        Toggle("Logo", isOn: $draft.showLogo)
                        Toggle("Company Name", isOn: $draft.showCompanyName)
                        Toggle("Company Contact", isOn: $draft.showCompanyContact)
                        Toggle(kind == .receipt ? "Received From" : (kind == .quotation ? "Quotation To" : "Bill To"), isOn: $draft.showBillTo)
                        Toggle("Dates / Details", isOn: $draft.showInvoiceMeta)
                        Toggle(kind == .receipt ? "Payment Amount" : "Items / Amount", isOn: $draft.showItems)
                        Toggle("Document Status", isOn: $draft.showPaymentStatus)
                        Toggle("Payment Details", isOn: $draft.showPayment)
                        Toggle("Terms / Notes", isOn: $draft.showTerms)
                        Toggle("Footer", isOn: $draft.showFooter)
                    }.aspirePanel()
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(kind.rawValue) PDF Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); message = "\(kind.rawValue) PDF format saved." } }
            }
            .onAppear { draft = storedSettings; schedulePreview() }
            .onChange(of: draft) { _ in schedulePreview() }
            .onChange(of: addPhotoItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let optimized = ImageUtilities.normalizedImageData(data) { addOverlay(data: optimized) }
                }
            }
            .fileImporter(isPresented: $importingImage, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard let optimized = ImageUtilities.normalizedImageData(try Data(contentsOf: url)) else { throw NSError(domain: "Aspire", code: 20, userInfo: [NSLocalizedDescriptionKey: "Unsupported image file."]) }
                    addOverlay(data: optimized)
                } catch { message = error.localizedDescription }
            }
            .sheet(item: $selectedZone) { zone in
                if zone == .logo { PDFLogoEditorView(documentKind: kind, settings: $draft) }
                else { PDFZoneEditorView(documentKind: kind, zone: zone, settings: $draft) }
            }
            .sheet(item: $overlaySelection) { selection in PDFOverlayImageEditorView(overlayID: selection.id, settings: $draft) }
            .alert("Print Center", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
        }
    }

    private var storedSettings: InvoicePDFSettings {
        switch kind {
        case .invoice: return store.invoicePDFSettings
        case .quotation: return store.quotationPDFSettings
        case .receipt: return store.receiptPDFSettings
        }
    }

    private var defaultSettings: InvoicePDFSettings {
        switch kind {
        case .invoice: return .aspireDefault
        case .quotation: return .aspireQuotationDefault
        case .receipt: return .aspireReceiptDefault
        }
    }

    private func save() {
        switch kind {
        case .invoice: store.updateInvoicePDFSettings(draft)
        case .quotation: store.updateQuotationPDFSettings(draft)
        case .receipt: store.updateReceiptPDFSettings(draft)
        }
    }

    private func addOverlay(data: Data) {
        draft.overlayImages.append(InvoicePDFOverlayImage(imageData: data, x: 0.60, y: 0.66, width: 0.25, height: 0.16))
    }

    private func schedulePreview() {
        previewTask?.cancel()
        let snapshot = draft
        let company = store.company
        let bank = store.defaultBankAccount
        let appLogo = store.appLogoData
        let invoicePair = sampleInvoice
        let quotePair = sampleQuotation
        let employeeInvoice = store.employee(id: invoicePair.0.employeeID)?.name
        let employeeQuote = store.employee(id: quotePair.0.employeeID)?.name
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let data: Data
            switch kind {
            case .invoice:
                data = InvoicePDFService().makePDF(invoice: invoicePair.0, customer: invoicePair.1, company: company, settings: snapshot, bankAccount: bank, appLogoData: appLogo, employeeName: employeeInvoice)
            case .quotation:
                data = QuotationPDFService().makePDF(quotation: quotePair.0, customer: quotePair.1, company: company, settings: snapshot, bankAccount: bank, appLogoData: appLogo, employeeName: employeeQuote)
            case .receipt:
                data = PaymentReceiptPDFService().makePDF(invoice: invoicePair.0, customer: invoicePair.1, company: company, settings: snapshot, bankAccount: bank, appLogoData: appLogo, employeeName: employeeInvoice)
            }
            guard !Task.isCancelled else { return }
            if let document = PDFDocument(data: data), let page = document.page(at: 0) {
                previewImage = page.thumbnail(of: CGSize(width: 714, height: 1010), for: .mediaBox)
            }
        }
    }
}

struct PDFEditablePreview: View {
    let image: UIImage?
    @Binding var settings: InvoicePDFSettings
    let onZone: (PDFEditableZone) -> Void
    let onOverlay: (UUID) -> Void

    @State private var zoneStarts: [String: PDFNormalizedRect] = [:]
    @State private var overlayStarts: [UUID: InvoicePDFOverlayImage] = [:]
    private let ratio: CGFloat = 595.2 / 841.8

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width / ratio
            ZStack(alignment: .topLeading) {
                if let image { Image(uiImage: image).resizable().scaledToFit().frame(width: width, height: height) }
                else { ProgressView().frame(width: width, height: height) }

                ForEach(PDFEditableZone.allCases) { zone in
                    let r = zoneRect(zone, width: width, height: height)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.aspireGold.opacity(0.95), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                        .background(Color.aspireGold.opacity(0.025))
                        .contentShape(Rectangle())
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .onTapGesture { onZone(zone) }
                        .gesture(DragGesture(minimumDistance: 4)
                            .onChanged { value in moveZone(zone, translation: value.translation, width: width, height: height) }
                            .onEnded { _ in zoneStarts.removeValue(forKey: zone.rawValue) })
                }

                ForEach(settings.overlayImages) { overlay in
                    if let current = settings.overlayImages.first(where: { $0.id == overlay.id }) {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.aspireGreen, lineWidth: 2)
                            .overlay(alignment: .topTrailing) { Image(systemName: "photo.fill").font(.caption2).padding(3).background(.thinMaterial, in: Circle()) }
                            .contentShape(Rectangle())
                            .frame(width: width * CGFloat(current.width), height: height * CGFloat(current.height))
                            .position(x: width * CGFloat(current.x + current.width / 2), y: height * CGFloat(current.y + current.height / 2))
                            .onTapGesture { onOverlay(current.id) }
                            .gesture(DragGesture(minimumDistance: 4)
                                .onChanged { value in moveOverlay(current.id, translation: value.translation, width: width, height: height) }
                                .onEnded { _ in overlayStarts.removeValue(forKey: current.id) })
                    }
                }
            }
            .frame(width: width, height: height)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 3, y: 1)
        }
        .aspectRatio(ratio, contentMode: .fit)
    }

    private func zoneRect(_ zone: PDFEditableZone, width: CGFloat, height: CGFloat) -> CGRect {
        let n = settings.frame(for: zone)
        return CGRect(x: n.x * width, y: n.y * height, width: n.width * width, height: n.height * height)
    }

    private func moveZone(_ zone: PDFEditableZone, translation: CGSize, width: CGFloat, height: CGFloat) {
        let start = zoneStarts[zone.rawValue] ?? settings.frame(for: zone)
        if zoneStarts[zone.rawValue] == nil { zoneStarts[zone.rawValue] = start }
        var next = start
        next.x = start.x + Double(translation.width / max(width, 1))
        next.y = start.y + Double(translation.height / max(height, 1))
        var copy = settings; copy.setFrame(next, for: zone); settings = copy
    }

    private func moveOverlay(_ id: UUID, translation: CGSize, width: CGFloat, height: CGFloat) {
        guard let index = settings.overlayImages.firstIndex(where: { $0.id == id }) else { return }
        let start = overlayStarts[id] ?? settings.overlayImages[index]
        if overlayStarts[id] == nil { overlayStarts[id] = start }
        var next = start
        next.x = max(0, min(1 - next.width, start.x + Double(translation.width / max(width, 1))))
        next.y = max(0, min(1 - next.height, start.y + Double(translation.height / max(height, 1))))
        settings.overlayImages[index] = next
    }
}

struct PDFZoneEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let documentKind: PrintDocumentKind
    let zone: PDFEditableZone
    @Binding var settings: InvoicePDFSettings

    var body: some View {
        NavigationStack {
            Form {
                Section(zone.title) { controls }
                Section("Position & Size") {
                    Slider(value: frameBinding(\.x), in: 0...0.95) { Text("Horizontal") }
                    Slider(value: frameBinding(\.y), in: 0...0.97) { Text("Vertical") }
                    Slider(value: frameBinding(\.width), in: 0.08...0.95) { Text("Width") }
                    Slider(value: frameBinding(\.height), in: 0.03...0.70) { Text("Height") }
                    Button("Reset Section Position") { var copy = settings; copy.resetFrame(for: zone); settings = copy }
                }
                Section { Text("Changes appear in the live preview immediately. You can also drag this section directly on the PDF page.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle(zone.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder private var controls: some View {
        switch zone {
        case .companyName:
            Toggle("Show company name", isOn: $settings.showCompanyName)
            TextField("Custom company name (optional)", text: $settings.companyNameOverride, axis: .vertical)
        case .companyContact:
            Toggle("Show company contact", isOn: $settings.showCompanyContact)
            TextField("Custom contact line (optional)", text: $settings.companyContactOverride, axis: .vertical)
        case .invoiceTitle:
            TextField("Document title", text: $settings.invoiceTitle)
        case .paymentStatus:
            Toggle("Show document status", isOn: $settings.showPaymentStatus)
            TextField(documentKind == .quotation ? "Accepted text" : "Paid text", text: $settings.paidText)
            TextField(documentKind == .quotation ? "Draft text" : "Unpaid / received text", text: $settings.unpaidText)
            TextField(documentKind == .quotation ? "Sent text" : "Part-paid text", text: $settings.partialPaidText)
        case .billTo:
            Toggle("Show customer section", isOn: $settings.showBillTo)
            TextField("Section title", text: $settings.billToTitle)
        case .invoiceMeta:
            Toggle("Show dates / details", isOn: $settings.showInvoiceMeta)
        case .items:
            Toggle("Show items / amount", isOn: $settings.showItems)
        case .payment:
            Toggle("Show payment details", isOn: $settings.showPayment)
            TextField("Section title", text: $settings.paymentTitle)
        case .terms:
            Toggle("Show terms / notes", isOn: $settings.showTerms)
            TextField("Section title", text: $settings.termsTitle)
        case .footer:
            Toggle("Show footer", isOn: $settings.showFooter)
            TextField("Footer text", text: $settings.footerText, axis: .vertical)
        case .logo:
            EmptyView()
        }
    }

    private func frameBinding(_ keyPath: WritableKeyPath<PDFNormalizedRect, Double>) -> Binding<Double> {
        Binding(get: { settings.frame(for: zone)[keyPath: keyPath] }, set: { value in
            var frame = settings.frame(for: zone); frame[keyPath: keyPath] = value
            var copy = settings; copy.setFrame(frame, for: zone); settings = copy
        })
    }
}

struct PDFLogoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let documentKind: PrintDocumentKind
    @Binding var settings: InvoicePDFSettings
    @State private var photoItem: PhotosPickerItem?
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("\(documentKind.rawValue) Logo") {
                    HStack { Spacer(); StoredLogoView(data: settings.logoData).frame(width: 220, height: 120); Spacer() }
                    Toggle("Show logo on PDF", isOn: $settings.showLogo)
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose from Photos", systemImage: "photo") }
                    Button { importing = true } label: { Label("Choose from Files", systemImage: "folder") }
                    if settings.logoData != nil { Button("Use Dashboard / Default Aspire Logo", role: .destructive) { settings.logoData = nil } }
                }
            }
            .navigationTitle("Logo Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task { if let data = try? await item.loadTransferable(type: Data.self), let optimized = ImageUtilities.normalizedImageData(data) { settings.logoData = optimized } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard let optimized = ImageUtilities.normalizedImageData(try Data(contentsOf: url)) else { return }
                    settings.logoData = optimized
                } catch { message = error.localizedDescription }
            }
            .alert("Image", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
        }
    }
}

struct PDFOverlayImageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let overlayID: UUID
    @Binding var settings: InvoicePDFSettings
    @State private var photoItem: PhotosPickerItem?
    @State private var importing = false

    private var index: Int? { settings.overlayImages.firstIndex { $0.id == overlayID } }

    var body: some View {
        NavigationStack {
            Form {
                if let index {
                    Section("Photo") {
                        if let image = UIImage(data: settings.overlayImages[index].imageData) { HStack { Spacer(); Image(uiImage: image).resizable().scaledToFit().frame(height: 150); Spacer() } }
                        PhotosPicker(selection: $photoItem, matching: .images) { Label("Replace from Photos", systemImage: "photo") }
                        Button { importing = true } label: { Label("Replace from Files", systemImage: "folder") }
                    }
                    Section("Position & Size") {
                        Slider(value: $settings.overlayImages[index].x, in: 0...0.90) { Text("Horizontal") }
                        Slider(value: $settings.overlayImages[index].y, in: 0...0.90) { Text("Vertical") }
                        Slider(value: $settings.overlayImages[index].width, in: 0.08...0.80) { Text("Width") }
                        Slider(value: $settings.overlayImages[index].height, in: 0.05...0.60) { Text("Height") }
                    }
                    Section { Button("Remove Photo", role: .destructive) { settings.overlayImages.remove(at: index); dismiss() } }
                }
            }
            .navigationTitle("Photo Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: photoItem) { item in
                guard let item, let index else { return }
                Task { if let data = try? await item.loadTransferable(type: Data.self), let optimized = ImageUtilities.normalizedImageData(data) { settings.overlayImages[index].imageData = optimized } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                guard let index else { return }
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if let optimized = ImageUtilities.normalizedImageData(try Data(contentsOf: url)) { settings.overlayImages[index].imageData = optimized }
                } catch { }
            }
        }
    }
}
