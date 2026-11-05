import MessageUI
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - App Shell

struct AppRootView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var showingError = false
    @AppStorage(ThemePreferenceKeys.appTheme) private var appThemeRaw = AspireAppTheme.professionalGreen.rawValue

    private var appTheme: AspireAppTheme { AspireAppTheme(rawValue: appThemeRaw) ?? .professionalGreen }

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }

            VisitCenterView()
                .tabItem { Label("Visits", systemImage: "calendar.badge.clock") }

            FinanceView()
                .tabItem { Label("Finance", systemImage: "wallet.bifold.fill") }

            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.bar.doc.horizontal.fill") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(appTheme.primary)
        .preferredColorScheme(appTheme.preferredColorScheme)
        .onChange(of: store.lastErrorMessage) { value in
            showingError = value != nil
        }
        .alert("Aspire Maintenance", isPresented: $showingError) {
            Button("OK") { store.lastErrorMessage = nil }
        } message: {
            Text(store.lastErrorMessage ?? "Unknown error")
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    var body: some View {
        AspireDashboardHostView()
    }
}

enum DashboardTransactionKind: String, Hashable {
    case invoiced, collected, expenses, profitLoss
    var title: String {
        switch self {
        case .invoiced: return "Invoiced Transactions"
        case .collected: return "Payments Received"
        case .expenses: return "Expense Transactions"
        case .profitLoss: return "Profit & Loss Transactions"
        }
    }
}

struct DashboardTransactionsView: View {
    @EnvironmentObject private var store: AspireStore
    let kind: DashboardTransactionKind
    let month: Date
    private var serviceInvoices: [Invoice] { store.invoicesForServiceMonth(month) }
    private var receivedInvoices: [Invoice] { store.paymentsReceived(in: month) }
    private var monthExpenses: [Expense] { store.expensesForMonth(month) }

    var body: some View {
        List {
            switch kind {
            case .invoiced:
                Section(DateFormatter.monthAndYear.string(from: month)) {
                    if serviceInvoices.isEmpty { EmptyInlineView(icon: "doc.text", text: "No invoices for this service month") }
                    else { ForEach(serviceInvoices) { invoice in NavigationLink { InvoiceDetailView(invoiceID: invoice.id) } label: { InvoiceRow(invoice: invoice) } } }
                }
            case .collected:
                Section(DateFormatter.monthAndYear.string(from: month)) {
                    if receivedInvoices.isEmpty { EmptyInlineView(icon: "banknote", text: "No payments received in this month") }
                    else { ForEach(receivedInvoices) { invoice in NavigationLink { InvoiceDetailView(invoiceID: invoice.id) } label: { InvoiceRow(invoice: invoice) } } }
                }
            case .expenses:
                Section(DateFormatter.monthAndYear.string(from: month)) {
                    if monthExpenses.isEmpty { EmptyInlineView(icon: "fuelpump", text: "No expenses recorded in this month") }
                    else { ForEach(monthExpenses) { expense in ExpenseRow(expense: expense) } }
                }
            case .profitLoss:
                Section("Invoice Income • \(store.currency(store.invoicedIncome(in: month)))") {
                    if serviceInvoices.isEmpty { EmptyInlineView(icon: "doc.text", text: "No invoice income") }
                    else { ForEach(serviceInvoices) { invoice in NavigationLink { InvoiceDetailView(invoiceID: invoice.id) } label: { InvoiceRow(invoice: invoice) } } }
                }
                Section("Expenses • \(store.currency(store.expensesTotal(in: month)))") {
                    if monthExpenses.isEmpty { EmptyInlineView(icon: "fuelpump", text: "No expenses") }
                    else { ForEach(monthExpenses) { expense in ExpenseRow(expense: expense) } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VisitProgressSection: View {
    @EnvironmentObject private var store: AspireStore
    var month: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Monthly Visits", subtitle: "Planned garden maintenance progress")
            if store.monthlyMaintenanceCustomers.isEmpty {
                EmptyInlineView(icon: "leaf.fill", text: "Add monthly-maintenance customers to track visits")
            } else {
                ForEach(store.monthlyMaintenanceCustomers.prefix(8)) { customer in
                    let completed = store.visits(for: customer.id, in: month).count
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(customer.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(completed) / \(customer.plannedVisitsPerMonth)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(completed >= customer.plannedVisitsPerMonth ? Color.aspireGreen : .secondary)
                        }
                        ProgressView(value: Double(min(completed, customer.plannedVisitsPerMonth)), total: Double(max(1, customer.plannedVisitsPerMonth)))
                            .tint(completed >= customer.plannedVisitsPerMonth ? .aspireGreen : .aspireGold)
                    }
                }
            }
        }
        .aspirePanel()
    }
}

// MARK: - Customers

private enum CustomerListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case monthly = "Monthly"
    case oneTime = "One-Time"
    case project = "Project"
    var id: String { rawValue }
}

struct CustomersView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var searchText = ""
    @State private var showingEditor = false
    @State private var filter: CustomerListFilter = .all

    private var filteredCustomers: [Customer] {
        store.customers.filter { customer in
            let matchesType: Bool
            switch filter {
            case .all: matchesType = true
            case .monthly: matchesType = customer.resolvedType == .monthlyMaintenance
            case .oneTime: matchesType = customer.resolvedType == .oneTimeJob
            case .project: matchesType = customer.resolvedType == .project
            }
            guard matchesType else { return false }
            let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return true }
            return customer.name.localizedCaseInsensitiveContains(term) ||
                customer.email.localizedCaseInsensitiveContains(term) ||
                customer.phone.localizedCaseInsensitiveContains(term) ||
                customer.address.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Customer type", selection: $filter) {
                ForEach(CustomerListFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                if filteredCustomers.isEmpty {
                    FullEmptyView(
                        title: searchText.isEmpty ? "No Customers" : "No Results",
                        icon: "person.2",
                        message: searchText.isEmpty ? "Add monthly-maintenance, one-time or project customers." : "Try another customer name, phone, address or email."
                    )
                } else {
                    List {
                        ForEach(filteredCustomers) { customer in
                            NavigationLink {
                                CustomerDetailView(customerID: customer.id)
                            } label: {
                                EnhancedCustomerRow(customer: customer)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in store.deleteCustomers(at: offsets, from: filteredCustomers) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .navigationTitle("Customers")
        .searchable(text: $searchText, prompt: "Name, phone, address or email")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingEditor = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingEditor) { CustomerEditorView() }
    }
}

struct CustomerRow: View {
    var customer: Customer

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.aspireGreen.opacity(0.12))
                Image(systemName: "leaf.fill").foregroundStyle(Color.aspireGreen)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(customer.name).font(.headline)
                Text(customer.email.isEmpty ? customer.phone : customer.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(customer.plannedVisitsPerMonth) visits/month")
                    .font(.caption2)
                    .foregroundStyle(customer.isActive ? Color.aspireGreen : .secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(CurrencyFormatter.string(customer.monthlyRate, code: "AED"))
                    .font(.subheadline.weight(.semibold))
                Text(customer.isActive ? "Active" : "Inactive")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((customer.isActive ? Color.aspireGreen : Color.gray).opacity(0.12), in: Capsule())
                    .foregroundStyle(customer.isActive ? Color.aspireGreen : .secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct CustomerDetailView: View {
    @EnvironmentObject private var store: AspireStore
    let customerID: UUID
    @State private var showingEditor = false
    @State private var showingVisit = false
    @State private var showingInvoice = false
    @State private var showingAdvance = false
    @State private var confirmArchive = false

    var body: some View {
        Group {
            if let customer = store.customer(id: customerID) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Color.aspireGreen.opacity(0.12))
                                Image(systemName: customer.resolvedType.icon)
                                    .font(.system(size: 38, weight: .semibold))
                                    .foregroundStyle(Color.aspireGreen)
                            }
                            .frame(width: 84, height: 84)
                            Text(customer.name)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .minimumScaleFactor(0.82)
                            HStack(spacing: 7) {
                                Text(customer.resolvedType.rawValue)
                                Text("•")
                                Text(customer.resolvedArchived ? "Archived" : (customer.isActive ? "Active" : "Inactive"))
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(customer.resolvedArchived ? .secondary : (customer.isActive ? Color.aspireGreen : .secondary))
                        }
                        .frame(maxWidth: .infinity)
                        .aspirePanel()

                        HStack(spacing: 12) {
                            if customer.resolvedType == .monthlyMaintenance {
                                MetricPill(title: "Monthly Bill", value: store.currency(customer.monthlyRate))
                                MetricPill(title: "Visits", value: "\(store.visits(for: customer.id, in: Date()).count)/\(customer.plannedVisitsPerMonth)")
                            } else {
                                MetricPill(title: "Work Type", value: customer.resolvedType.shortTitle)
                                MetricPill(title: "Quotes", value: "\(store.quotations.filter { $0.customerID == customer.id }.count)")
                            }
                            MetricPill(title: "Invoices", value: "\(store.invoices(for: customer.id).count)")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Contact & Site", subtitle: nil)
                            LabeledValue(icon: "mappin.and.ellipse", value: customer.address.isEmpty ? "No address" : customer.address)
                            LabeledValue(icon: "phone.fill", value: customer.phone.isEmpty ? "No phone" : customer.phone)
                            LabeledValue(icon: "envelope.fill", value: customer.email.isEmpty ? "No email" : customer.email)
                            if !customer.notes.isEmpty { LabeledValue(icon: "note.text", value: customer.notes) }
                        }
                        .aspirePanel()

                        if customer.resolvedType == .monthlyMaintenance {
                            HStack(spacing: 10) {
                                ActionButton(title: "Log Visit", icon: "checkmark.circle", style: .green) { showingVisit = true }
                                ActionButton(title: "Monthly Invoice", icon: "doc.badge.plus", style: .gold) { showingInvoice = true }
                            }
                        } else {
                            ActionButton(title: "Create Manual Invoice", icon: "doc.badge.plus", style: .gold) { showingInvoice = true }
                        }
                        HStack(spacing: 10) {
                            ActionButton(title: "Collect Advance", icon: "banknote.fill", style: .neutral) { showingAdvance = true }
                            ActionButton(title: "Edit Customer", icon: "pencil", style: .neutral) { showingEditor = true }
                        }
                        HStack(spacing: 10) {
                            ActionButton(
                                title: customer.isActive && !customer.resolvedArchived ? "Set Inactive" : "Set Active",
                                icon: customer.isActive && !customer.resolvedArchived ? "pause.circle.fill" : "checkmark.circle.fill",
                                style: customer.isActive && !customer.resolvedArchived ? .neutral : .green
                            ) {
                                if customer.resolvedArchived { store.setCustomerArchived(customer.id, archived: false) }
                                store.setCustomerActive(customer.id, active: !(customer.isActive && !customer.resolvedArchived))
                            }
                            ActionButton(
                                title: customer.resolvedArchived ? "Restore" : "Archive",
                                icon: customer.resolvedArchived ? "arrow.uturn.backward.circle.fill" : "archivebox.fill",
                                style: .neutral
                            ) {
                                if customer.resolvedArchived { store.setCustomerArchived(customer.id, archived: false) }
                                else { confirmArchive = true }
                            }
                        }

                        if customer.resolvedType == .monthlyMaintenance {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Recent Visits", subtitle: "Maintenance work history")
                                let visits = store.visits(for: customer.id)
                                if visits.isEmpty {
                                    EmptyInlineView(icon: "calendar.badge.clock", text: "No visits recorded")
                                } else {
                                    ForEach(visits.prefix(6)) { visit in
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(DateFormatter.shortDate.string(from: visit.date)).font(.subheadline.weight(.semibold))
                                                Spacer()
                                                Text(visit.staffName).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Text(visit.workDone).font(.subheadline)
                                            if !visit.notes.isEmpty { Text(visit.notes).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        if visit.id != visits.prefix(6).last?.id { Divider() }
                                    }
                                }
                            }
                            .aspirePanel()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Invoices", subtitle: "Customer billing history")
                            let invoices = store.invoices(for: customer.id)
                            if invoices.isEmpty {
                                EmptyInlineView(icon: "doc.text", text: "No invoices created")
                            } else {
                                ForEach(invoices.prefix(8)) { invoice in
                                    NavigationLink { InvoiceDetailView(invoiceID: invoice.id) } label: { InvoiceRow(invoice: invoice) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .aspirePanel()
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Customer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) { Button("Edit") { showingEditor = true } }
                }
                .sheet(isPresented: $showingEditor) { CustomerEditorView(existing: customer) }
                .sheet(isPresented: $showingVisit) { VisitEditorView(customer: customer) }
                .sheet(isPresented: $showingInvoice) {
                    if customer.resolvedType == .monthlyMaintenance {
                        QuickInvoiceView(customer: customer)
                    } else {
                        ManualInvoiceView(preselectedCustomer: customer)
                    }
                }
                .sheet(isPresented: $showingAdvance) { AdvancePaymentEditorView(preselectedCustomer: customer) }
                .confirmationDialog("Archive this customer?", isPresented: $confirmArchive, titleVisibility: .visible) {
                    Button("Archive Customer", role: .destructive) { store.setCustomerArchived(customer.id, archived: true) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The customer will remain in history but will be removed from active workflows.")
                }
            } else {
                FullEmptyView(title: "Customer Not Found", icon: "person.crop.circle.badge.exclamationmark", message: "The customer record is no longer available.")
            }
        }
    }
}

struct CustomerEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    var existing: Customer?
    var onSave: ((Customer) -> Void)? = nil

    @State private var name = ""
    @State private var address = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var monthlyRate = 0.0
    @State private var visitsPerMonth = 3
    @State private var notes = ""
    @State private var isActive = true
    @State private var customerType: CustomerType = .monthlyMaintenance

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer Type") {
                    Picker("Type", selection: $customerType) {
                        ForEach(CustomerType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    Text(customerType == .monthlyMaintenance
                         ? "Monthly customers appear in Visit Center and planned-visit totals."
                         : "One-time and project customers are not counted in monthly Visit Center totals; invoices are created manually with selected items/services.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Customer") {
                    TextField("Customer name", text: $name)
                    TextField("Site address", text: $address, axis: .vertical).lineLimit(2...4)
                    TextField("Email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    Toggle("Active customer", isOn: $isActive)
                }
                if customerType == .monthlyMaintenance {
                    Section("Monthly Maintenance") {
                        TextField("Monthly rate", value: $monthlyRate, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                        Stepper("Planned visits: \(visitsPerMonth)", value: $visitsPerMonth, in: 1...12)
                    }
                } else {
                    Section("Billing") {
                        Label("Use manual invoices/quotations to select exact items and services for this customer.", systemImage: "doc.text")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Notes") {
                    TextField("Access details, garden requirements or instructions", text: $notes, axis: .vertical).lineLimit(3...6)
                }
            }
            .navigationTitle(existing == nil ? "New Customer" : "Edit Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard let existing else { return }
                name = existing.name
                address = existing.address
                email = existing.email
                phone = existing.phone
                monthlyRate = existing.monthlyRate
                visitsPerMonth = max(1, existing.plannedVisitsPerMonth)
                notes = existing.notes
                isActive = existing.isActive
                customerType = existing.resolvedType
            }
        }
    }

    private func save() {
        let isMonthly = customerType == .monthlyMaintenance
        let customer = Customer(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            monthlyRate: isMonthly ? max(0, monthlyRate) : 0,
            plannedVisitsPerMonth: isMonthly ? max(1, visitsPerMonth) : 0,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isActive: isActive,
            customerType: customerType,
            isArchived: existing?.isArchived,
            createdAt: existing?.createdAt ?? Date()
        )
        if existing == nil { store.addCustomer(customer) } else { store.updateCustomer(customer) }
        onSave?(customer)
        dismiss()
    }
}

struct VisitEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    @State private var date = Date()
    @State private var staffName = ""
    @State private var employeeID: UUID?
    @State private var workDone = "Garden maintenance visit"
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(customer.name) {
                    DatePicker("Visit date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker("Employee / job done by", selection: $employeeID) {
                        Text("Not selected").tag(UUID?.none)
                        ForEach(store.activeEmployees) { employee in
                            Text(employee.name).tag(Optional(employee.id))
                        }
                    }
                    TextField("Team / staff note", text: $staffName)
                }
                Section("Work") {
                    TextField("Work completed", text: $workDone, axis: .vertical).lineLimit(2...5)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Log Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let selectedName = store.employee(id: employeeID)?.name ?? staffName
                        store.addVisit(MaintenanceVisit(customerID: customer.id, date: date, staffName: selectedName, workDone: workDone, notes: notes, employeeID: employeeID))
                        dismiss()
                    }
                    .disabled(workDone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Invoices

private enum InvoiceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case draft = "Draft"
    case sent = "Sent"
    case overdue = "Overdue"
    case paid = "Paid"
    var id: String { rawValue }
}

struct InvoicesView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var filter: InvoiceFilter = .all
    @State private var searchText = ""
    @State private var showingNewInvoice = false
    @State private var showingBulkGenerate = false

    private var displayedInvoices: [Invoice] {
        store.invoices.filter { invoice in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .draft: matchesFilter = invoice.status == .draft
            case .sent: matchesFilter = invoice.status == .sent || invoice.status == .partial
            case .overdue: matchesFilter = invoice.isOverdue()
            case .paid: matchesFilter = invoice.status == .paid
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            let customerName = store.customer(id: invoice.customerID)?.name ?? ""
            return invoice.number.localizedCaseInsensitiveContains(searchText) || customerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(InvoiceFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if displayedInvoices.isEmpty {
                    FullEmptyView(title: "No Invoices", icon: "doc.text", message: "Create a monthly customer invoice or generate all monthly invoices together.")
                } else {
                    List(displayedInvoices) { invoice in
                        NavigationLink(value: invoice.id) { InvoiceRow(invoice: invoice) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Invoices")
            .searchable(text: $searchText, prompt: "Invoice number or customer")
            .navigationDestination(for: UUID.self) { id in InvoiceDetailView(invoiceID: id) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showingNewInvoice = true } label: { Label("Create Invoice", systemImage: "doc.badge.plus") }
                        Button { showingBulkGenerate = true } label: { Label("Generate Monthly Invoices", systemImage: "doc.on.doc") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNewInvoice) { ManualInvoiceView() }
            .sheet(isPresented: $showingBulkGenerate) { BulkInvoiceGeneratorView() }
        }
    }
}

struct InvoiceRow: View {
    @EnvironmentObject private var store: AspireStore
    var invoice: Invoice

    private var displayStatus: String {
        invoice.isOverdue() ? "Overdue \(invoice.overdueDays())d" : invoice.status.title
    }

    private var statusColor: Color {
        if invoice.isOverdue() { return .red }
        switch invoice.status {
        case .draft: return .secondary
        case .sent: return .blue
        case .partial: return .orange
        case .paid: return .aspireGreen
        case .void: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(statusColor.opacity(0.12))
                Image(systemName: invoice.status == .paid ? "checkmark.seal.fill" : "doc.text.fill").foregroundStyle(statusColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.customer(id: invoice.customerID)?.name ?? "Unknown Customer").font(.headline)
                Text(invoice.number).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text("Due \(DateFormatter.shortDate.string(from: invoice.dueDate))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(store.currency(invoice.total)).font(.subheadline.weight(.bold))
                Text(displayStatus)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 3)
    }
}

struct QuickInvoiceView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    @State private var month = Date()
    @State private var amount: Double
    @State private var employeeID: UUID?

    init(customer: Customer) {
        self.customer = customer
        _amount = State(initialValue: customer.monthlyRate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(customer.name) {
                    DatePicker("Service month", selection: $month, displayedComponents: .date)
                    TextField("Invoice amount", value: $amount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                    Picker("Job done by", selection: $employeeID) {
                        Text("Not selected").tag(UUID?.none)
                        ForEach(store.activeEmployees) { employee in Text(employee.name).tag(Optional(employee.id)) }
                    }
                }
                Section {
                    Text("The invoice will use the company payment terms and the monthly garden-maintenance description.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        _ = store.createMonthlyInvoice(for: customer, serviceMonth: month, customAmount: amount, employeeID: employeeID)
                        dismiss()
                    }.disabled(amount <= 0)
                }
            }
        }
    }
}

struct ManualInvoiceView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    var preselectedCustomer: Customer? = nil

    @State private var customerID: UUID?
    @State private var jobType: JobType = .oneTimeJob
    @State private var serviceDate = Date()
    @State private var lineItems: [InvoiceLineItem] = [InvoiceLineItem(description: "", quantity: 1, unitPrice: 0)]
    @State private var employeeID: UUID?
    @State private var notes = ""
    @State private var showingNewCustomer = false

    init(preselectedCustomer: Customer? = nil) {
        self.preselectedCustomer = preselectedCustomer
        _customerID = State(initialValue: preselectedCustomer?.id)
        _jobType = State(initialValue: preselectedCustomer.map { JobType(customerType: $0.resolvedType) } ?? .oneTimeJob)
    }

    private var validItems: [InvoiceLineItem] {
        lineItems.filter { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.quantity > 0 && $0.unitPrice >= 0 }
    }

    private var total: Double { validItems.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer & Job") {
                    Picker("Customer", selection: $customerID) {
                        Text("Select customer").tag(UUID?.none)
                        ForEach(store.activeCustomers) { customer in Text(customer.name).tag(Optional(customer.id)) }
                    }
                    Button { showingNewCustomer = true } label: {
                        Label("Customer not listed? Create Customer", systemImage: "person.badge.plus")
                    }
                    Picker("Job type", selection: $jobType) {
                        ForEach(JobType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    DatePicker("Service / job date", selection: $serviceDate, displayedComponents: .date)
                    Picker("Job done by", selection: $employeeID) {
                        Text("Not selected").tag(UUID?.none)
                        ForEach(store.activeEmployees) { employee in Text(employee.name).tag(Optional(employee.id)) }
                    }
                }

                Section("Items / Services") {
                    ForEach(lineItems) { item in
                        if let index = lineItems.firstIndex(where: { $0.id == item.id }) {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Item / service name", text: $lineItems[index].description, axis: .vertical).lineLimit(1...3)
                                TextField("Item details — shown in grey below the item name", text: lineDetailsBinding(item.id), axis: .vertical).lineLimit(1...4)
                                if let catalog = lineCatalog(item), !catalog.availableVariants.isEmpty {
                                    Picker("Variant / Color / Option", selection: lineVariantBinding(item.id)) {
                                        Text("Not selected").tag("")
                                        ForEach(catalog.availableVariants, id: \.self) { variant in Text(variant).tag(variant) }
                                    }
                                }
                                TextField("Variant / color / option (optional)", text: lineVariantBinding(item.id))
                                HStack {
                                    TextField("Qty", value: $lineItems[index].quantity, format: .number.precision(.fractionLength(0...2))).keyboardType(.decimalPad)
                                    TextField("Unit price", value: $lineItems[index].unitPrice, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                                }
                                if lineItems.count > 1 {
                                    Button(role: .destructive) {
                                        lineItems.removeAll { $0.id == item.id }
                                    } label: { Label("Remove Item", systemImage: "trash") }
                                    .font(.caption)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }

                    Menu {
                        ForEach(store.activeCatalogItems) { catalog in
                            Button {
                                lineItems.append(InvoiceLineItem(
                                    description: catalog.name,
                                    quantity: 1,
                                    unitPrice: catalog.unitPrice,
                                    details: catalog.details.isEmpty ? nil : catalog.details,
                                    variant: catalog.availableVariants.count == 1 ? catalog.availableVariants[0] : nil,
                                    catalogItemID: catalog.id
                                ))
                            } label: {
                                Text("\(catalog.name) • \(store.currency(catalog.unitPrice))")
                            }
                        }
                    } label: { Label("Add from Price List", systemImage: "list.bullet.rectangle") }
                    .disabled(store.activeCatalogItems.isEmpty)

                    Button {
                        lineItems.append(InvoiceLineItem(description: "", quantity: 1, unitPrice: 0))
                    } label: { Label("Add Custom Item", systemImage: "plus.circle") }
                }

                Section("Summary") {
                    LabeledContent("Invoice total", value: store.currency(total))
                    TextField("Terms / notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Manual Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(customerID == nil || validItems.isEmpty || total <= 0)
                }
            }
            .onChange(of: customerID) { id in
                guard let id, let customer = store.customer(id: id) else { return }
                jobType = JobType(customerType: customer.resolvedType)
            }
            .sheet(isPresented: $showingNewCustomer) {
                CustomerEditorView { customer in
                    customerID = customer.id
                    jobType = JobType(customerType: customer.resolvedType)
                }
            }
        }
    }

    private func lineDetailsBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { lineItems.first(where: { $0.id == id })?.details ?? "" },
            set: { value in
                guard let index = lineItems.firstIndex(where: { $0.id == id }) else { return }
                lineItems[index].details = value
            }
        )
    }

    private func lineVariantBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { lineItems.first(where: { $0.id == id })?.variant ?? "" },
            set: { value in
                guard let index = lineItems.firstIndex(where: { $0.id == id }) else { return }
                lineItems[index].variant = value
            }
        )
    }

    private func lineCatalog(_ item: InvoiceLineItem) -> CatalogItem? {
        guard let catalogItemID = item.catalogItemID else { return nil }
        return store.catalogItem(id: catalogItemID)
    }

    private func create() {
        guard let customerID, let customer = store.customer(id: customerID) else { return }
        _ = store.createManualInvoice(
            for: customer,
            jobType: jobType,
            serviceDate: serviceDate,
            lineItems: validItems,
            employeeID: employeeID,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        dismiss()
    }
}

struct BulkInvoiceGeneratorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    @State private var generatedCount: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly Billing") {
                    DatePicker("Service month", selection: $month, displayedComponents: .date)
                    LabeledContent("Monthly-maintenance customers", value: "\(store.monthlyMaintenanceCustomers.count)")
                }
                Section {
                    Text("One invoice will be created only for active monthly-maintenance customers that do not already have an invoice for the selected service month.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let generatedCount {
                    Section { Label("Generated \(generatedCount) new invoice(s)", systemImage: "checkmark.circle.fill").foregroundStyle(Color.aspireGreen) }
                }
            }
            .navigationTitle("Generate Invoices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") { generatedCount = store.generateMonthlyInvoices(for: month).count }
                        .disabled(store.monthlyMaintenanceCustomers.isEmpty)
                }
            }
        }
    }
}

struct InvoiceDetailView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let invoiceID: UUID
    @State private var mailDraft: MailDraft?
    @State private var shareItems: ShareItems?
    @State private var showingDelete = false
    @State private var showingPDFEditor = false
    @State private var showingInvoiceEditor = false
    @State private var showingEditHistory = false
    @State private var showingPaymentEntry = false
    @State private var sending = false
    @State private var resultMessage: String?
    @State private var previewItem: GeneratedPDFPreviewItem?

    var body: some View {
        Group {
            if let invoice = store.invoice(id: invoiceID), let customer = store.customer(id: invoice.customerID) {
                ScrollView {
                    VStack(spacing: 16) {
                        invoiceHeader(invoice: invoice, customer: customer)
                        invoiceItems(invoice: invoice)
                        paymentSummary(invoice: invoice)
                        if let revisions = invoice.revisions, !revisions.isEmpty {
                            revisionHistory(revisions)
                        }
                        actionButtons(invoice: invoice, customer: customer)
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(invoice.number)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button { showingInvoiceEditor = true } label: {
                                Label("Edit Invoice Items", systemImage: "square.and.pencil")
                            }
                            .disabled(invoice.status == .paid || invoice.status == .void)
                            Button { showingPDFEditor = true } label: { Label("Edit PDF / Logo", systemImage: "doc.richtext") }
                            Divider()
                            Button(role: .destructive) { showingDelete = true } label: { Label("Delete Invoice", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .sheet(item: $mailDraft) { draft in
                    MailComposer(draft: draft) { result in
                        if result == .sent { store.markInvoiceSent(invoice.id); resultMessage = "Invoice sent using Apple Mail." }
                    }
                }
                .sheet(item: $shareItems) { payload in ShareSheet(items: payload.items) }
                .sheet(item: $previewItem) { GeneratedPDFPreviewSheet(item: $0) }
                .sheet(isPresented: $showingPDFEditor) { InvoiceReportCenterView(sampleInvoiceID: invoice.id) }
                .sheet(isPresented: $showingInvoiceEditor) {
                    AspireInvoiceEditorView(invoice: invoice) { changed in
                        resultMessage = changed
                            ? "Invoice updated. Please send the revised PDF to your customer."
                            : "No invoice changes were made."
                    }
                }
                .sheet(isPresented: $showingPaymentEntry) { PaymentEntryView(invoice: invoice) }
                .confirmationDialog("Delete this invoice?", isPresented: $showingDelete, titleVisibility: .visible) {
                    Button("Delete Invoice", role: .destructive) { store.deleteInvoice(invoice.id); dismiss() }
                }
                .alert("Invoice", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: { Text(resultMessage ?? "") }
            } else {
                FullEmptyView(title: "Invoice Not Found", icon: "doc.badge.exclamationmark", message: "The invoice record is no longer available.")
            }
        }
    }

    private func invoiceHeader(invoice: Invoice, customer: Customer) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(customer.name).font(.title3.bold())
                    Text(DateFormatter.monthAndYear.string(from: invoice.serviceMonth)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.currency(invoice.total)).font(.title2.bold()).foregroundStyle(Color.aspireGreen)
                    Text(invoice.isOverdue() ? "OVERDUE" : invoice.status.title.uppercased())
                        .font(.caption.weight(.heavy)).foregroundStyle(invoice.isOverdue() ? .red : Color.aspireGreen)
                }
            }
            Divider()
            HStack {
                LabeledContent("Issue", value: DateFormatter.shortDate.string(from: invoice.issueDate))
                Spacer()
                LabeledContent("Due", value: DateFormatter.shortDate.string(from: invoice.dueDate))
            }
            .font(.caption)
        }
        .aspirePanel()
    }

    private func invoiceItems(invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Invoice Items", subtitle: nil)
            ForEach(invoice.lineItems) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(item.description).font(.subheadline.weight(.semibold))
                        if item.hasSecondaryText {
                            Text(item.secondaryDisplayText).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(item.quantity, specifier: "%.2f") × \(store.currency(item.unitPrice))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(store.currency(item.amount)).font(.subheadline.weight(.bold))
                }
            }
        }
        .aspirePanel()
    }

    private func paymentSummary(invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Payment", subtitle: invoice.notes)
            LabeledContent("Invoice total", value: store.currency(invoice.total))
            LabeledContent("Paid", value: store.currency(invoice.amountPaid))
            LabeledContent("Outstanding", value: store.currency(invoice.outstanding)).font(.headline)
        }
        .aspirePanel()
    }

    private func revisionHistory(_ revisions: [InvoiceRevision]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $showingEditHistory) {
                ForEach(Array(revisions.enumerated().reversed()), id: \.offset) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Revision \(entry.offset + 1)")
                            .font(.subheadline.weight(.semibold))
                        Text(DateFormatter.backupDateTime.string(from: entry.element.revisedAt))
                            .font(.caption).foregroundStyle(.secondary)
                        LabeledContent("Previous total", value: store.currency(entry.element.previousTotal))
                        LabeledContent("New total", value: store.currency(entry.element.updatedTotal))
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }
            } label: {
                Label("Edit History • \(revisions.count) revisions", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .aspirePanel()
    }

    private func actionButtons(invoice: Invoice, customer: Customer) -> some View {
        VStack(spacing: 10) {
            if invoice.status != .paid && invoice.status != .void {
                ActionButton(title: "Edit Invoice", icon: "square.and.pencil", style: .neutral) {
                    showingInvoiceEditor = true
                }
            }
            ActionButton(
                title: sending ? "Sending…" :
                    ((invoice.revisions?.isEmpty == false) ? "Send Revised Invoice" : "Send Invoice"),
                icon: "paperplane.fill", style: .green
            ) {
                Task { await sendInvoice(invoice: invoice, customer: customer) }
            }
            .disabled(sending || customer.email.isEmpty)

            ActionButton(title: "Preview Invoice PDF", icon: "eye.fill", style: .green) {
                previewItem = GeneratedPDFPreviewItem(title: invoice.number, data: pdf(invoice: invoice, customer: customer))
            }

            ActionButton(title: "Download / Share Invoice PDF", icon: "arrow.down.doc.fill", style: .neutral) {
                sharePDF(invoice: invoice, customer: customer)
            }

            HStack(spacing: 10) {
                ActionButton(title: "Record Payment", icon: "creditcard.fill", style: .neutral) { showingPaymentEntry = true }
                    .disabled(invoice.status == .void || invoice.status == .paid)
                ActionButton(
                    title: invoice.status == .paid ? "PAID • Unmark" : "MARK PAID",
                    icon: invoice.status == .paid ? "checkmark.seal.fill" : "banknote.fill",
                    style: invoice.status == .paid ? .green : .gold
                ) { store.toggleInvoicePayment(invoice.id) }
                    .disabled(invoice.status == .void)
            }

            if invoice.status == .paid {
                ActionButton(title: "Preview Payment Receipt", icon: "eye", style: .green) {
                    previewItem = GeneratedPDFPreviewItem(title: "Receipt - \(invoice.number)", data: receiptData(invoice: invoice, customer: customer))
                }
                ActionButton(title: "Download Payment Receipt", icon: "checkmark.seal.fill", style: .green) {
                    shareReceipt(invoice: invoice, customer: customer)
                }
            }
        }
    }

    private func pdf(invoice: Invoice, customer: Customer) -> Data {
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

    private func emailBody(invoice: Invoice, customer: Customer) -> String {
        """
        Dear \(customer.name),

        Please find attached invoice \(invoice.number) for \(DateFormatter.monthAndYear.string(from: invoice.serviceMonth)) garden maintenance services.

        Invoice total: \(store.currency(invoice.total))
        Due date: \(DateFormatter.shortDate.string(from: invoice.dueDate))

        \(store.emailConfiguration.signature)
        """
    }

    private func sendInvoice(invoice: Invoice, customer: Customer) async {
        let data = pdf(invoice: invoice, customer: customer)
        let fileName = "\(invoice.number).pdf"
        let subject = "Aspire Garden Invoice \(invoice.number)"
        let body = emailBody(invoice: invoice, customer: customer)
        let config = store.emailConfiguration

        if config.preferredMode == .gmailDirect {
            sending = true
            do {
                let message = try await DirectEmailService().send(
                    recipient: customer.email,
                    subject: subject,
                    body: body,
                    attachments: [DirectEmailAttachment(fileName: fileName, mimeType: "application/pdf", data: data)],
                    configuration: config,
                    apiKey: SecureStore.load(account: "scheduler-api-key")
                )
                store.markInvoiceSent(invoice.id)
                resultMessage = message
            } catch {
                resultMessage = error.localizedDescription
            }
            sending = false
        } else if MFMailComposeViewController.canSendMail() {
            mailDraft = MailDraft(recipient: customer.email, subject: subject, body: body, attachmentData: data, attachmentName: fileName)
        } else {
            do {
                let url = try TemporaryFileService.write(data: data, fileName: fileName)
                shareItems = ShareItems(items: [body, url])
                resultMessage = "Apple Mail is unavailable. The iOS share sheet was opened instead."
            } catch {
                resultMessage = error.localizedDescription
            }
        }
    }

    private func sharePDF(invoice: Invoice, customer: Customer) {
        do {
            let url = try TemporaryFileService.write(data: pdf(invoice: invoice, customer: customer), fileName: "\(invoice.number).pdf")
            shareItems = ShareItems(items: [url])
        } catch {
            resultMessage = error.localizedDescription
        }
    }

    private func receiptData(invoice: Invoice, customer: Customer) -> Data {
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

    private func shareReceipt(invoice: Invoice, customer: Customer) {
        let data = receiptData(invoice: invoice, customer: customer)
        do {
            let url = try TemporaryFileService.write(data: data, fileName: "Receipt-\(invoice.number).pdf")
            shareItems = ShareItems(items: [url])
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}

struct PaymentEntryView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let invoice: Invoice
    @State private var amount: Double
    @State private var date = Date()

    init(invoice: Invoice) {
        self.invoice = invoice
        _amount = State(initialValue: invoice.outstanding)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(invoice.number) {
                    LabeledContent("Outstanding", value: CurrencyFormatter.string(invoice.outstanding, code: "AED"))
                    TextField("Payment amount", value: $amount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                    DatePicker("Payment date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.recordPayment(invoiceID: invoice.id, amount: amount, paymentDate: date); dismiss() }
                        .disabled(amount <= 0)
                }
            }
        }
    }
}

// MARK: - Finance

struct FinanceView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var month = Date()
    @State private var showingExpense = false
    @State private var showingInvoices = false
    @State private var batchResultMessage: String?

    private var monthExpenses: [Expense] {
        store.expensesForMonth(month)
    }

    private var monthlyInvoicesForSelectedMonth: [Invoice] {
        store.invoicesForServiceMonth(month).filter { invoice in
            (invoice.jobType ?? .monthlyMaintenance) == .monthlyMaintenance && invoice.status != .void
        }
    }

    private var missingMonthlyInvoiceCount: Int {
        store.monthlyMaintenanceCustomers.filter { customer in
            !monthlyInvoicesForSelectedMonth.contains { $0.customerID == customer.id }
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthPicker(month: $month)
                    let income = store.invoicedIncome(in: month)
                    let costs = store.expensesTotal(in: month)
                    let profit = income - costs

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Profit & Loss", subtitle: DateFormatter.monthAndYear.string(from: month))
                        FinanceLine(title: "Invoice Income", amount: income, store: store)
                        FinanceLine(title: "Expenses", amount: -costs, store: store)
                        Divider()
                        FinanceLine(title: profit >= 0 ? "Net Profit" : "Net Loss", amount: profit, store: store, emphasized: true)
                    }
                    .aspirePanel()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "Monthly Maintenance Billing",
                            subtitle: "Create routine month-end invoices for all active monthly customers"
                        )

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Monthly Customers").font(.caption).foregroundStyle(.secondary)
                                Text("\(store.monthlyMaintenanceCustomers.count)").font(.title3.bold())
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Still to Invoice").font(.caption).foregroundStyle(.secondary)
                                Text("\(missingMonthlyInvoiceCount)")
                                    .font(.title3.bold())
                                    .foregroundStyle(missingMonthlyInvoiceCount > 0 ? Color.orange : Color.aspireGreen)
                            }
                        }

                        Button {
                            let generated = store.generateMonthlyInvoices(for: month)
                            if generated.isEmpty {
                                batchResultMessage = "No new invoices were needed for \(DateFormatter.monthAndYear.string(from: month)). Existing invoices were left unchanged."
                            } else {
                                batchResultMessage = "Created \(generated.count) monthly maintenance invoice\(generated.count == 1 ? "" : "s") for \(DateFormatter.monthAndYear.string(from: month))."
                            }
                        } label: {
                            Label(
                                missingMonthlyInvoiceCount > 0
                                    ? "Generate \(missingMonthlyInvoiceCount) Month-End Invoice\(missingMonthlyInvoiceCount == 1 ? "" : "s")"
                                    : "Monthly Invoices Up to Date",
                                systemImage: missingMonthlyInvoiceCount > 0 ? "doc.on.doc.fill" : "checkmark.seal.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.aspireGreen)
                        .disabled(store.monthlyMaintenanceCustomers.isEmpty || missingMonthlyInvoiceCount == 0)

                        Button { showingInvoices = true } label: {
                            Label("View / Send Monthly Invoices", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if let batchResultMessage {
                            Label(batchResultMessage, systemImage: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(Color.aspireGreen)
                        }
                    }
                    .aspirePanel()

                    AgingView(summary: store.agingSummary())

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(title: "Expenses", subtitle: "Fuel and company costs")
                            Spacer()
                            Button { showingExpense = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(.aspireGreen)
                        }
                        if monthExpenses.isEmpty {
                            EmptyInlineView(icon: "fuelpump", text: "No expenses recorded for this month")
                        } else {
                            ForEach(monthExpenses) { expense in
                                NavigationLink { ExpenseDetailView(expenseID: expense.id) } label: {
                                    ExpenseRow(expense: expense)
                                }
                                .buttonStyle(.plain)
                                if expense.id != monthExpenses.last?.id { Divider() }
                            }
                        }
                    }
                    .aspirePanel()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Finance")
            .sheet(isPresented: $showingExpense) { ExpenseEditorView() }
            .sheet(isPresented: $showingInvoices) { InvoicesView() }
        }
    }
}

struct AgingView: View {
    @EnvironmentObject private var store: AspireStore
    var summary: AgingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Receivables Aging", subtitle: "Unpaid customer invoices")
            AgingRow(label: "Current / Not Due", amount: summary.current)
            AgingRow(label: "1–30 Days", amount: summary.days1To30)
            AgingRow(label: "31–60 Days", amount: summary.days31To60)
            AgingRow(label: "61–90 Days", amount: summary.days61To90)
            AgingRow(label: "Over 90 Days", amount: summary.over90, warning: summary.over90 > 0)
            Divider()
            AgingRow(label: "Total Receivables", amount: summary.total, emphasized: true)
        }
        .aspirePanel()
    }
}

struct ExpenseRow: View {
    @EnvironmentObject private var store: AspireStore
    var expense: Expense

    var body: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Color.aspireGold.opacity(0.15))
                Image(systemName: expense.category == .fuel ? "fuelpump.fill" : "receipt.fill").foregroundStyle(Color.aspireGold)
            }.frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.vendor.isEmpty ? expense.category.rawValue : expense.vendor).font(.subheadline.weight(.semibold))
                Text("\(expense.category.rawValue) • \(DateFormatter.shortDate.string(from: expense.date))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.currency(store.netAmount(for: expense))).font(.subheadline.weight(.bold))
                let refunded = store.refunds(for: expense.id).reduce(0) { $0 + $1.amount }
                if refunded > 0 {
                    Text("Refunded \(store.currency(refunded))").font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }
}

struct ExpenseEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var category: ExpenseCategory = .fuel
    @State private var vendor = ""
    @State private var amountText = ""
    @State private var paymentAccount = "Cash"
    @State private var notes = ""
    @State private var saveError: String?

    private var parsedAmount: Double? {
        var cleaned = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.contains(",") && cleaned.contains(".") { cleaned = cleaned.replacingOccurrences(of: ",", with: "") }
        else { cleaned = cleaned.replacingOccurrences(of: ",", with: ".") }
        guard let value = Double(cleaned), value.isFinite, value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Category", selection: $category) { ForEach(ExpenseCategory.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Vendor / payee", text: $vendor)
                    TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                    TextField("Paid from", text: $paymentAccount)
                }
                Section("Notes") { TextField("Description or receipt reference", text: $notes, axis: .vertical).lineLimit(2...5) }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveExpense() }.disabled(parsedAmount == nil) }
            }
            .alert("Expense Not Saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "Enter a valid amount.") }
        }
    }

    private func saveExpense() {
        guard let amount = parsedAmount else { saveError = "Enter a valid expense amount greater than zero."; return }
        let expense = Expense(date: date, category: category, vendor: vendor.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount, paymentAccount: paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        if store.addExpense(expense) { dismiss() }
        else { saveError = store.lastErrorMessage ?? "The expense could not be saved." }
    }
}

// MARK: - Settings

struct LegacySettingsView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var company = CompanyProfile.aspireDefault
    @State private var emailConfig = EmailConfiguration.aspireDefault
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var message: String?
    @State private var shareItems: ShareItems?
    @State private var importing = false

    var body: some View {
        NavigationStack {
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

                Section("Invoice & Bank Details") {
                    TextField("Invoice prefix", text: $company.invoicePrefix)
                    TextField("Currency", text: $company.currencyCode)
                    Stepper("Payment terms: \(company.paymentTermsDays) days", value: $company.paymentTermsDays, in: 0...90)
                    Stepper("Long overdue alert: \(company.longOverdueDays) days", value: $company.longOverdueDays, in: 7...180)
                    TextField("Bank name", text: $company.bankName)
                    TextField("Account holder", text: $company.accountHolderName)
                    TextField("Account number", text: $company.accountNumber)
                    TextField("IBAN", text: $company.iban).textInputAutocapitalization(.characters)
                    TextField("SWIFT", text: $company.swiftCode).textInputAutocapitalization(.characters)
                    TextField("Invoice terms", text: $company.invoiceTerms, axis: .vertical).lineLimit(2...5)
                }

                Section("Invoice Email Delivery") {
                    Picker("Preferred method", selection: $emailConfig.preferredMode) {
                        ForEach(EmailDeliveryMode.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Scheduler HTTPS URL", text: $emailConfig.schedulerEndpoint).textInputAutocapitalization(.never).keyboardType(.URL)
                    SecureField("Scheduler API key", text: $apiKey)
                    TextField("Email signature", text: $emailConfig.signature, axis: .vertical).lineLimit(3...6)

                    if emailConfig.connectorID.isEmpty {
                        Button {
                            connectGmail()
                        } label: {
                            Label(isConnecting ? "Connecting…" : "Connect Gmail", systemImage: "envelope.badge")
                        }
                        .disabled(isConnecting || emailConfig.schedulerEndpoint.isEmpty || apiKey.isEmpty)
                    } else {
                        LabeledContent("Connected account", value: emailConfig.connectedEmail)
                        Button("Disconnect Gmail", role: .destructive) { disconnectGmail() }
                    }

                    Text("Gmail Direct uses the same scheduler/connector approach as Next Job. Apple Mail Assisted opens the standard iOS mail composer for confirmation.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Alerts & Data") {
                    Button { Task { await store.requestNotificationsAndRefresh() } } label: { Label("Enable Overdue Alerts", systemImage: "bell.badge.fill") }
                    Button { exportBackup() } label: { Label("Export Complete Backup", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Import Backup", systemImage: "square.and.arrow.down") }
                    Button("Add Demo Data for Testing") { store.addDemoData(); message = "Demo customer, invoice and fuel expense added." }
                }

                Section("Application") {
                    LabeledContent("Name", value: "Aspire Maintenance")
                    LabeledContent("Company", value: "Aspire Green Garden Designing and Works LLC")
                    LabeledContent("Version", value: "1.0.0 Test")
                    Text("This build is branded only for Aspire. It does not use Next Solution or Bin Noman branding in the app or generated invoices.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Save") { saveSettings() } }
            }
            .onAppear {
                company = store.company
                emailConfig = store.emailConfiguration
                apiKey = SecureStore.load(account: "scheduler-api-key")
            }
            .sheet(item: $shareItems) { payload in ShareSheet(items: payload.items) }
            .sheet(isPresented: $importing) {
                AspireBackupDocumentPicker { url in
                    importing = false
                    importBackup(from: url)
                } onCancel: {
                    importing = false
                }
                .ignoresSafeArea()
            }
            .alert("Aspire Maintenance", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }

    private func importBackup(from url: URL) {
        do {
            let backupData = try AspireBackupFileReader.readData(from: url)
            try store.importData(backupData)
            company = store.company
            emailConfig = store.emailConfiguration
            message = "Backup imported successfully. \(store.customers.count) customer(s), \(store.invoices.count) invoice(s), \(store.visits.count) visit(s) and \(store.expenses.count) expense(s) restored."
        } catch {
            message = "Backup import failed: \(error.localizedDescription)"
        }
    }

    private func saveSettings() {
        store.updateCompany(company)
        store.updateEmailConfiguration(emailConfig)
        do {
            if apiKey.isEmpty { SecureStore.delete(account: "scheduler-api-key") }
            else { try SecureStore.save(apiKey, account: "scheduler-api-key") }
            message = "Company, invoice and email settings saved."
        } catch {
            message = error.localizedDescription
        }
    }

    private func connectGmail() {
        saveSettings()
        isConnecting = true
        Task {
            do {
                let record = try await GmailOAuthClient.shared.connect(configuration: emailConfig, apiKey: apiKey)
                emailConfig.connectorID = record.connectorID
                emailConfig.connectedEmail = record.emailAddress
                store.updateEmailConfiguration(emailConfig)
                message = "Gmail connected: \(record.emailAddress)"
            } catch {
                message = error.localizedDescription
            }
            isConnecting = false
        }
    }

    private func disconnectGmail() {
        isConnecting = true
        Task {
            do {
                try await GmailOAuthClient.shared.disconnect(configuration: emailConfig, apiKey: apiKey)
                emailConfig.connectorID = ""
                emailConfig.connectedEmail = ""
                store.updateEmailConfiguration(emailConfig)
                message = "Gmail disconnected."
            } catch {
                message = error.localizedDescription
            }
            isConnecting = false
        }
    }

    private func exportBackup() {
        do {
            let data = try store.exportData()
            let url = try TemporaryFileService.write(data: data, fileName: "Aspire-Maintenance-Backup-\(DateFormatter.invoiceMonth.string(from: Date())).json")
            shareItems = ShareItems(items: [url])
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Shared Components

struct AspireHeaderCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image("AspireLogo").resizable().scaledToFit().frame(maxWidth: 300, maxHeight: 150)
                .accessibilityLabel("Aspire Green Garden Designing and Works LLC logo")
            Text("Garden Maintenance • Customers • Invoices • Profit & Loss")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .aspirePanel()
    }
}

struct MonthPicker: View {
    @Binding var month: Date

    var body: some View {
        HStack {
            Button { month = Calendar.current.addingMonths(-1, to: month) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(DateFormatter.monthAndYear.string(from: month)).font(.headline)
            Spacer()
            Button { month = Calendar.current.addingMonths(1, to: month) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.bordered)
        .tint(.aspireGreen)
        .aspirePanel()
    }
}

struct SummaryCard: View {
    var title: String
    var value: String
    var subtitle: String
    var icon: String
    var emphasized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon).foregroundStyle(emphasized ? Color.aspireGold : Color.aspireGreen)
                Spacer()
            }
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(emphasized ? Color.aspireGreen.opacity(0.09) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(emphasized ? Color.aspireGreen.opacity(0.25) : Color.clear, lineWidth: 1))
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct MetricPill: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.65)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FullEmptyView: View {
    var title: String
    var icon: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 42)).foregroundStyle(Color.aspireGreen)
            Text(title).font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct EmptyInlineView: View {
    var icon: String
    var text: String
    var body: some View {
        HStack { Image(systemName: icon).foregroundStyle(Color.aspireGreen); Text(text).font(.subheadline).foregroundStyle(.secondary); Spacer() }
        .padding(.vertical, 8)
    }
}

struct LabeledValue: View {
    var icon: String
    var value: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) { Image(systemName: icon).foregroundStyle(Color.aspireGreen).frame(width: 20); Text(value).font(.subheadline); Spacer() }
    }
}

struct FinanceLine: View {
    var title: String
    var amount: Double
    var store: AspireStore
    var emphasized = false
    var body: some View {
        HStack {
            Text(title).font(emphasized ? .headline : .body)
            Spacer()
            Text(store.currency(amount)).font(emphasized ? .headline : .body).foregroundStyle(amount < 0 ? .red : (emphasized ? Color.aspireGreen : .primary))
        }
    }
}

struct AgingRow: View {
    @EnvironmentObject private var store: AspireStore
    var label: String
    var amount: Double
    var warning = false
    var emphasized = false
    var body: some View {
        HStack {
            Text(label).font(emphasized ? .headline : .subheadline)
            Spacer()
            Text(store.currency(amount)).font(emphasized ? .headline : .subheadline.weight(.semibold)).foregroundStyle(warning ? .red : .primary)
        }
    }
}

enum ActionButtonStyle { case green, gold, neutral }

struct ActionButton: View {
    var title: String
    var icon: String
    var style: ActionButtonStyle
    var action: () -> Void

    private var foreground: Color {
        switch style { case .green: return .white; case .gold: return .black; case .neutral: return .primary }
    }
    private var background: Color {
        switch style { case .green: return .aspireGreen; case .gold: return .aspireGold; case .neutral: return Color(.secondarySystemGroupedBackground) }
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(background, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
    }
}

struct ShareItems: Identifiable {
    let id = UUID()
    var items: [Any]
}

extension View {
    func aspirePanel() -> some View {
        self.padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension Color {
    static var aspireGreen: Color { AspireAppTheme.selected.primary }
    static var aspireGold: Color { AspireAppTheme.selected.accent }
}
