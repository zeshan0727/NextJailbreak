import Foundation
import UserNotifications

// MARK: - Core Models

struct CompanyProfile: Codable, Equatable {
    var fullName: String
    var tradingName: String
    var address: String
    var phone: String
    var email: String
    var website: String
    var taxRegistrationNumber: String
    var bankName: String
    var accountHolderName: String
    var accountNumber: String
    var iban: String
    var swiftCode: String
    var currencyCode: String
    var invoicePrefix: String
    var paymentTermsDays: Int
    var invoiceTerms: String
    var longOverdueDays: Int

    static let aspireDefault = CompanyProfile(
        fullName: "Aspire Green Garden Designing and Works LLC",
        tradingName: "Aspire Garden",
        address: "United Arab Emirates",
        phone: "+971 58 608 0000",
        email: "sales@aspiregroupae.com",
        website: "aspiregroupae.com",
        taxRegistrationNumber: "",
        bankName: "",
        accountHolderName: "",
        accountNumber: "",
        iban: "",
        swiftCode: "",
        currencyCode: "AED",
        invoicePrefix: "ASP",
        paymentTermsDays: 7,
        invoiceTerms: "Kindly transfer the invoice amount to the company bank account. Thank you.",
        longOverdueDays: 30
    )
}

struct Customer: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var address: String
    var email: String
    var phone: String
    var monthlyRate: Double
    var plannedVisitsPerMonth: Int
    var notes: String
    var isActive: Bool
    /// Nil in older backups; nil is treated as monthly maintenance for backward compatibility.
    var customerType: CustomerType? = nil
    /// Optional for backward-compatible decoding. Archived customers remain in history but are hidden from active workflows.
    var isArchived: Bool? = nil
    var createdAt: Date = Date()
}

struct MaintenanceVisit: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var customerID: UUID
    var date: Date
    var staffName: String
    var workDone: String
    var notes: String
    var employeeID: UUID? = nil
    /// Planned monthly visit slot (1st, 2nd, 3rd...). Optional keeps older backups compatible.
    var visitNumber: Int? = nil
}

/// Planned future visit for a monthly-maintenance customer. Stored separately from completed
/// MaintenanceVisit records so scheduling never changes service history.
struct ScheduledMaintenanceVisit: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var customerID: UUID
    var slot: Int
    var scheduledAt: Date
    var createdAt: Date = Date()
}

struct InvoiceLineItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var description: String
    var quantity: Double
    var unitPrice: Double
    /// Optional supporting detail shown beneath the item name on quotations/invoices.
    var details: String? = nil
    /// Optional selected variant such as stone colour, size, finish or service option.
    var variant: String? = nil
    /// Optional link back to the reusable price-list item so its configured variants remain available while editing.
    var catalogItemID: UUID? = nil

    var amount: Double { quantity * unitPrice }
    var resolvedDetails: String { (details ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    var resolvedVariant: String { (variant ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasSecondaryText: Bool { !resolvedDetails.isEmpty || !resolvedVariant.isEmpty }
    var secondaryDisplayText: String {
        var lines: [String] = []
        if !resolvedVariant.isEmpty { lines.append("Variant: \(resolvedVariant)") }
        if !resolvedDetails.isEmpty { lines.append(resolvedDetails) }
        return lines.joined(separator: "\n")
    }
}

enum InvoiceStatus: String, CaseIterable, Codable, Identifiable {
    case draft
    case sent
    case partial
    case paid
    case void

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .partial: return "Part Paid"
        case .paid: return "Paid"
        case .void: return "Void"
        }
    }
}

// Previous versions remain available for an audit trail when an issued invoice is revised.
struct InvoiceRevision: Codable, Hashable {
    var revisedAt: Date
    var previousLineItems: [InvoiceLineItem]
    var previousDueDate: Date
    var previousNotes: String
    var previousEmployeeID: UUID?
    var previousTotal: Double
    var updatedTotal: Double
}

enum AspireInvoiceEditError: LocalizedError {
    case unavailable, changedOnAnotherDevice, invalidLines, belowAmountReceived

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Paid and void invoices cannot be edited. Use an adjustment document instead."
        case .changedOnAnotherDevice: return "The invoice changed while you were editing it. Close and reopen to see the latest version."
        case .invalidLines: return "Add at least one valid line item and a positive invoice total."
        case .belowAmountReceived: return "The revised invoice total cannot be less than the payment already received."
        }
    }
}

struct Invoice: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var number: String
    var customerID: UUID
    var issueDate: Date
    var dueDate: Date
    var serviceMonth: Date
    var lineItems: [InvoiceLineItem]
    var status: InvoiceStatus
    var amountPaid: Double
    var notes: String
    var sentAt: Date?
    var paidAt: Date?
    var employeeID: UUID? = nil
    /// Nil in older backups; nil is treated as monthly maintenance for backward compatibility.
    var jobType: JobType? = nil
    var createdAt: Date = Date()
    /// Optional so all existing 1.2.2 invoices and backups decode unchanged.
    var revisions: [InvoiceRevision]? = nil

    var total: Double { lineItems.reduce(0) { $0 + $1.amount } }
    var outstanding: Double { max(0, total - amountPaid) }

    func isOverdue(asOf date: Date = Date()) -> Bool {
        status != .paid && status != .void && outstanding > 0 && dueDate < Calendar.current.startOfDay(for: date)
    }

    func overdueDays(asOf date: Date = Date()) -> Int {
        guard isOverdue(asOf: date) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: dueDate, to: date).day ?? 0)
    }
}

enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case fuel = "Fuel"
    case salaries = "Salaries & Labour"
    case plants = "Plants & Materials"
    case equipment = "Tools & Equipment"
    case vehicle = "Vehicle & Transport"
    case subcontractor = "Subcontractor"
    case utilities = "Utilities"
    case office = "Office & Administration"
    case other = "Other"

    var id: String { rawValue }
}

struct Expense: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var category: ExpenseCategory
    var vendor: String
    var amount: Double
    var paymentAccount: String
    var notes: String
}

enum EmailDeliveryMode: String, CaseIterable, Codable, Identifiable {
    case gmailDirect
    case appleMail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gmailDirect: return "Gmail Direct"
        case .appleMail: return "Apple Mail Assisted"
        }
    }
}

struct EmailConfiguration: Codable, Equatable {
    var schedulerEndpoint: String
    var connectorID: String
    var connectedEmail: String
    var signature: String
    var preferredMode: EmailDeliveryMode

    static let aspireDefault = EmailConfiguration(
        schedulerEndpoint: "",
        connectorID: "",
        connectedEmail: "",
        signature: "Thank you,\nAspire Green Garden Designing and Works LLC",
        preferredMode: .gmailDirect
    )
}

struct AspireData: Codable {
    var company: CompanyProfile
    var customers: [Customer]
    var visits: [MaintenanceVisit]
    var invoices: [Invoice]
    var expenses: [Expense]
    var emailConfiguration: EmailConfiguration

    // Optional for backward-compatible decoding of 1.0.x backups.
    var employees: [Employee]?
    var bankAccounts: [BankAccount]?
    var advancePayments: [AdvancePayment]?
    var expenseRefunds: [ExpenseRefund]?
    var invoicePDFSettings: InvoicePDFSettings?
    var quotationPDFSettings: InvoicePDFSettings?
    var receiptPDFSettings: InvoicePDFSettings?
    var appLogoData: Data?
    var catalogItems: [CatalogItem]?
    var quotations: [Quotation]?
    /// Optional for backward-compatible decoding. Future visit scheduling was added in 1.1.4.
    var visitSchedules: [ScheduledMaintenanceVisit]?

    static let empty = AspireData(
        company: .aspireDefault,
        customers: [],
        visits: [],
        invoices: [],
        expenses: [],
        emailConfiguration: .aspireDefault,
        employees: [],
        bankAccounts: [],
        advancePayments: [],
        expenseRefunds: [],
        invoicePDFSettings: .aspireDefault,
        quotationPDFSettings: .aspireQuotationDefault,
        receiptPDFSettings: .aspireReceiptDefault,
        appLogoData: nil,
        catalogItems: [],
        quotations: [],
        visitSchedules: []
    )
}

struct AgingSummary {
    var current: Double = 0
    var days1To30: Double = 0
    var days31To60: Double = 0
    var days61To90: Double = 0
    var over90: Double = 0

    var total: Double { current + days1To30 + days31To60 + days61To90 + over90 }
}

// MARK: - Store

@MainActor
final class AspireStore: ObservableObject {
    @Published private(set) var data: AspireData
    @Published var lastErrorMessage: String?
    @Published private(set) var automaticCloudBackupEnabled: Bool
    @Published private(set) var cloudBackupStatus: String
    @Published private(set) var lastCloudBackupAt: Date?
    @Published private(set) var lastCloudBackupLocation: String
    @Published private(set) var iCloudAccessDiagnostic: String

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dataURL: URL
    private var pendingCloudBackup: DispatchWorkItem?

    private enum BackupPreferenceKeys {
        static let enabled = "aspire.backup.icloud.enabled"
        static let lastDate = "aspire.backup.icloud.lastDate"
        static let lastLocation = "aspire.backup.icloud.lastLocation"
    }

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let defaults = UserDefaults.standard
        let backupEnabled = defaults.object(forKey: BackupPreferenceKeys.enabled) as? Bool ?? true
        automaticCloudBackupEnabled = backupEnabled
        lastCloudBackupAt = defaults.object(forKey: BackupPreferenceKeys.lastDate) as? Date
        lastCloudBackupLocation = defaults.string(forKey: BackupPreferenceKeys.lastLocation) ?? "Not backed up yet"
        cloudBackupStatus = backupEnabled ? "Automatic backup enabled" : "Automatic backup disabled"
        iCloudAccessDiagnostic = "Not checked"

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("AspireMaintenance", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dataURL = directory.appendingPathComponent("aspire-maintenance-data.json")

        if let stored = try? Data(contentsOf: dataURL),
           let decoded = try? decoder.decode(AspireData.self, from: stored) {
            data = decoded
        } else {
            data = .empty
        }
    }


    var hasMeaningfulUserData: Bool {
        !data.customers.isEmpty || !data.invoices.isEmpty || !data.expenses.isEmpty || !data.visits.isEmpty || !(data.quotations ?? []).isEmpty
    }

    func setAutomaticCloudBackupEnabled(_ enabled: Bool) {
        automaticCloudBackupEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: BackupPreferenceKeys.enabled)
        cloudBackupStatus = enabled ? "Automatic backup enabled" : "Automatic backup disabled"
        if enabled { performAutomaticCloudBackup(reason: "Enabled") }
    }

    func performAutomaticCloudBackup(reason: String = "Saved change") {
        guard automaticCloudBackupEnabled, hasMeaningfulUserData else { return }
        do {
            let encoded = try encoder.encode(data)
            scheduleCloudBackup(data: encoded, reason: reason)
        } catch {
            cloudBackupStatus = "Backup preparation failed: \(error.localizedDescription)"
        }
    }

    func checkICloudAccess() {
        iCloudAccessDiagnostic = "Checking iCloud on this device…"
        AspireCloudBackupService.shared.checkICloudAccess { [weak self] message in
            guard let self else { return }
            self.iCloudAccessDiagnostic = message
        }
    }

    func backupNowToICloud() {
        do {
            let encoded = try encoder.encode(data)
            pendingCloudBackup?.cancel()
            cloudBackupStatus = "Backing up…"
            AspireCloudBackupService.shared.createBackup(data: encoded) { [weak self] result in
                guard let self else { return }
                Task { @MainActor in self.finishCloudBackup(result) }
            }
        } catch {
            cloudBackupStatus = "Backup preparation failed: \(error.localizedDescription)"
        }
    }

    func restoreLatestAutomaticBackup() {
        cloudBackupStatus = "Looking for latest backup…"
        AspireCloudBackupService.shared.loadLatestBackup { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let payload):
                    do {
                        try self.importData(payload.0)
                        self.lastCloudBackupAt = payload.1.date
                        self.lastCloudBackupLocation = payload.1.location.rawValue
                        self.cloudBackupStatus = "Restored latest backup from \(payload.1.location.rawValue)."
                    } catch {
                        self.cloudBackupStatus = "Restore failed: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    self.cloudBackupStatus = error.localizedDescription
                }
            }
        }
    }

    private func scheduleCloudBackup(data: Data, reason: String) {
        pendingCloudBackup?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            AspireCloudBackupService.shared.createBackup(data: data) { [weak self] result in
                guard let self else { return }
                Task { @MainActor in self.finishCloudBackup(result) }
            }
        }
        pendingCloudBackup = item
        cloudBackupStatus = "Automatic backup queued • \(reason)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    private func finishCloudBackup(_ result: Result<AspireBackupResult, Error>) {
        switch result {
        case .success(let backup):
            lastCloudBackupAt = backup.date
            lastCloudBackupLocation = backup.location.rawValue
            UserDefaults.standard.set(backup.date, forKey: BackupPreferenceKeys.lastDate)
            UserDefaults.standard.set(backup.location.rawValue, forKey: BackupPreferenceKeys.lastLocation)
            if backup.location == .iCloud {
                cloudBackupStatus = "Saved to iCloud Drive container (sync may still be pending)."
            } else {
                cloudBackupStatus = "Local safety backup created. " + (backup.cloudIssue ?? "iCloud storage unavailable.")
            }
        case .failure(let error):
            cloudBackupStatus = "Backup failed: \(error.localizedDescription)"
        }
    }

    var company: CompanyProfile { data.company }
    var customers: [Customer] { data.customers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    var activeCustomers: [Customer] { customers.filter { $0.isActive && !$0.resolvedArchived } }
    var monthlyMaintenanceCustomers: [Customer] { activeCustomers.filter { $0.resolvedType == .monthlyMaintenance } }
    var invoices: [Invoice] { data.invoices.sorted { $0.issueDate > $1.issueDate } }
    var expenses: [Expense] { data.expenses.sorted { $0.date > $1.date } }
    var visits: [MaintenanceVisit] { data.visits.sorted { $0.date > $1.date } }
    var emailConfiguration: EmailConfiguration { data.emailConfiguration }
    var employees: [Employee] { (data.employees ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    var activeEmployees: [Employee] { employees.filter(\.isActive) }
    var bankAccounts: [BankAccount] {
        let stored = data.bankAccounts ?? []
        if !stored.isEmpty { return stored }
        let company = data.company
        guard !company.bankName.isEmpty || !company.iban.isEmpty || !company.accountNumber.isEmpty else { return [] }
        return [BankAccount(
            label: "Default Account",
            bankName: company.bankName,
            accountHolderName: company.accountHolderName,
            accountNumber: company.accountNumber,
            iban: company.iban,
            swiftCode: company.swiftCode,
            currencyCode: company.currencyCode,
            isDefault: true
        )]
    }
    var defaultBankAccount: BankAccount? { bankAccounts.first(where: \.isDefault) ?? bankAccounts.first }
    var advancePayments: [AdvancePayment] { (data.advancePayments ?? []).sorted { $0.date > $1.date } }
    var expenseRefunds: [ExpenseRefund] { (data.expenseRefunds ?? []).sorted { $0.date > $1.date } }
    var invoicePDFSettings: InvoicePDFSettings { data.invoicePDFSettings ?? .aspireDefault }
    var quotationPDFSettings: InvoicePDFSettings { data.quotationPDFSettings ?? .aspireQuotationDefault }
    var receiptPDFSettings: InvoicePDFSettings { data.receiptPDFSettings ?? .aspireReceiptDefault }
    var appLogoData: Data? { data.appLogoData }
    var catalogItems: [CatalogItem] { (data.catalogItems ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    var activeCatalogItems: [CatalogItem] { catalogItems.filter(\.isActive) }
    var quotations: [Quotation] { (data.quotations ?? []).sorted { $0.issueDate > $1.issueDate } }
    var visitSchedules: [ScheduledMaintenanceVisit] { (data.visitSchedules ?? []).sorted { $0.scheduledAt < $1.scheduledAt } }

    func customer(id: UUID) -> Customer? {
        data.customers.first { $0.id == id }
    }

    func visits(for customerID: UUID, in month: Date? = nil) -> [MaintenanceVisit] {
        data.visits.filter { visit in
            guard visit.customerID == customerID else { return false }
            guard let month else { return true }
            return Calendar.current.isDate(visit.date, equalTo: month, toGranularity: .month)
        }.sorted { $0.date > $1.date }
    }

    func invoices(for customerID: UUID) -> [Invoice] {
        invoices.filter { $0.customerID == customerID }
    }

    func invoice(id: UUID) -> Invoice? {
        data.invoices.first { $0.id == id }
    }

    func expense(id: UUID) -> Expense? {
        data.expenses.first { $0.id == id }
    }

    func employee(id: UUID?) -> Employee? {
        guard let id else { return nil }
        return (data.employees ?? []).first { $0.id == id }
    }

    func advancePayment(id: UUID) -> AdvancePayment? {
        (data.advancePayments ?? []).first { $0.id == id }
    }

    func catalogItem(id: UUID) -> CatalogItem? {
        (data.catalogItems ?? []).first { $0.id == id }
    }

    func quotation(id: UUID) -> Quotation? {
        (data.quotations ?? []).first { $0.id == id }
    }

    func refunds(for expenseID: UUID) -> [ExpenseRefund] {
        expenseRefunds.filter { $0.expenseID == expenseID }
    }

    func netAmount(for expense: Expense) -> Double {
        let refunded = refunds(for: expense.id).reduce(0) { $0 + $1.amount }
        return max(0, expense.amount - refunded)
    }

    func outstanding(for customerID: UUID) -> Double {
        invoices(for: customerID).filter { $0.status != .void }.reduce(0) { $0 + $1.outstanding }
    }

    func visits(in month: Date) -> [MaintenanceVisit] {
        visits.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    func monthlyMaintenanceVisits(in month: Date) -> [MaintenanceVisit] {
        visits(in: month).filter { visit in
            customer(id: visit.customerID)?.resolvedType == .monthlyMaintenance
        }
    }

    /// Maps recorded visits to the customer's planned monthly slots. Explicit slot numbers
    /// are preserved; older visits without a slot are assigned chronologically to the first
    /// available slots so existing data remains useful after upgrading.
    func visitAssignments(for customerID: UUID, in month: Date) -> [Int: MaintenanceVisit] {
        let monthVisits = visits(for: customerID, in: month).sorted { $0.date < $1.date }
        guard let customer = customer(id: customerID), customer.resolvedType.tracksMonthlyVisits else { return [:] }
        let planned = max(1, customer.plannedVisitsPerMonth)
        var assignments: [Int: MaintenanceVisit] = [:]
        var unassigned: [MaintenanceVisit] = []

        for visit in monthVisits {
            if let number = visit.visitNumber, number >= 1, number <= planned, assignments[number] == nil {
                assignments[number] = visit
            } else {
                unassigned.append(visit)
            }
        }

        for visit in unassigned {
            guard let slot = (1...planned).first(where: { assignments[$0] == nil }) else { break }
            assignments[slot] = visit
        }
        return assignments
    }

    func completedVisitCount(for customerID: UUID, in month: Date) -> Int {
        visitAssignments(for: customerID, in: month).count
    }

    func scheduledVisits(for customerID: UUID, in month: Date) -> [ScheduledMaintenanceVisit] {
        visitSchedules.filter { schedule in
            schedule.customerID == customerID && Calendar.current.isDate(schedule.scheduledAt, equalTo: month, toGranularity: .month)
        }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func scheduledVisits(on day: Date) -> [ScheduledMaintenanceVisit] {
        visitSchedules.filter { schedule in
            Calendar.current.isDate(schedule.scheduledAt, inSameDayAs: day) &&
            customer(id: schedule.customerID)?.resolvedType == .monthlyMaintenance
        }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func scheduledVisit(for customerID: UUID, slot: Int, in month: Date) -> ScheduledMaintenanceVisit? {
        scheduledVisits(for: customerID, in: month).first { $0.slot == slot }
    }

    func nextScheduledVisit(for customerID: UUID, in month: Date) -> ScheduledMaintenanceVisit? {
        let completed = visitAssignments(for: customerID, in: month)
        return scheduledVisits(for: customerID, in: month)
            .filter { completed[$0.slot] == nil }
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .first
    }

    func overdueScheduledVisits(asOf date: Date = Date(), in month: Date? = nil) -> [ScheduledMaintenanceVisit] {
        visitSchedules.filter { schedule in
            if let month, !Calendar.current.isDate(schedule.scheduledAt, equalTo: month, toGranularity: .month) { return false }
            guard schedule.scheduledAt < date else { return false }
            guard let customer = customer(id: schedule.customerID), customer.resolvedType == .monthlyMaintenance else { return false }
            return visitAssignments(for: schedule.customerID, in: schedule.scheduledAt)[schedule.slot] == nil
        }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    @discardableResult
    func setVisitSchedule(customerID: UUID, slot: Int, scheduledAt: Date) -> Bool {
        guard let customer = customer(id: customerID), customer.resolvedType == .monthlyMaintenance else {
            lastErrorMessage = "Visit scheduling is available only for monthly-maintenance customers."
            return false
        }
        guard slot >= 1, slot <= max(1, customer.plannedVisitsPerMonth) else {
            lastErrorMessage = "Choose a valid planned visit number."
            return false
        }
        var schedules = data.visitSchedules ?? []
        if let index = schedules.firstIndex(where: {
            $0.customerID == customerID && $0.slot == slot && Calendar.current.isDate($0.scheduledAt, equalTo: scheduledAt, toGranularity: .month)
        }) {
            schedules[index].scheduledAt = scheduledAt
        } else {
            // One planned time per customer/slot/month. Remove any older time for the same slot in this month.
            schedules.removeAll {
                $0.customerID == customerID && $0.slot == slot && Calendar.current.isDate($0.scheduledAt, equalTo: scheduledAt, toGranularity: .month)
            }
            schedules.append(ScheduledMaintenanceVisit(customerID: customerID, slot: slot, scheduledAt: scheduledAt))
        }
        data.visitSchedules = schedules
        return persist()
    }

    func removeVisitSchedule(customerID: UUID, slot: Int, in month: Date) {
        var schedules = data.visitSchedules ?? []
        schedules.removeAll {
            $0.customerID == customerID && $0.slot == slot && Calendar.current.isDate($0.scheduledAt, equalTo: month, toGranularity: .month)
        }
        data.visitSchedules = schedules
        persist()
    }

    func remainingVisitCount(for customerID: UUID, in month: Date) -> Int {
        guard let customer = customer(id: customerID), customer.resolvedType.tracksMonthlyVisits else { return 0 }
        return max(0, customer.plannedVisitsPerMonth - completedVisitCount(for: customerID, in: month))
    }

    @discardableResult
    func recordVisitSlot(customerID: UUID, slot: Int, date: Date, employeeID: UUID?, notes: String = "") -> Bool {
        guard let customer = customer(id: customerID) else {
            lastErrorMessage = "Customer not found."
            return false
        }
        guard customer.resolvedType.tracksMonthlyVisits else {
            lastErrorMessage = "Visits are only scheduled for monthly-maintenance customers."
            return false
        }
        guard slot >= 1, slot <= max(1, customer.plannedVisitsPerMonth) else {
            lastErrorMessage = "Invalid visit number."
            return false
        }
        let existing = visitAssignments(for: customerID, in: date)
        guard existing[slot] == nil else {
            lastErrorMessage = "This visit is already marked as completed."
            return false
        }
        let employeeName = employee(id: employeeID)?.name ?? ""
        data.visits.append(MaintenanceVisit(
            customerID: customerID,
            date: date,
            staffName: employeeName,
            workDone: "Garden maintenance visit \(slot) of \(customer.plannedVisitsPerMonth)",
            notes: notes,
            employeeID: employeeID,
            visitNumber: slot
        ))
        return persist()
    }

    func updateCompany(_ company: CompanyProfile) {
        data.company = company
        persist()
    }

    func updateEmailConfiguration(_ configuration: EmailConfiguration) {
        data.emailConfiguration = configuration
        persist()
    }

    func updateAppLogoData(_ logoData: Data?) {
        data.appLogoData = logoData
        persist()
    }

    func updateInvoicePDFSettings(_ settings: InvoicePDFSettings) {
        data.invoicePDFSettings = settings
        persist()
    }

    func updateQuotationPDFSettings(_ settings: InvoicePDFSettings) {
        data.quotationPDFSettings = settings
        persist()
    }

    func updateReceiptPDFSettings(_ settings: InvoicePDFSettings) {
        data.receiptPDFSettings = settings
        persist()
    }

    func addCatalogItem(_ item: CatalogItem) {
        var items = data.catalogItems ?? []
        items.append(item)
        data.catalogItems = items
        persist()
    }

    func updateCatalogItem(_ item: CatalogItem) {
        var items = data.catalogItems ?? []
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        data.catalogItems = items
        persist()
    }

    func deleteCatalogItem(_ id: UUID) {
        var items = data.catalogItems ?? []
        items.removeAll { $0.id == id }
        data.catalogItems = items
        persist()
    }

    func addQuotation(_ quotation: Quotation) {
        var quotes = data.quotations ?? []
        quotes.append(quotation)
        data.quotations = quotes
        persist()
    }

    func updateQuotation(_ quotation: Quotation) {
        var quotes = data.quotations ?? []
        guard let index = quotes.firstIndex(where: { $0.id == quotation.id }) else { return }
        quotes[index] = quotation
        data.quotations = quotes
        persist()
    }

    func deleteQuotation(_ id: UUID) {
        var quotes = data.quotations ?? []
        quotes.removeAll { $0.id == id }
        data.quotations = quotes
        persist()
    }

    func addEmployee(_ employee: Employee) {
        var employees = data.employees ?? []
        employees.append(employee)
        data.employees = employees
        persist()
    }

    func updateEmployee(_ employee: Employee) {
        var employees = data.employees ?? []
        guard let index = employees.firstIndex(where: { $0.id == employee.id }) else { return }
        employees[index] = employee
        data.employees = employees
        persist()
    }

    func deleteEmployee(_ id: UUID) {
        var employees = data.employees ?? []
        employees.removeAll { $0.id == id }
        data.employees = employees
        persist()
    }

    func replaceBankAccounts(_ accounts: [BankAccount]) {
        var normalized = accounts
        if !normalized.isEmpty && !normalized.contains(where: \.isDefault) {
            normalized[0].isDefault = true
        }
        data.bankAccounts = normalized
        persist()
    }

    func addBankAccount(_ account: BankAccount) {
        var accounts = data.bankAccounts ?? []
        var newAccount = account
        if accounts.isEmpty { newAccount.isDefault = true }
        if newAccount.isDefault {
            accounts = accounts.map {
                var copy = $0
                copy.isDefault = false
                return copy
            }
        }
        accounts.append(newAccount)
        data.bankAccounts = accounts
        persist()
    }

    func updateBankAccount(_ account: BankAccount) {
        var accounts = data.bankAccounts ?? []
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        if account.isDefault {
            for i in accounts.indices { accounts[i].isDefault = false }
        }
        accounts[index] = account
        data.bankAccounts = accounts
        persist()
    }

    func deleteBankAccount(_ id: UUID) {
        var accounts = data.bankAccounts ?? []
        let wasDefault = accounts.first(where: { $0.id == id })?.isDefault == true
        accounts.removeAll { $0.id == id }
        if wasDefault, !accounts.isEmpty { accounts[0].isDefault = true }
        data.bankAccounts = accounts
        persist()
    }

    func addCustomer(_ customer: Customer) {
        data.customers.append(customer)
        persist()
    }

    func updateCustomer(_ customer: Customer) {
        guard let index = data.customers.firstIndex(where: { $0.id == customer.id }) else { return }
        data.customers[index] = customer
        persist()
    }

    func setCustomerActive(_ customerID: UUID, active: Bool) {
        guard let index = data.customers.firstIndex(where: { $0.id == customerID }) else { return }
        data.customers[index].isActive = active
        persist()
    }

    func setCustomerArchived(_ customerID: UUID, archived: Bool) {
        guard let index = data.customers.firstIndex(where: { $0.id == customerID }) else { return }
        data.customers[index].isArchived = archived
        if archived { data.customers[index].isActive = false }
        persist()
    }

    func deleteCustomers(at offsets: IndexSet, from displayedCustomers: [Customer]) {
        let ids = offsets.map { displayedCustomers[$0].id }
        data.customers.removeAll { ids.contains($0.id) }
        data.visits.removeAll { ids.contains($0.customerID) }
        data.invoices.removeAll { ids.contains($0.customerID) }
        var schedules = data.visitSchedules ?? []
        schedules.removeAll { ids.contains($0.customerID) }
        data.visitSchedules = schedules
        persist()
    }

    func addVisit(_ visit: MaintenanceVisit) {
        data.visits.append(visit)
        persist()
    }

    @discardableResult
    func createMonthlyInvoice(for customer: Customer, serviceMonth: Date, customAmount: Double? = nil, employeeID: UUID? = nil) -> Invoice {
        let calendar = Calendar.current
        let normalizedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: serviceMonth)) ?? serviceMonth
        let issueDate = Date()
        let dueDate = calendar.date(byAdding: .day, value: max(0, company.paymentTermsDays), to: issueDate) ?? issueDate
        let monthName = DateFormatter.monthAndYear.string(from: normalizedMonth)
        let amount = customAmount ?? customer.monthlyRate
        let invoice = Invoice(
            number: nextInvoiceNumber(for: issueDate),
            customerID: customer.id,
            issueDate: issueDate,
            dueDate: dueDate,
            serviceMonth: normalizedMonth,
            lineItems: [InvoiceLineItem(description: "Garden Maintenance Charges (Monthly) – \(monthName)", quantity: 1, unitPrice: amount)],
            status: .draft,
            amountPaid: 0,
            notes: company.invoiceTerms,
            sentAt: nil,
            paidAt: nil,
            employeeID: employeeID,
            jobType: .monthlyMaintenance
        )
        data.invoices.append(invoice)
        persist()
        return invoice
    }

    @discardableResult
    func createManualInvoice(
        for customer: Customer,
        jobType: JobType,
        serviceDate: Date,
        lineItems: [InvoiceLineItem],
        employeeID: UUID? = nil,
        notes: String? = nil
    ) -> Invoice {
        let issueDate = Date()
        let dueDate = Calendar.current.date(byAdding: .day, value: max(0, company.paymentTermsDays), to: issueDate) ?? issueDate
        let normalizedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: serviceDate)) ?? serviceDate
        let validItems = lineItems.filter { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.quantity > 0 && $0.unitPrice >= 0 }
        let invoice = Invoice(
            number: nextInvoiceNumber(for: issueDate),
            customerID: customer.id,
            issueDate: issueDate,
            dueDate: dueDate,
            serviceMonth: normalizedMonth,
            lineItems: validItems,
            status: .draft,
            amountPaid: 0,
            notes: notes ?? company.invoiceTerms,
            sentAt: nil,
            paidAt: nil,
            employeeID: employeeID,
            jobType: jobType
        )
        data.invoices.append(invoice)
        persist()
        return invoice
    }

    func makeQuotation(
        for customer: Customer,
        jobType: JobType,
        issueDate: Date,
        validUntil: Date,
        lineItems: [InvoiceLineItem],
        discountMode: QuoteDiscountMode,
        discountValue: Double,
        notes: String,
        employeeID: UUID? = nil
    ) -> Quotation {
        let quote = Quotation(
            number: nextQuotationNumber(for: issueDate),
            customerID: customer.id,
            jobType: jobType,
            issueDate: issueDate,
            validUntil: validUntil,
            lineItems: lineItems,
            discountMode: discountMode,
            discountValue: discountValue,
            notes: notes,
            status: .draft,
            employeeID: employeeID
        )
        addQuotation(quote)
        return quote
    }

    @discardableResult
    func createInvoice(from quotation: Quotation, for customer: Customer, issueDate: Date = Date()) -> Invoice {
        let dueDate = Calendar.current.date(byAdding: .day, value: max(0, company.paymentTermsDays), to: issueDate) ?? issueDate
        let normalizedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: issueDate)) ?? issueDate
        var invoiceItems = quotation.lineItems
        if quotation.discountAmount > 0 {
            let label: String
            if quotation.discountMode == .percentage {
                label = String(format: "Quotation Discount (%.2f%%)", quotation.discountValue)
            } else {
                label = "Quotation Discount"
            }
            invoiceItems.append(InvoiceLineItem(description: label, quantity: 1, unitPrice: -quotation.discountAmount))
        }
        let invoice = Invoice(
            number: nextInvoiceNumber(for: issueDate),
            customerID: customer.id,
            issueDate: issueDate,
            dueDate: dueDate,
            serviceMonth: normalizedMonth,
            lineItems: invoiceItems,
            status: .draft,
            amountPaid: 0,
            notes: quotation.notes.isEmpty ? company.invoiceTerms : quotation.notes,
            sentAt: nil,
            paidAt: nil,
            employeeID: quotation.employeeID,
            jobType: quotation.jobType
        )
        data.invoices.append(invoice)
        var quotes = data.quotations ?? []
        if let index = quotes.firstIndex(where: { $0.id == quotation.id }) {
            quotes[index].status = .accepted
            quotes[index].acceptedAt = quotes[index].acceptedAt ?? Date()
            quotes[index].convertedInvoiceID = invoice.id
            data.quotations = quotes
        }
        persist()
        return invoice
    }

    func addInvoice(_ invoice: Invoice) {
        data.invoices.append(invoice)
        persist()
    }

    func updateInvoice(_ invoice: Invoice) {
        guard let index = data.invoices.firstIndex(where: { $0.id == invoice.id }) else { return }
        data.invoices[index] = invoice
        persist()
    }

    /// Updates an existing invoice without altering its identity, issue date, customer,
    /// payment history or original transmission timestamp. All edit paths call persist(),
    /// so the existing backup and device-sync observers continue to work.
    @discardableResult
    func reviseInvoice(
        original: Invoice,
        lineItems: [InvoiceLineItem],
        dueDate: Date,
        notes: String,
        employeeID: UUID?
    ) throws -> Bool {
        guard let index = data.invoices.firstIndex(where: { $0.id == original.id }) else {
            throw AspireInvoiceEditError.changedOnAnotherDevice
        }
        let current = data.invoices[index]
        guard current.status != .paid && current.status != .void else {
            throw AspireInvoiceEditError.unavailable
        }
        guard current.lineItems == original.lineItems,
              current.dueDate == original.dueDate,
              current.notes == original.notes,
              current.employeeID == original.employeeID else {
            throw AspireInvoiceEditError.changedOnAnotherDevice
        }
        guard !lineItems.isEmpty,
              lineItems.allSatisfy({
                  !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.quantity.isFinite && $0.quantity > 0 &&
                  $0.unitPrice.isFinite && $0.unitPrice >= 0
              }) else {
            throw AspireInvoiceEditError.invalidLines
        }
        let revisedTotal = lineItems.reduce(0.0) { $0 + $1.amount }
        guard revisedTotal.isFinite && revisedTotal > 0 else {
            throw AspireInvoiceEditError.invalidLines
        }
        guard revisedTotal + 0.005 >= current.amountPaid else {
            throw AspireInvoiceEditError.belowAmountReceived
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current.lineItems != lineItems || current.dueDate != dueDate ||
              current.notes != trimmedNotes || current.employeeID != employeeID else {
            return false
        }

        var revised = current
        let history = InvoiceRevision(
            revisedAt: Date(), previousLineItems: current.lineItems,
            previousDueDate: current.dueDate, previousNotes: current.notes,
            previousEmployeeID: current.employeeID,
            previousTotal: current.total, updatedTotal: revisedTotal
        )
        revised.revisions = (current.revisions ?? []) + [history]
        revised.lineItems = lineItems
        revised.dueDate = dueDate
        revised.notes = trimmedNotes
        revised.employeeID = employeeID
        // Existing receipts stay intact. A partial payment becomes fully paid only
        // when its preserved amount exactly covers the new revised invoice total.
        if revised.amountPaid > 0 {
            revised.status = revised.amountPaid >= revisedTotal - 0.005 ? .paid : .partial
        }
        data.invoices[index] = revised
        guard persist() else {
            data.invoices[index] = current
            throw CocoaError(.fileWriteUnknown)
        }
        return true
    }

    func markInvoiceSent(_ id: UUID) {
        guard let index = data.invoices.firstIndex(where: { $0.id == id }) else { return }
        data.invoices[index].status = data.invoices[index].amountPaid > 0 ? .partial : .sent
        data.invoices[index].sentAt = Date()
        persist()
    }

    func recordPayment(invoiceID: UUID, amount: Double, paymentDate: Date) {
        guard let index = data.invoices.firstIndex(where: { $0.id == invoiceID }) else { return }
        let newPaid = min(data.invoices[index].total, max(0, data.invoices[index].amountPaid + amount))
        data.invoices[index].amountPaid = newPaid
        if newPaid >= data.invoices[index].total - 0.005 {
            data.invoices[index].status = .paid
            data.invoices[index].paidAt = paymentDate
        } else if newPaid > 0 {
            data.invoices[index].status = .partial
            data.invoices[index].paidAt = paymentDate
        }
        persist()
    }

    /// One-touch full payment toggle. A second touch reverses an accidental receipt.
    func toggleInvoicePayment(_ invoiceID: UUID, paymentDate: Date = Date()) {
        guard let index = data.invoices.firstIndex(where: { $0.id == invoiceID }) else { return }
        guard data.invoices[index].status != .void else { return }

        if data.invoices[index].status == .paid {
            data.invoices[index].amountPaid = 0
            data.invoices[index].paidAt = nil
            data.invoices[index].status = data.invoices[index].sentAt == nil ? .draft : .sent
        } else {
            data.invoices[index].amountPaid = data.invoices[index].total
            data.invoices[index].paidAt = paymentDate
            data.invoices[index].status = .paid
        }
        persist()
    }

    func deleteInvoice(_ id: UUID) {
        data.invoices.removeAll { $0.id == id }
        var quotes = data.quotations ?? []
        for index in quotes.indices where quotes[index].convertedInvoiceID == id {
            quotes[index].convertedInvoiceID = nil
        }
        data.quotations = quotes
        persist()
    }

    @discardableResult
    func addAdvancePayment(_ payment: AdvancePayment) -> Bool {
        guard payment.amount.isFinite, payment.amount > 0 else {
            lastErrorMessage = "Enter a valid advance amount greater than zero."
            return false
        }
        var payments = data.advancePayments ?? []
        payments.append(payment)
        data.advancePayments = payments
        return persist()
    }

    func deleteAdvancePayment(_ id: UUID) {
        var payments = data.advancePayments ?? []
        payments.removeAll { $0.id == id }
        data.advancePayments = payments
        persist()
    }

    func advances(for customerID: UUID) -> [AdvancePayment] {
        advancePayments.filter { $0.customerID == customerID }
    }

    func advanceTotal(in month: Date? = nil) -> Double {
        advancePayments.filter { payment in
            guard let month else { return true }
            return Calendar.current.isDate(payment.date, equalTo: month, toGranularity: .month)
        }.reduce(0) { $0 + $1.amount }
    }

    @discardableResult
    func addExpense(_ expense: Expense) -> Bool {
        guard expense.amount.isFinite, expense.amount > 0 else {
            lastErrorMessage = "Enter a valid expense amount greater than zero."
            return false
        }
        var updated = data
        updated.expenses.append(expense)
        data = updated
        return persist()
    }

    func updateExpense(_ expense: Expense) {
        guard let index = data.expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        data.expenses[index] = expense
        persist()
    }

    func deleteExpense(_ id: UUID) {
        data.expenses.removeAll { $0.id == id }
        var refunds = data.expenseRefunds ?? []
        refunds.removeAll { $0.expenseID == id }
        data.expenseRefunds = refunds
        persist()
    }

    @discardableResult
    func addExpenseRefund(_ refund: ExpenseRefund) -> Bool {
        guard let expense = expense(id: refund.expenseID) else {
            lastErrorMessage = "The original expense no longer exists."
            return false
        }
        let alreadyRefunded = refunds(for: expense.id).reduce(0) { $0 + $1.amount }
        let remaining = max(0, expense.amount - alreadyRefunded)
        guard refund.amount.isFinite, refund.amount > 0, refund.amount <= remaining + 0.005 else {
            lastErrorMessage = "Refund must be greater than zero and cannot exceed the remaining expense amount."
            return false
        }
        var refunds = data.expenseRefunds ?? []
        refunds.append(refund)
        data.expenseRefunds = refunds
        return persist()
    }

    func deleteExpenseRefund(_ id: UUID) {
        var refunds = data.expenseRefunds ?? []
        refunds.removeAll { $0.id == id }
        data.expenseRefunds = refunds
        persist()
    }

    func generateMonthlyInvoices(for month: Date) -> [Invoice] {
        var generated: [Invoice] = []
        for customer in monthlyMaintenanceCustomers {
            let exists = data.invoices.contains {
                $0.customerID == customer.id &&
                Calendar.current.isDate($0.serviceMonth, equalTo: month, toGranularity: .month) &&
                $0.status != .void
            }
            if !exists {
                generated.append(createMonthlyInvoice(for: customer, serviceMonth: month))
            }
        }
        return generated
    }

    /// Revenue belongs to the maintenance service month, regardless of when the invoice
    /// was created or when its payment was received.
    func invoicedIncome(in month: Date) -> Double {
        invoicesForServiceMonth(month).reduce(0) { $0 + $1.total }
    }

    func invoicesForServiceMonth(_ month: Date) -> [Invoice] {
        invoices.filter {
            $0.status != .void && Calendar.current.isDate($0.serviceMonth, equalTo: month, toGranularity: .month)
        }
    }

    func collectedIncome(in month: Date) -> Double {
        paymentsReceived(in: month).reduce(0) { $0 + $1.amountPaid }
    }

    func paymentsReceived(in month: Date) -> [Invoice] {
        invoices.filter {
            guard $0.status != .void, let paidAt = $0.paidAt else { return false }
            return Calendar.current.isDate(paidAt, equalTo: month, toGranularity: .month)
        }
    }

    func expensesForMonth(_ month: Date) -> [Expense] {
        expenses.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    func refundsForMonth(_ month: Date) -> [ExpenseRefund] {
        expenseRefunds.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    func grossExpensesTotal(in month: Date) -> Double {
        expensesForMonth(month).reduce(0) { $0 + $1.amount }
    }

    func refundsTotal(in month: Date) -> Double {
        refundsForMonth(month).reduce(0) { $0 + $1.amount }
    }

    func expensesTotal(in month: Date) -> Double {
        grossExpensesTotal(in: month) - refundsTotal(in: month)
    }

    func outstandingTotal() -> Double {
        data.invoices.filter { $0.status != .void }.reduce(0) { $0 + $1.outstanding }
    }

    func overdueInvoices(asOf date: Date = Date()) -> [Invoice] {
        invoices.filter { $0.isOverdue(asOf: date) }
    }

    func longOverdueInvoices(asOf date: Date = Date()) -> [Invoice] {
        overdueInvoices(asOf: date).filter { $0.overdueDays(asOf: date) >= company.longOverdueDays }
    }

    func agingSummary(asOf date: Date = Date()) -> AgingSummary {
        var summary = AgingSummary()
        for invoice in data.invoices where invoice.status != .void && invoice.outstanding > 0 {
            let days = invoice.overdueDays(asOf: date)
            if !invoice.isOverdue(asOf: date) {
                summary.current += invoice.outstanding
            } else if days <= 30 {
                summary.days1To30 += invoice.outstanding
            } else if days <= 60 {
                summary.days31To60 += invoice.outstanding
            } else if days <= 90 {
                summary.days61To90 += invoice.outstanding
            } else {
                summary.over90 += invoice.outstanding
            }
        }
        return summary
    }

    func exportData() throws -> Data {
        try encoder.encode(data)
    }

    func importData(_ importedData: Data) throws {
        // Decode fully before touching the in-memory database so a bad/partial backup can
        // never wipe the current session. Then verify that the restored payload can be
        // re-encoded and saved before publishing it to the UI.
        let restored = try decoder.decode(AspireData.self, from: importedData)
        let persisted = try encoder.encode(restored)
        try persisted.write(to: dataURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        data = restored
        lastErrorMessage = nil
    }

    func addDemoData() {
        guard data.customers.isEmpty && data.invoices.isEmpty && data.expenses.isEmpty else { return }
        let customer = Customer(
            name: "Sample Garden Customer",
            address: "Abu Dhabi, UAE",
            email: "customer@example.com",
            phone: "+971 50 000 0000",
            monthlyRate: 600,
            plannedVisitsPerMonth: 3,
            notes: "Demo record for first testing. Delete it when finished.",
            isActive: true,
            customerType: .monthlyMaintenance
        )
        data.customers.append(customer)
        let invoice = createMonthlyInvoice(for: customer, serviceMonth: Date())
        data.invoices = data.invoices.map { current in
            var updated = current
            if current.id == invoice.id {
                updated.issueDate = Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? Date()
                updated.dueDate = Calendar.current.date(byAdding: .day, value: -38, to: Date()) ?? Date()
                updated.status = .sent
            }
            return updated
        }
        data.expenses.append(Expense(date: Date(), category: .fuel, vendor: "Sample Fuel", amount: 120, paymentAccount: "Cash", notes: "Demo expense"))
        persist()
    }

    func requestNotificationsAndRefresh() async {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted { await refreshOverdueNotifications() }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshOverdueNotifications() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["aspire.long-overdue"])
        let overdue = longOverdueInvoices()
        guard !overdue.isEmpty else { return }

        let total = overdue.reduce(0) { $0 + $1.outstanding }
        let content = UNMutableNotificationContent()
        content.title = "Long-overdue invoices"
        content.body = "\(overdue.count) invoice(s) are overdue by at least \(company.longOverdueDays) days. Outstanding: \(currency(total))."
        content.sound = .default
        content.badge = NSNumber(value: overdue.count)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "aspire.long-overdue", content: content, trigger: trigger)
        try? await center.add(request)
    }

    func currency(_ amount: Double) -> String {
        CurrencyFormatter.string(amount, code: company.currencyCode)
    }

    private func nextInvoiceNumber(for date: Date) -> String {
        let month = DateFormatter.invoiceMonth.string(from: date)
        let prefix = company.invoicePrefix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().isEmpty
            ? "ASP"
            : company.invoicePrefix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let sameMonthCount = data.invoices.filter {
            DateFormatter.invoiceMonth.string(from: $0.issueDate) == month
        }.count + 1
        return String(format: "%@-%@-%03d", prefix, month, sameMonthCount)
    }

    private func nextQuotationNumber(for date: Date) -> String {
        let month = DateFormatter.invoiceMonth.string(from: date)
        let prefix = company.invoicePrefix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().isEmpty
            ? "ASP"
            : company.invoicePrefix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let sameMonthCount = (data.quotations ?? []).filter {
            DateFormatter.invoiceMonth.string(from: $0.issueDate) == month
        }.count + 1
        return String(format: "%@-QT-%@-%03d", prefix, month, sameMonthCount)
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: dataURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            objectWillChange.send()
            if automaticCloudBackupEnabled && hasMeaningfulUserData {
                scheduleCloudBackup(data: encoded, reason: "Saved change")
            }
            return true
        } catch {
            lastErrorMessage = "Unable to save Aspire data: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - Formatting

enum CurrencyFormatter {
    static func string(_ amount: Double, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code.isEmpty ? "AED" : code
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%@ %.2f", code, amount)
    }
}

extension DateFormatter {
    static let monthAndYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let invoiceMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMM"
        return formatter
    }()

    static let backupDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

extension Calendar {
    func addingMonths(_ value: Int, to date: Date) -> Date {
        self.date(byAdding: .month, value: value, to: date) ?? date
    }
}
