import SwiftUI
import LocalAuthentication
import UniformTypeIdentifiers

// AccountantsNext Mobile 0.3.0 — HR, Payments, Manager Reporting, Company and Zee.
// No network access, no Xero posting, and no writes to the imported PC database.
enum MobilePalette {
    static let accent = Color(red: 0.20, green: 0.39, blue: 0.94)
    static let ink = Color.primary
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let panel = Color(uiColor: .secondarySystemGroupedBackground)
}

enum MobileSection: String, CaseIterable {
    case hr = "HR", payments = "Payments", reporting = "Reports", company = "Company", zee = "Agent Zee"
    var symbol: String {
        switch self {
        case .hr: return "person.2.crop.square.stack.fill"
        case .payments: return "arrow.left.arrow.right.circle.fill"
        case .reporting: return "chart.bar.doc.horizontal.fill"
        case .company: return "building.2.crop.circle.fill"
        case .zee: return "sparkles"
        }
    }
}

struct MobileV2Root: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var drafts = ReceiptDraftStore()
    @State private var showingImporter = false
    @State private var locked = true
    @State private var authenticationMessage = ""

    var body: some View {
        ZStack {
            TabView {
                ModernHRView()
                    .tabItem { Label("HR", systemImage: MobileSection.hr.symbol) }
                ModernPaymentsView()
                    .tabItem { Label("Payments", systemImage: MobileSection.payments.symbol) }
                ManagerReportingMobileView()
                    .tabItem { Label("Reports", systemImage: MobileSection.reporting.symbol) }
                ModernCompanyView(importer: $showingImporter)
                    .tabItem { Label("Company", systemImage: MobileSection.company.symbol) }
                ModernZeeView()
                    .tabItem { Label("Agent Zee", systemImage: MobileSection.zee.symbol) }
            }
            .tint(MobilePalette.accent)
            .environmentObject(drafts)
            if locked {
                lockScreen
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.zip, .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { Task { await store.importBackup(from: url) } }
            case .failure(let error):
                store.lastError = error.localizedDescription
            }
        }
        .overlay(alignment: .top) {
            if store.isBusy {
                ProgressView(store.importStage.isEmpty ? "Importing snapshot…" : store.importStage)
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .alert("AccountantsNext", isPresented: Binding(
            get: { !store.lastError.isEmpty },
            set: { if !$0 { store.lastError = "" } }
        )) { Button("OK", role: .cancel) {} }
        message: { Text(store.lastError) }
        .onAppear(perform: authenticate)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active { authenticate() }
            else { locked = true }
        }
    }

    private var lockScreen: some View {
        ZStack {
            MobilePalette.canvas.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(MobilePalette.accent)
                    .frame(width: 110, height: 110)
                    .background(MobilePalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 30))
                Text("AccountantsNext")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("HR, payments, company records and Agent Zee")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Label("Local business data stays on this device", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                Spacer()
                if !authenticationMessage.isEmpty {
                    Text(authenticationMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button(action: authenticate) {
                    Label("Unlock securely", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                        .padding(12)
                }
                .buttonStyle(.borderedProminent)
                .tint(MobilePalette.accent)
            }
            .padding(30)
        }
    }

    private func authenticate() {
        guard locked else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationMessage = "Enable an iPhone passcode or Face ID to protect HR and financial records."
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your AccountantsNext business workspace") { result, error in
            DispatchQueue.main.async {
                if result {
                    withAnimation(.easeInOut(duration: 0.2)) { locked = false }
                    authenticationMessage = ""
                } else {
                    authenticationMessage = error?.localizedDescription ?? "Authentication required."
                }
            }
        }
    }
}

struct MobileModuleHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 32, weight: .bold, design: .rounded))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }
}

struct MobileCompanyPicker: View {
    @EnvironmentObject private var store: MobileStore
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2")
                .font(.title3.weight(.semibold))
                .foregroundStyle(MobilePalette.accent)
                .frame(width: 42, height: 42)
                .background(MobilePalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("WORKSPACE").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.secondary)
                if store.entities.isEmpty {
                    Text("No backup imported").font(.subheadline.weight(.semibold))
                } else {
                    Picker("Company", selection: $store.selectedEntityID) {
                        ForEach(store.entities) { entity in Text(entity.name).tag(entity.id) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(.primary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
        }
        .padding(14)
        .background(MobilePalette.panel, in: RoundedRectangle(cornerRadius: 19))
        .task(id: store.selectedEntityID) { await store.refreshEntityData() }
    }
}

struct MobileCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MobilePalette.panel, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct MobileEmpty: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 32)).foregroundStyle(MobilePalette.accent)
            Text(title).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .background(MobilePalette.panel, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct ModernHRView: View {
    @EnvironmentObject private var store: MobileStore
    @State private var section = 0
    @State private var query = ""
    private var filteredEmployees: [EmployeeRow] {
        store.employees.filter { query.isEmpty || "\($0.name) \($0.no) \($0.position) \($0.department)".localizedCaseInsensitiveContains(query) }
    }
    private var filteredLeaves: [LeaveRow] {
        store.leaves.filter { query.isEmpty || "\($0.employee) \($0.recordId) \($0.status)".localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MobileModuleHeader(title: "Human Resources", subtitle: "Employees, leave and HR records")
                    MobileCompanyPicker()
                    HStack(spacing: 10) {
                        stat(title: "Employees", value: "\(store.employees.count)", icon: "person.2.fill")
                        stat(title: "Active", value: "\(store.employees.filter(\.active).count)", icon: "checkmark.circle.fill")
                        stat(title: "Leave records", value: "\(store.leaves.count)", icon: "calendar")
                    }
                    Picker("HR area", selection: $section) {
                        Text("Employees").tag(0)
                        Text("Leave").tag(1)
                    }.pickerStyle(.segmented)
                    TextField("Search \(section == 0 ? "employees" : "leave settlements")", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    if section == 0 {
                        if filteredEmployees.isEmpty {
                            MobileEmpty(title: "No employees to display", detail: "Import your Windows Accountants backup to load real HR records.", symbol: "person.crop.rectangle.stack")
                        } else {
                            LazyVStack(spacing: 9) {
                                ForEach(filteredEmployees) { employee in
                                    NavigationLink { EmployeeDetailView(employee: employee) } label: {
                                        HStack(spacing: 12) {
                                            Text(String(employee.name.prefix(1)).uppercased())
                                                .font(.headline)
                                                .foregroundStyle(MobilePalette.accent)
                                                .frame(width: 42, height: 42)
                                                .background(MobilePalette.accent.opacity(0.10), in: Circle())
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(employee.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                                Text([employee.no, employee.position].filter { !$0.isEmpty }.joined(separator: " • "))
                                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                        }
                                        .padding(13)
                                        .background(MobilePalette.panel, in: RoundedRectangle(cornerRadius: 16))
                                    }
                                }
                            }
                        }
                    } else {
                        if filteredLeaves.isEmpty {
                            MobileEmpty(title: "No leave settlements", detail: "Leave settlement records from the imported snapshot appear here.", symbol: "calendar.badge.clock")
                        } else {
                            LazyVStack(spacing: 9) {
                                ForEach(filteredLeaves) { leave in
                                    NavigationLink { LeaveDetailView(leave: leave) } label: {
                                        MobileCard {
                                            HStack {
                                                Text(leave.employee).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                                Spacer()
                                                Text(leave.status.isEmpty ? "Review" : leave.status)
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Text("\(leave.start)  –  \(leave.end)")
                                                .font(.caption).foregroundStyle(.secondary)
                                            Text("Net: \(money(leave.net, store.selectedEntity?.currency ?? "QAR"))")
                                                .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(MobilePalette.canvas)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    private func stat(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(MobilePalette.accent)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MobilePalette.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct EmployeeDetailView: View {
    let employee: EmployeeRow
    var body: some View {
        List {
            Section("Employee") {
                LabeledContent("Name", value: employee.name)
                LabeledContent("Employee no.", value: employee.no)
                LabeledContent("Position", value: employee.position)
                LabeledContent("Department", value: employee.department)
                LabeledContent("Status", value: employee.active ? "Active" : "Inactive")
            }
            Section {
                Text("Read-only record from the imported Windows snapshot. Editing and live HR synchronization are not enabled.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Employee Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LeaveDetailView: View {
    @EnvironmentObject private var store: MobileStore
    let leave: LeaveRow
    var body: some View {
        List {
            Section("Leave settlement") {
                LabeledContent("Employee", value: leave.employee)
                LabeledContent("Reference", value: leave.recordId)
                LabeledContent("From", value: leave.start)
                LabeledContent("To", value: leave.end)
                LabeledContent("Days", value: String(format: "%.2f", leave.days))
                LabeledContent("Remaining", value: String(format: "%.2f", leave.remaining))
                LabeledContent("Net payable", value: money(leave.net, store.selectedEntity?.currency ?? "QAR"))
                LabeledContent("Status", value: leave.status)
            }
        }
        .navigationTitle("Leave Details")
    }
}

struct ModernPaymentsView: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var drafts: ReceiptDraftStore
    @State private var section = 0
    @State private var query = ""
    @State private var showingForm = false

    private var filteredRows: [PaymentRow] {
        let data = section == 0 ? store.payments : store.receipts
        return data.filter { query.isEmpty || "\($0.number) \($0.party) \($0.purpose)".localizedCaseInsensitiveContains(query) }
    }
    private var filteredDrafts: [ReceiptDraft] {
        drafts.items.filter { $0.entityID == store.selectedEntityID && (query.isEmpty || "\($0.receivedFrom) \($0.receivedBy) \($0.notes)".localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MobileModuleHeader(title: "Payments & Receipts", subtitle: "Vouchers and secure local receipt drafts")
                    MobileCompanyPicker()
                    HStack(spacing: 10) {
                        miniStat(label: "Payments", count: store.payments.count, icon: "arrow.up.right")
                        miniStat(label: "Receipts", count: store.receipts.count, icon: "arrow.down.left")
                        miniStat(label: "Drafts", count: drafts.items.filter { $0.entityID == store.selectedEntityID }.count, icon: "square.and.pencil")
                    }
                    Picker("Transactions", selection: $section) {
                        Text("Payments").tag(0)
                        Text("Receipts").tag(1)
                        Text("Drafts").tag(2)
                    }.pickerStyle(.segmented)
                    if section != 2 {
                        HStack {
                            Picker("Month", selection: $store.selectedMonth) {
                                ForEach(1...12, id: \.self) { n in
                                    Text(Calendar.current.monthSymbols[n - 1]).tag(n)
                                }
                            }
                            Picker("Year", selection: $store.selectedYear) {
                                ForEach(2024...2032, id: \.self) { n in Text(String(n)).tag(n) }
                            }
                        }
                        .onChange(of: store.selectedMonth) { _ in Task { await store.refreshEntityData() } }
                        .onChange(of: store.selectedYear) { _ in Task { await store.refreshEntityData() } }
                    }
                    TextField("Search records", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    if section == 2 {
                        if filteredDrafts.isEmpty {
                            MobileEmpty(title: "No local drafts", detail: "Create a receipt draft without changing Windows data.", symbol: "doc.badge.plus")
                        } else {
                            ForEach(filteredDrafts) { draft in
                                NavigationLink { ReceiptDraftDetail(draft: draft) } label: {
                                    MobileCard {
                                        HStack {
                                            Text(draft.receivedFrom).font(.headline).foregroundStyle(.primary)
                                            Spacer()
                                            Text(money(draft.amount, draft.currency)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        }
                                        Text("Received by \(draft.receivedBy) • Local draft")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else if filteredRows.isEmpty {
                        MobileEmpty(title: "No \(section == 0 ? "payments" : "receipts") found", detail: "Import a Windows backup or select another company and period.", symbol: "tray")
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredRows) { row in
                                NavigationLink { VoucherDetailView(voucher: row) } label: {
                                    MobileCard {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(row.number.isEmpty ? "Voucher" : row.number)
                                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                            Spacer(minLength: 8)
                                            Text(money(row.amount, row.currency))
                                                .font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(.primary)
                                        }
                                        Text(row.party).foregroundStyle(.secondary).font(.subheadline)
                                        Text(row.date).foregroundStyle(.secondary).font(.caption)
                                    }
                                }
                            }
                        }
                    }
                    Label("Imported payment records are read-only. New receipts are saved locally as drafts.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                }
                .padding(16)
            }
            .background(MobilePalette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingForm = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                }
            }
            .sheet(isPresented: $showingForm) { ReceiptDraftForm() }
        }
    }

    private func miniStat(label: String, count: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).foregroundStyle(MobilePalette.accent)
            Text("\(count)").font(.title2.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MobilePalette.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct VoucherDetailView: View {
    @EnvironmentObject private var store: MobileStore
    let voucher: PaymentRow

    private var originalDocuments: [FileRow] {
        let ref = voucher.number.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ref.count >= 4 else { return [] }
        return store.files.filter { file in
            let ext = file.url.pathExtension.lowercased()
            let path = file.relative.lowercased()
            return ["pdf", "xlsx", "xls"].contains(ext)
                && (path.contains("payment") || path.contains("receipt") || path.contains("voucher"))
                && file.url.deletingPathExtension().lastPathComponent.lowercased().contains(ref)
        }
    }

    var body: some View {
        List {
            Section("Voucher") {
                LabeledContent("Number", value: voucher.number)
                LabeledContent("Date", value: voucher.date)
                LabeledContent("Party", value: voucher.party)
                LabeledContent("Amount", value: money(voucher.amount, voucher.currency))
                LabeledContent("Purpose", value: voucher.purpose)
                LabeledContent("Type", value: voucher.kind)
            }
            Section("Original PC documents") {
                if originalDocuments.isEmpty {
                    Text("No matching Windows-exported document was included in the restored snapshot. Mobile will not substitute a differently formatted PDF.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(originalDocuments) { file in
                        OriginalDesktopFileRow(file: file)
                    }
                }
            }
            Section {
                Text("Record copied from a Windows backup. It is read-only and not posted or changed on your PC.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Voucher Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ModernCompanyView: View {
    @EnvironmentObject private var store: MobileStore
    @Binding var importer: Bool
    @State private var showSettings = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MobileModuleHeader(title: "Company Information", subtitle: "Legal records, profiles and documents")
                    MobileCompanyPicker()
                    MobileCard {
                        Label("Company profile", systemImage: "building.2.crop.circle")
                            .font(.headline).foregroundStyle(MobilePalette.accent)
                        LabeledContent("Entity", value: store.selectedEntity?.name ?? "Not imported")
                        LabeledContent("Code", value: store.selectedEntity?.code ?? "—")
                        LabeledContent("Currency", value: store.selectedEntity?.currency ?? "—")
                    }
                    HStack {
                        Text("Company Documents").font(.title3.bold())
                        Spacer()
                        Text("\(store.companyDocs.count)").foregroundStyle(.secondary)
                    }
                    if store.companyDocs.isEmpty {
                        MobileEmpty(title: "No company records loaded", detail: "Import the latest Windows full backup to view CR, registration and other documents.", symbol: "folder.badge.questionmark")
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(store.companyDocs) { doc in
                                NavigationLink { CompanyDocumentDetail(document: doc) } label: {
                                    MobileCard {
                                        HStack {
                                            Label(doc.type, systemImage: "doc.text")
                                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(.tertiary).font(.caption)
                                        }
                                        Text(doc.number).font(.caption.monospaced()).foregroundStyle(.secondary)
                                        if !doc.expiry.isEmpty {
                                            Label("Expires \(doc.expiry)", systemImage: "calendar")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if store.currentDatabaseURL == nil {
                        Button { importer = true } label: {
                            Label("Import Windows Backup", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(MobilePalette.accent)
                    }
                }
                .padding(16)
            }
            .background(MobilePalette.canvas)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    MobileBackupCenter(showImporter: $importer)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
                }
            }
        }
    }
}

struct CompanyDocumentDetail: View {
    @EnvironmentObject private var store: MobileStore
    let document: CompanyDocRow
    var relatedFile: FileRow? {
        guard !document.path.isEmpty else { return nil }
        let name = (document.path as NSString).lastPathComponent
        return store.files.first { $0.relative == document.path || $0.url.lastPathComponent == name }
    }
    var body: some View {
        List {
            Section("Registration") {
                LabeledContent("Type", value: document.type)
                LabeledContent("Number", value: document.number)
                LabeledContent("Legal name", value: document.legalName)
                LabeledContent("Expiry", value: document.expiry.isEmpty ? "—" : document.expiry)
            }
            Section("Supporting document") {
                if let file = relatedFile { FileLinkRow(file: file) }
                else { Text("Attachment not included in this backup").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Company Document")
    }
}

struct ModernZeeView: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var drafts: ReceiptDraftStore
    @State private var question = ""
    @State private var submittedQuery = ""
    @State private var answers: [SearchHit] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MobileModuleHeader(title: "Agent Zee", subtitle: "Your local business-record assistant")
                    MobileCompanyPicker()
                    MobileCard {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title2).foregroundStyle(MobilePalette.accent)
                                .frame(width: 52, height: 52)
                                .background(MobilePalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 17))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Zee • Local Mode").font(.headline)
                                Text("Searches imported records. No AI API or cloud connection in this build.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Find an employee, receipt, document…", text: $question)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit(runSearch)
                        Button(action: runSearch) {
                            Image(systemName: "arrow.up")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 39, height: 39)
                                .background(MobilePalette.accent, in: RoundedRectangle(cornerRadius: 13))
                        }.accessibilityLabel("Search local records")
                    }
                    HStack {
                        shortcut("Employees")
                        shortcut("Receipts")
                        shortcut("Company")
                    }
                    if !submittedQuery.isEmpty {
                        Text("Results for “\(submittedQuery)”").font(.headline)
                        if answers.isEmpty {
                            MobileEmpty(title: "No matching records", detail: "Try a receipt number, employee name, company document number or another keyword.", symbol: "magnifyingglass")
                        } else {
                            ForEach(answers) { result in
                                MobileCard {
                                    Text(result.module.uppercased())
                                        .font(.system(size: 10, weight: .semibold)).tracking(1)
                                        .foregroundStyle(MobilePalette.accent)
                                    Text(result.title).font(.subheadline.weight(.semibold))
                                    Text(result.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        MobileEmpty(title: "Ask Zee to find a record", detail: "The first release searches your imported local snapshot. Managed agent actions can be integrated after secure authorization.", symbol: "text.magnifyingglass")
                    }
                }
                .padding(16)
            }
            .background(MobilePalette.canvas)
        }
    }
    private func shortcut(_ label: String) -> some View {
        Button(label) { question = label; runSearch() }
            .font(.caption.weight(.medium))
            .buttonStyle(.bordered)
            .tint(MobilePalette.accent)
    }
    private func runSearch() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        submittedQuery = q
        if q.localizedCaseInsensitiveContains("employee") || q.localizedCaseInsensitiveContains("staff") {
            answers = store.employees.prefix(50).map { SearchHit(module: "HR", title: $0.name, detail: "\($0.no) • \($0.position)") }
        } else if q.localizedCaseInsensitiveContains("receipt") {
            answers = store.receipts.prefix(50).map { SearchHit(module: "Receipts", title: $0.number, detail: "\($0.party) • \(money($0.amount, $0.currency))") }
            answers += drafts.items.filter { $0.entityID == store.selectedEntityID }.prefix(30).map {
                SearchHit(module: "Local draft", title: $0.receivedFrom, detail: money($0.amount, $0.currency))
            }
        } else if q.localizedCaseInsensitiveContains("company") {
            answers = store.companyDocs.prefix(50).map { SearchHit(module: "Company", title: $0.type, detail: "\($0.number) • \($0.legalName)") }
        } else {
            answers = store.searchSnapshot(q)
        }
    }
}
