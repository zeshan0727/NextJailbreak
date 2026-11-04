import SwiftUI

// MARK: - Dashboard Preferences

enum AspireDashboardStyle: String, CaseIterable, Identifiable {
    case hybrid = "hybrid"
    case executive = "executive"
    case todayFirst = "todayFirst"
    case financeOperations = "financeOperations"
    case appleModular = "appleModular"
    case customerPipeline = "customerPipeline"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hybrid: return "Hybrid Default"
        case .executive: return "Executive Cards"
        case .todayFirst: return "Today-First"
        case .financeOperations: return "Finance + Operations"
        case .appleModular: return "Apple-style Modular"
        case .customerPipeline: return "Customer Pipeline"
        }
    }

    var subtitle: String {
        switch self {
        case .hybrid: return "Finance, operations, alerts and quick actions"
        case .executive: return "Overall business overview and performance"
        case .todayFirst: return "Daily field work and visit schedule"
        case .financeOperations: return "Management control for money and service delivery"
        case .appleModular: return "Premium widget-style cards and activity"
        case .customerPipeline: return "Quotation → invoice → payment workflow"
        }
    }

    var icon: String {
        switch self {
        case .hybrid: return "square.grid.2x2.fill"
        case .executive: return "chart.bar.xaxis"
        case .todayFirst: return "calendar.badge.clock"
        case .financeOperations: return "chart.line.uptrend.xyaxis"
        case .appleModular: return "rectangle.grid.2x2.fill"
        case .customerPipeline: return "arrow.triangle.branch"
        }
    }
}

enum DashboardSectionID: String, CaseIterable, Identifiable {
    case summary
    case pipeline
    case today
    case alerts
    case quickActions
    case monthlyVisits
    case receivables
    case recentActivity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: return "Summary Cards"
        case .pipeline: return "Business Pipeline"
        case .today: return "Today's Visits"
        case .alerts: return "Attention Required"
        case .quickActions: return "Quick Actions"
        case .monthlyVisits: return "Monthly Visits Progress"
        case .receivables: return "Receivables"
        case .recentActivity: return "Recent Activity"
        }
    }

    var icon: String {
        switch self {
        case .summary: return "square.grid.2x2"
        case .pipeline: return "arrow.right.circle"
        case .today: return "calendar"
        case .alerts: return "exclamationmark.triangle"
        case .quickActions: return "bolt.fill"
        case .monthlyVisits: return "leaf.circle"
        case .receivables: return "banknote"
        case .recentActivity: return "clock.arrow.circlepath"
        }
    }

    static let defaultOrder: [DashboardSectionID] = [
        .summary, .pipeline, .today, .alerts, .quickActions, .monthlyVisits, .receivables, .recentActivity
    ]
}

enum DashboardPreferenceKeys {
    static let style = "aspire.dashboard.style"
    static let showSummary = "aspire.dashboard.show.summary"
    static let showPipeline = "aspire.dashboard.show.pipeline"
    static let showToday = "aspire.dashboard.show.today"
    static let showAlerts = "aspire.dashboard.show.alerts"
    static let showQuickActions = "aspire.dashboard.show.quickActions"
    static let showMonthlyVisits = "aspire.dashboard.show.monthlyVisits"
    static let showReceivables = "aspire.dashboard.show.receivables"
    static let showRecentActivity = "aspire.dashboard.show.recentActivity"
    static let sectionOrder = "aspire.dashboard.sectionOrder"
    static let showHeader = "aspire.dashboard.showHeader"
}

struct DashboardVisibility {
    let summary: Bool
    let pipeline: Bool
    let today: Bool
    let alerts: Bool
    let quickActions: Bool
    let monthlyVisits: Bool
    let receivables: Bool
    let recentActivity: Bool

    func contains(_ section: DashboardSectionID) -> Bool {
        switch section {
        case .summary: return summary
        case .pipeline: return pipeline
        case .today: return today
        case .alerts: return alerts
        case .quickActions: return quickActions
        case .monthlyVisits: return monthlyVisits
        case .receivables: return receivables
        case .recentActivity: return recentActivity
        }
    }
}

enum DashboardSectionOrderCodec {
    static let defaultValue = DashboardSectionID.defaultOrder.map(\.rawValue).joined(separator: ",")

    static func decode(_ raw: String) -> [DashboardSectionID] {
        var decoded = raw.split(separator: ",").compactMap { DashboardSectionID(rawValue: String($0)) }
        for item in DashboardSectionID.defaultOrder where !decoded.contains(item) { decoded.append(item) }
        return decoded
    }

    static func encode(_ items: [DashboardSectionID]) -> String {
        items.map(\.rawValue).joined(separator: ",")
    }
}

// MARK: - Dashboard Host

struct AspireDashboardHostView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var selectedMonth = Date()

    @AppStorage(DashboardPreferenceKeys.style) private var styleRaw = AspireDashboardStyle.hybrid.rawValue
    @AppStorage(DashboardPreferenceKeys.showSummary) private var showSummary = true
    @AppStorage(DashboardPreferenceKeys.showPipeline) private var showPipeline = true
    @AppStorage(DashboardPreferenceKeys.showToday) private var showToday = true
    @AppStorage(DashboardPreferenceKeys.showAlerts) private var showAlerts = true
    @AppStorage(DashboardPreferenceKeys.showQuickActions) private var showQuickActions = true
    @AppStorage(DashboardPreferenceKeys.showMonthlyVisits) private var showMonthlyVisits = true
    @AppStorage(DashboardPreferenceKeys.showReceivables) private var showReceivables = true
    @AppStorage(DashboardPreferenceKeys.showRecentActivity) private var showRecentActivity = true
    @AppStorage(DashboardPreferenceKeys.sectionOrder) private var sectionOrderRaw = DashboardSectionOrderCodec.defaultValue
    @AppStorage(DashboardPreferenceKeys.showHeader) private var showHeader = true

    private var style: AspireDashboardStyle { AspireDashboardStyle(rawValue: styleRaw) ?? .hybrid }
    private var visibility: DashboardVisibility {
        DashboardVisibility(
            summary: showSummary,
            pipeline: showPipeline,
            today: showToday,
            alerts: showAlerts,
            quickActions: showQuickActions,
            monthlyVisits: showMonthlyVisits,
            receivables: showReceivables,
            recentActivity: showRecentActivity
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    if showHeader {
                        DashboardBrandHeader(month: $selectedMonth, style: style)
                    } else {
                        DashboardMonthStrip(month: $selectedMonth)
                    }

                    Group {
                        switch style {
                        case .hybrid:
                            HybridDashboardLayout(
                                month: selectedMonth,
                                visibility: visibility,
                                sectionOrder: DashboardSectionOrderCodec.decode(sectionOrderRaw)
                            )
                        case .executive:
                            ExecutiveDashboardLayout(month: selectedMonth, visibility: visibility)
                        case .todayFirst:
                            TodayFirstDashboardLayout(month: selectedMonth, visibility: visibility)
                        case .financeOperations:
                            FinanceOperationsDashboardLayout(month: selectedMonth, visibility: visibility)
                        case .appleModular:
                            AppleModularDashboardLayout(month: selectedMonth, visibility: visibility)
                        case .customerPipeline:
                            CustomerPipelineDashboardLayout(month: selectedMonth, visibility: visibility)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Aspire Maintenance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink { DashboardSettingsView() } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    Button {
                        Task { await store.refreshOverdueNotifications() }
                    } label: {
                        Image(systemName: "bell.badge")
                    }
                }
            }
        }
    }
}

// MARK: - Brand / Month

struct DashboardBrandHeader: View {
    @EnvironmentObject private var store: AspireStore
    @Binding var month: Date
    let style: AspireDashboardStyle

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                StoredLogoView(data: store.appLogoData)
                    .frame(width: 118, height: 58)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(style.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.aspireGreen)
                    Text("ASPIRE GARDEN • EST. 2009")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            DashboardMonthStrip(month: $month)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.top, 8)
    }
}

struct DashboardMonthStrip: View {
    @Binding var month: Date

    var body: some View {
        HStack(spacing: 12) {
            Button { month = Calendar.current.addingMonths(-1, to: month) } label: {
                Image(systemName: "chevron.left").frame(width: 28, height: 28)
            }
            Spacer()
            Label(DateFormatter.monthAndYear.string(from: month), systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button { month = Calendar.current.addingMonths(1, to: month) } label: {
                Image(systemName: "chevron.right").frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.aspireGreen)
    }
}

// MARK: - Hybrid Dashboard

struct HybridDashboardLayout: View {
    let month: Date
    let visibility: DashboardVisibility
    let sectionOrder: [DashboardSectionID]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(sectionOrder) { section in
                if visibility.contains(section) {
                    hybridSection(section)
                }
            }
        }
    }

    @ViewBuilder
    private func hybridSection(_ section: DashboardSectionID) -> some View {
        switch section {
        case .summary: DashboardSummaryCards(month: month)
        case .pipeline: DashboardPipelineSection(month: month)
        case .today: DashboardTodayVisitsSection()
        case .alerts: DashboardAttentionSection(month: month)
        case .quickActions: DashboardQuickActionsSection()
        case .monthlyVisits: DashboardMonthlyVisitsSection(month: month)
        case .receivables: DashboardReceivablesSection()
        case .recentActivity: DashboardRecentActivitySection(month: month)
        }
    }
}

// MARK: - Executive Dashboard

struct ExecutiveDashboardLayout: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date
    let visibility: DashboardVisibility

    private var revenue: Double { store.invoicedIncome(in: month) }
    private var expenses: Double { store.expensesTotal(in: month) }
    private var profit: Double { revenue - expenses }

    private var trendMonths: [Date] {
        (-5...0).compactMap { Calendar.current.date(byAdding: .month, value: $0, to: month) }
    }

    var body: some View {
        VStack(spacing: 14) {
            if visibility.summary {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Executive Overview").font(.headline)
                            Text(DateFormatter.monthAndYear.string(from: month)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chart.bar.xaxis").foregroundStyle(Color.aspireGreen)
                    }
                    HStack(alignment: .bottom, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.currency(revenue)).font(.title2.bold()).minimumScaleFactor(0.7)
                            Text("Revenue this month").font(.caption).foregroundStyle(.secondary)
                            Text(profit >= 0 ? "Net profit \(store.currency(profit))" : "Net loss \(store.currency(abs(profit)))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(profit >= 0 ? Color.aspireGreen : Color.red)
                        }
                        Spacer()
                        MiniTrendBars(values: trendMonths.map { store.invoicedIncome(in: $0) }, accent: .aspireGreen)
                            .frame(width: 115, height: 55)
                    }
                }
                .aspirePanel()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    NavigationLink { DashboardTransactionsView(kind: .collected, month: month) } label: {
                        DashboardMetricCard(title: "Collected", value: store.currency(store.collectedIncome(in: month)), icon: "checkmark.circle.fill", accent: .aspireGreen)
                    }.buttonStyle(.plain)
                    NavigationLink { ReceivableListView(kind: .outstanding) } label: {
                        DashboardMetricCard(title: "Receivable", value: store.currency(store.outstandingTotal()), icon: "banknote.fill", accent: .orange)
                    }.buttonStyle(.plain)
                    NavigationLink { DashboardTransactionsView(kind: .expenses, month: month) } label: {
                        DashboardMetricCard(title: "Expenses", value: store.currency(expenses), icon: "receipt.fill", accent: .aspireGold)
                    }.buttonStyle(.plain)
                    NavigationLink { CustomersView() } label: {
                        DashboardMetricCard(title: "Active Customers", value: "\(store.activeCustomers.count)", icon: "person.2.fill", accent: .blue)
                    }.buttonStyle(.plain)
                }
            }
            if visibility.pipeline { DashboardPipelineSection(month: month) }
            if visibility.receivables { DashboardReceivablesSection() }
            if visibility.monthlyVisits { DashboardMonthlyVisitsSection(month: month) }
            if visibility.alerts { DashboardAttentionSection(month: month) }
            if visibility.quickActions { DashboardQuickActionsSection() }
            if visibility.recentActivity { DashboardRecentActivitySection(month: month) }
        }
    }
}

// MARK: - Today First Dashboard

struct TodayFirstDashboardLayout: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date
    let visibility: DashboardVisibility

    private var todaySchedules: [ScheduledMaintenanceVisit] { store.scheduledVisits(on: Date()) }
    private var completedToday: Int {
        store.visits.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    var body: some View {
        VStack(spacing: 14) {
            if visibility.today {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DateFormatter.weekdayLong.string(from: Date())).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(DateFormatter.longDate.string(from: Date())).font(.headline)
                        }
                        Spacer()
                        Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(Color.aspireGreen)
                    }
                    HStack(spacing: 10) {
                        VisitHeroNumber(value: todaySchedules.count, label: "Scheduled")
                        VisitHeroNumber(value: completedToday, label: "Completed")
                        VisitHeroNumber(value: max(0, todaySchedules.count - completedToday), label: "Remaining")
                    }
                }
                .padding(18)
                .background(
                    LinearGradient(colors: [Color.aspireGreen.opacity(0.18), Color.aspireGreen.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )

                DashboardTodayVisitsSection()
            }

            if visibility.alerts { DashboardAttentionSection(month: month) }
            if visibility.quickActions { DashboardQuickActionsSection() }
            if visibility.summary {
                HStack(spacing: 10) {
                    NavigationLink { ReceivableListView(kind: .outstanding) } label: {
                        DashboardMetricCard(title: "Unpaid Invoices", value: store.currency(store.outstandingTotal()), icon: "doc.text.fill", accent: .orange)
                    }.buttonStyle(.plain)
                    NavigationLink { ContractsCenterView() } label: {
                        DashboardMetricCard(title: "Pending Quotes", value: "\(store.quotations.filter { $0.status == .draft || $0.status == .sent }.count)", icon: "doc.text.magnifyingglass", accent: .blue)
                    }.buttonStyle(.plain)
                }
            }
            if visibility.monthlyVisits { DashboardMonthlyVisitsSection(month: month) }
            if visibility.recentActivity { DashboardRecentActivitySection(month: month) }
        }
    }
}

struct VisitHeroNumber: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.title2.bold())
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Finance + Operations Dashboard

struct FinanceOperationsDashboardLayout: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date
    let visibility: DashboardVisibility

    private var planned: Int { store.monthlyMaintenanceCustomers.reduce(0) { $0 + max(0, $1.plannedVisitsPerMonth) } }
    private var done: Int { store.monthlyMaintenanceCustomers.reduce(0) { $0 + min(store.completedVisitCount(for: $1.id, in: month), max(0, $1.plannedVisitsPerMonth)) } }

    var body: some View {
        VStack(spacing: 14) {
            if visibility.summary {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Financial Overview", subtitle: DateFormatter.monthAndYear.string(from: month))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        DashboardMetricCard(title: "Revenue", value: store.currency(store.invoicedIncome(in: month)), icon: "chart.line.uptrend.xyaxis", accent: .aspireGreen)
                        DashboardMetricCard(title: "Collected", value: store.currency(store.collectedIncome(in: month)), icon: "banknote.fill", accent: .blue)
                        DashboardMetricCard(title: "Receivable", value: store.currency(store.outstandingTotal()), icon: "clock.badge.exclamationmark", accent: .orange)
                        DashboardMetricCard(title: "Expenses", value: store.currency(store.expensesTotal(in: month)), icon: "receipt.fill", accent: .aspireGold)
                    }
                    let netCash = store.collectedIncome(in: month) - store.expensesTotal(in: month)
                    HStack {
                        Text("Net Cash Flow").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(store.currency(netCash)).font(.headline).foregroundStyle(netCash >= 0 ? Color.aspireGreen : Color.red)
                    }
                    .padding(12)
                    .background(Color.aspireGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                .aspirePanel()
            }

            if visibility.today || visibility.monthlyVisits {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Operational Overview", subtitle: "Monthly maintenance delivery")
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().stroke(Color(.systemGray5), lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: planned > 0 ? min(1, Double(done) / Double(planned)) : 0)
                                .stroke(Color.aspireGreen, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 1) {
                                Text("\(done)/\(planned)").font(.headline.bold())
                                Text("Visits").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 105, height: 105)
                        VStack(spacing: 8) {
                            OperationalLine(title: "Monthly Customers", value: "\(store.monthlyMaintenanceCustomers.count)", icon: "person.2.fill")
                            OperationalLine(title: "Visits Pending", value: "\(max(0, planned - done))", icon: "clock.fill")
                            OperationalLine(title: "Employees", value: "\(store.activeEmployees.count)", icon: "person.3.fill")
                        }
                    }
                }
                .aspirePanel()
            }

            if visibility.pipeline { DashboardPipelineSection(month: month) }
            if visibility.monthlyVisits { DashboardMonthlyVisitsSection(month: month) }
            if visibility.alerts { DashboardAttentionSection(month: month) }
            if visibility.quickActions { DashboardQuickActionsSection() }
            if visibility.receivables { DashboardReceivablesSection() }
            if visibility.recentActivity { DashboardRecentActivitySection(month: month) }
        }
    }
}

struct OperationalLine: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Color.aspireGreen).frame(width: 22)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.bold))
        }
    }
}

// MARK: - Apple-style Modular Dashboard

struct AppleModularDashboardLayout: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date
    let visibility: DashboardVisibility

    private var planned: Int { store.monthlyMaintenanceCustomers.reduce(0) { $0 + max(0, $1.plannedVisitsPerMonth) } }
    private var completed: Int { store.monthlyMaintenanceCustomers.reduce(0) { $0 + min(store.completedVisitCount(for: $1.id, in: month), max(0, $1.plannedVisitsPerMonth)) } }

    private var trend: [Double] {
        (-7...0).compactMap { Calendar.current.date(byAdding: .month, value: $0, to: month) }.map { store.invoicedIncome(in: $0) }
    }

    var body: some View {
        VStack(spacing: 12) {
            if visibility.summary {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Revenue This Month").font(.caption.weight(.semibold)).opacity(0.78)
                            Text(store.currency(store.invoicedIncome(in: month))).font(.title.bold()).minimumScaleFactor(0.7)
                            Text("Business performance").font(.caption2).opacity(0.70)
                        }
                        Spacer()
                        MiniTrendBars(values: trend, accent: .white).frame(width: 120, height: 65)
                    }
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(
                    LinearGradient(colors: [Color.purple.opacity(0.88), Color.indigo.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )

                HStack(spacing: 10) {
                    AppleWidgetCard(title: "Visits", value: "\(completed)/\(planned)", icon: "leaf.fill", accent: .cyan, detail: "Completed")
                    AppleWidgetCard(title: "Receivables", value: store.currency(store.outstandingTotal()), icon: "banknote.fill", accent: .orange, detail: "Outstanding")
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    SmallAppleWidget(title: "Quotes", value: "\(store.quotations.count)", icon: "doc.text")
                    SmallAppleWidget(title: "Projects", value: "\(store.activeCustomers.filter { $0.resolvedType == .project }.count)", icon: "building.2")
                    SmallAppleWidget(title: "Overdue", value: "\(store.overdueInvoices().count)", icon: "exclamationmark.circle")
                    SmallAppleWidget(title: "Employees", value: "\(store.activeEmployees.count)", icon: "person.3")
                    SmallAppleWidget(title: "Customers", value: "\(store.activeCustomers.count)", icon: "person.2")
                    SmallAppleWidget(title: "Visits Due", value: "\(max(0, planned - completed))", icon: "calendar.badge.clock")
                }
            }

            if visibility.recentActivity { DashboardRecentActivitySection(month: month) }
            if visibility.quickActions { DashboardQuickActionsSection() }
            if visibility.monthlyVisits { DashboardMonthlyVisitsSection(month: month) }
            if visibility.pipeline { DashboardPipelineSection(month: month) }
            if visibility.alerts { DashboardAttentionSection(month: month) }
            if visibility.receivables { DashboardReceivablesSection() }
        }
    }
}

struct AppleWidgetCard: View {
    let title: String
    let value: String
    let icon: String
    let accent: Color
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(accent)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.65)
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SmallAppleWidget: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(Color.aspireGreen)
            Text(value).font(.headline.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
    }
}

// MARK: - Customer Pipeline Dashboard

struct CustomerPipelineDashboardLayout: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date
    let visibility: DashboardVisibility

    private var monthQuotes: [Quotation] {
        store.quotations.filter { Calendar.current.isDate($0.issueDate, equalTo: month, toGranularity: .month) }
    }
    private var accepted: [Quotation] { monthQuotes.filter { $0.status == .accepted } }
    private var invoiced: [Quotation] { monthQuotes.filter { $0.convertedInvoiceID != nil } }
    private var paid: [Quotation] {
        invoiced.filter { quote in
            guard let id = quote.convertedInvoiceID, let invoice = store.invoice(id: id) else { return false }
            return invoice.status == .paid
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if visibility.pipeline {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Pipeline Overview", subtitle: "Quotation → accepted → invoiced → paid")
                    VerticalPipelineRow(title: "Quotations", value: monthQuotes.count, icon: "doc.text.magnifyingglass", accent: .purple)
                    PipelineConnector()
                    VerticalPipelineRow(title: "Accepted", value: accepted.count, icon: "checkmark.seal.fill", accent: .orange)
                    PipelineConnector()
                    VerticalPipelineRow(title: "Invoiced", value: invoiced.count, icon: "doc.text.fill", accent: .blue)
                    PipelineConnector()
                    VerticalPipelineRow(title: "Paid", value: paid.count, icon: "checkmark.circle.fill", accent: .aspireGreen)
                    NavigationLink { ContractsCenterView() } label: {
                        Label("Open Contracts & Quotations", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.aspireGreen)
                }
                .aspirePanel()
            }

            if visibility.alerts { DashboardAttentionSection(month: month) }

            if visibility.recentActivity {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Recent Quotations", subtitle: "Latest customer opportunities")
                    if store.quotations.isEmpty {
                        EmptyInlineView(icon: "doc.text", text: "No quotations yet")
                    } else {
                        ForEach(Array(store.quotations.prefix(4))) { quotation in
                            NavigationLink { QuotationDetailView(quotationID: quotation.id) } label: {
                                QuotationRow(quotation: quotation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .aspirePanel()
            }

            if visibility.quickActions { DashboardQuickActionsSection() }
            if visibility.summary { DashboardSummaryCards(month: month) }
            if visibility.monthlyVisits { DashboardMonthlyVisitsSection(month: month) }
            if visibility.receivables { DashboardReceivablesSection() }
        }
    }
}

struct VerticalPipelineRow: View {
    let title: String
    let value: Int
    let icon: String
    let accent: Color
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(accent.opacity(0.12))
                Image(systemName: icon).foregroundStyle(accent)
            }.frame(width: 42, height: 42)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(value)").font(.title3.bold()).foregroundStyle(accent)
        }
        .padding(12)
        .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PipelineConnector: View {
    var body: some View {
        HStack {
            Image(systemName: "arrow.down").font(.caption.bold()).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.leading, 14)
        .frame(height: 8)
    }
}

// MARK: - Shared Dashboard Sections

struct DashboardSummaryCards: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date

    private var planned: Int { store.monthlyMaintenanceCustomers.reduce(0) { $0 + max(0, $1.plannedVisitsPerMonth) } }
    private var completed: Int { store.monthlyMaintenanceCustomers.reduce(0) { $0 + min(store.completedVisitCount(for: $1.id, in: month), max(0, $1.plannedVisitsPerMonth)) } }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NavigationLink { DashboardTransactionsView(kind: .invoiced, month: month) } label: {
                DashboardMetricCard(title: "Revenue", value: store.currency(store.invoicedIncome(in: month)), icon: "chart.line.uptrend.xyaxis", accent: .aspireGreen, detail: "This month")
            }.buttonStyle(.plain)
            NavigationLink { ReceivableListView(kind: .outstanding) } label: {
                DashboardMetricCard(title: "Receivables", value: store.currency(store.outstandingTotal()), icon: "banknote.fill", accent: .orange, detail: "Outstanding")
            }.buttonStyle(.plain)
            NavigationLink { CustomersView() } label: {
                DashboardMetricCard(title: "Active Customers", value: "\(store.activeCustomers.count)", icon: "person.2.fill", accent: .blue, detail: "All segments")
            }.buttonStyle(.plain)
            NavigationLink { VisitCenterView() } label: {
                DashboardMetricCard(title: "Visits Due", value: "\(max(0, planned - completed))", icon: "calendar.badge.clock", accent: .aspireGold, detail: "Monthly maintenance")
            }.buttonStyle(.plain)
        }
    }
}

struct DashboardMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let accent: Color
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon).foregroundStyle(accent)
                Spacer()
            }
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.62)
            Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
        .padding(13)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(accent.opacity(0.12), lineWidth: 1))
    }
}

struct DashboardPipelineSection: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date

    private var monthQuotes: [Quotation] {
        store.quotations.filter { Calendar.current.isDate($0.issueDate, equalTo: month, toGranularity: .month) }
    }
    private var accepted: Int { monthQuotes.filter { $0.status == .accepted }.count }
    private var invoiced: Int { monthQuotes.filter { $0.convertedInvoiceID != nil }.count }
    private var paid: Int {
        monthQuotes.filter { quote in
            guard let invoiceID = quote.convertedInvoiceID, let invoice = store.invoice(id: invoiceID) else { return false }
            return invoice.status == .paid
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Business Pipeline", subtitle: "Quotation to payment")
                Spacer()
                NavigationLink { ContractsCenterView() } label: { Text("View All").font(.caption.weight(.semibold)) }
            }
            HStack(spacing: 5) {
                PipelineStep(label: "Quotes", value: monthQuotes.count, accent: .purple)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                PipelineStep(label: "Accepted", value: accepted, accent: .orange)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                PipelineStep(label: "Invoiced", value: invoiced, accent: .blue)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                PipelineStep(label: "Paid", value: paid, accent: .aspireGreen)
            }
        }
        .aspirePanel()
    }
}

struct PipelineStep: View {
    let label: String
    let value: Int
    let accent: Color
    var body: some View {
        VStack(spacing: 5) {
            Text("\(value)").font(.headline.bold()).foregroundStyle(accent)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DashboardTodayVisitsSection: View {
    @EnvironmentObject private var store: AspireStore

    private var schedules: [ScheduledMaintenanceVisit] {
        store.scheduledVisits(on: Date()).sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Today's Visits", subtitle: DateFormatter.longDate.string(from: Date()))
                Spacer()
                NavigationLink { VisitCenterView() } label: { Text("View All").font(.caption.weight(.semibold)) }
            }

            if schedules.isEmpty {
                EmptyInlineView(icon: "calendar", text: "No maintenance visits scheduled today")
            } else {
                ForEach(Array(schedules.prefix(5))) { schedule in
                    let assignment = store.visitAssignments(for: schedule.customerID, in: schedule.scheduledAt)[schedule.slot]
                    NavigationLink { VisitCustomerDetailView(customerID: schedule.customerID, month: schedule.scheduledAt) } label: {
                        HStack(spacing: 11) {
                            Text(DateFormatter.timeOnly.string(from: schedule.scheduledAt))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.aspireGreen)
                                .frame(width: 66, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.customer(id: schedule.customerID)?.name ?? "Customer")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                Text("\(VisitOrdinal.text(schedule.slot)) monthly visit")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: assignment == nil ? "clock" : "checkmark.circle.fill")
                                .foregroundStyle(assignment == nil ? Color.orange : Color.aspireGreen)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .aspirePanel()
    }
}

struct DashboardAttentionSection: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date

    private var expiringQuotes: [Quotation] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return store.quotations.filter {
            ($0.status == .draft || $0.status == .sent) && $0.validUntil >= now && $0.validUntil <= end
        }
    }

    private var overdueSchedules: [ScheduledMaintenanceVisit] { store.overdueScheduledVisits(asOf: Date(), in: month) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Attention Required", subtitle: "Items that need action")
            NavigationLink { ReceivableListView(kind: .overdue) } label: {
                AttentionRow(title: "Overdue Invoices", value: store.overdueInvoices().count, icon: "exclamationmark.circle.fill", accent: .red)
            }.buttonStyle(.plain)
            NavigationLink { ContractsCenterView() } label: {
                AttentionRow(title: "Quotations Expiring", value: expiringQuotes.count, icon: "clock.badge.exclamationmark.fill", accent: .orange)
            }.buttonStyle(.plain)
            NavigationLink { VisitCenterView() } label: {
                AttentionRow(title: "Visits Overdue", value: overdueSchedules.count, icon: "calendar.badge.exclamationmark", accent: .aspireGold)
            }.buttonStyle(.plain)
        }
        .aspirePanel()
    }
}

struct AttentionRow: View {
    let title: String
    let value: Int
    let icon: String
    let accent: Color
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(accent.opacity(0.12))
                Image(systemName: icon).font(.caption).foregroundStyle(accent)
            }.frame(width: 30, height: 30)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            Spacer()
            Text("\(value)").font(.subheadline.bold()).foregroundStyle(accent)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct DashboardReceivablesSection: View {
    @EnvironmentObject private var store: AspireStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Receivables", subtitle: "Customer balances and advances")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                NavigationLink { ReceivableListView(kind: .outstanding) } label: {
                    MetricPill(title: "Outstanding", value: store.currency(store.outstandingTotal()))
                }.buttonStyle(.plain)
                NavigationLink { ReceivableListView(kind: .overdue) } label: {
                    MetricPill(title: "Overdue", value: "\(store.overdueInvoices().count)")
                }.buttonStyle(.plain)
                NavigationLink { ReceivableListView(kind: .longOverdue) } label: {
                    MetricPill(title: "30+ Days", value: "\(store.longOverdueInvoices().count)")
                }.buttonStyle(.plain)
                NavigationLink { ReceivableListView(kind: .advances) } label: {
                    MetricPill(title: "Advance", value: store.currency(store.advanceTotal()))
                }.buttonStyle(.plain)
            }
        }
        .aspirePanel()
    }
}

enum DashboardQuickSheet: String, Identifiable {
    case customer, quote, invoice, visit, payment, expense
    var id: String { rawValue }
}

struct DashboardQuickActionsSection: View {
    @State private var sheet: DashboardQuickSheet?
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Quick Actions", subtitle: "Create or record in one tap")
            LazyVGrid(columns: columns, spacing: 9) {
                QuickActionTile(title: "Customer", icon: "person.badge.plus", accent: .aspireGreen) { sheet = .customer }
                QuickActionTile(title: "Quote", icon: "doc.text.magnifyingglass", accent: .purple) { sheet = .quote }
                QuickActionTile(title: "Invoice", icon: "doc.badge.plus", accent: .orange) { sheet = .invoice }
                QuickActionTile(title: "Visit", icon: "calendar.badge.plus", accent: .blue) { sheet = .visit }
                QuickActionTile(title: "Payment", icon: "banknote.fill", accent: .aspireGreen) { sheet = .payment }
                QuickActionTile(title: "Expense", icon: "receipt.fill", accent: .aspireGold) { sheet = .expense }
            }
        }
        .aspirePanel()
        .sheet(item: $sheet) { item in
            switch item {
            case .customer: CustomerEditorView()
            case .quote: QuotationEditorView()
            case .invoice: ManualInvoiceView()
            case .visit: VisitCenterView()
            case .payment: InvoicesView()
            case .expense: ExpenseEditorView()
            }
        }
    }
}

struct QuickActionTile: View {
    let title: String
    let icon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.12))
                    Image(systemName: icon).foregroundStyle(accent)
                }.frame(width: 38, height: 38)
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }
}

struct DashboardMonthlyVisitsSection: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date

    private var progress: [VisitCustomerProgress] {
        store.monthlyMaintenanceCustomers.map { customer in
            let completed = store.completedVisitCount(for: customer.id, in: month)
            return VisitCustomerProgress(customer: customer, completed: completed, remaining: max(0, customer.plannedVisitsPerMonth - completed))
        }
        .sorted {
            if $0.remaining == 0 && $1.remaining != 0 { return false }
            if $0.remaining != 0 && $1.remaining == 0 { return true }
            if $0.remaining != $1.remaining { return $0.remaining > $1.remaining }
            return $0.customer.name.localizedCaseInsensitiveCompare($1.customer.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Monthly Visits Progress", subtitle: "Monthly-maintenance customers only")
                Spacer()
                NavigationLink { VisitCenterView() } label: { Text("View All").font(.caption.weight(.semibold)) }
            }

            if progress.isEmpty {
                EmptyInlineView(icon: "leaf", text: "No monthly-maintenance customers")
            } else {
                ForEach(Array(progress.prefix(6))) { item in
                    NavigationLink { VisitCustomerDetailView(customerID: item.customer.id, month: month) } label: {
                        MonthlyVisitProgressRow(progress: item, month: month)
                    }
                    .buttonStyle(.plain)
                    if item.id != progress.prefix(6).last?.id { Divider() }
                }
            }
        }
        .aspirePanel()
    }
}

struct MonthlyVisitProgressRow: View {
    @EnvironmentObject private var store: AspireStore
    let progress: VisitCustomerProgress
    let month: Date

    private var total: Int { max(1, progress.customer.plannedVisitsPerMonth) }
    private var fraction: Double { min(1, Double(progress.completed) / Double(total)) }
    private var next: ScheduledMaintenanceVisit? { store.nextScheduledVisit(for: progress.customer.id, in: month) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.09))
                    Image(systemName: "house.and.flag.fill").foregroundStyle(Color.blue)
                }.frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.customer.name)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2).minimumScaleFactor(0.78)
                    Text("\(progress.completed) of \(progress.customer.plannedVisitsPerMonth) visits completed")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(progress.remaining == 0 ? "COMPLETED" : "\(progress.remaining) LEFT")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(progress.remaining == 0 ? Color.aspireGreen : Color.orange)
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.caption.weight(.bold)).foregroundStyle(Color.aspireGreen)
                }
            }

            ProgressView(value: fraction).tint(progress.remaining == 0 ? .aspireGreen : .aspireGreen)

            HStack {
                if progress.remaining == 0 {
                    Label("Monthly plan completed", systemImage: "checkmark.seal.fill")
                        .font(.caption2).foregroundStyle(Color.aspireGreen)
                } else if let next {
                    let overdue = next.scheduledAt < Date()
                    Label("Next: \(DateFormatter.shortDateTime.string(from: next.scheduledAt))", systemImage: overdue ? "exclamationmark.circle.fill" : "calendar")
                        .font(.caption2)
                        .foregroundStyle(overdue ? Color.red : .secondary)
                } else {
                    Label("Next visit not scheduled", systemImage: "calendar.badge.plus")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DashboardRecentActivitySection: View {
    @EnvironmentObject private var store: AspireStore
    let month: Date

    private var recentInvoices: [Invoice] {
        Array(store.invoices.filter { Calendar.current.isDate($0.issueDate, equalTo: month, toGranularity: .month) }.prefix(3))
    }
    private var recentVisits: [MaintenanceVisit] {
        Array(store.visits(in: month).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent Activity", subtitle: DateFormatter.monthAndYear.string(from: month))
            if recentInvoices.isEmpty && recentVisits.isEmpty {
                EmptyInlineView(icon: "clock", text: "No recent activity this month")
            } else {
                ForEach(recentInvoices) { invoice in
                    NavigationLink { InvoiceDetailView(invoiceID: invoice.id) } label: {
                        DashboardActivityRow(
                            icon: invoice.status == .paid ? "checkmark.circle.fill" : "doc.text.fill",
                            title: invoice.status == .paid ? "Payment / invoice updated" : "Invoice created",
                            subtitle: store.customer(id: invoice.customerID)?.name ?? invoice.number,
                            trailing: store.currency(invoice.total),
                            accent: invoice.status == .paid ? .aspireGreen : .blue
                        )
                    }.buttonStyle(.plain)
                }
                ForEach(recentVisits) { visit in
                    NavigationLink { VisitCustomerDetailView(customerID: visit.customerID, month: visit.date) } label: {
                        DashboardActivityRow(
                            icon: "leaf.circle.fill",
                            title: "Visit completed",
                            subtitle: store.customer(id: visit.customerID)?.name ?? "Maintenance customer",
                            trailing: DateFormatter.shortDate.string(from: visit.date),
                            accent: .aspireGreen
                        )
                    }.buttonStyle(.plain)
                }
            }
        }
        .aspirePanel()
    }
}

struct DashboardActivityRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let trailing: String
    let accent: Color
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(trailing).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

struct MiniTrendBars: View {
    let values: [Double]
    let accent: Color

    private var maxValue: Double { max(values.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(accent.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(5, 52 * value / maxValue))
            }
        }
    }
}

// MARK: - Dashboard Settings

struct DashboardSettingsView: View {
    @AppStorage(DashboardPreferenceKeys.style) private var styleRaw = AspireDashboardStyle.hybrid.rawValue
    @AppStorage(DashboardPreferenceKeys.showHeader) private var showHeader = true

    private var selectedStyle: AspireDashboardStyle { AspireDashboardStyle(rawValue: styleRaw) ?? .hybrid }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Dashboard Style", systemImage: "paintpalette.fill")
                        .font(.headline).foregroundStyle(Color.aspireGreen)
                    Text("Choose the layout that best fits your role. You can switch at any time without changing your business data.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Dashboard Style") {
                ForEach(AspireDashboardStyle.allCases) { style in
                    Button { styleRaw = style.rawValue } label: {
                        HStack(spacing: 12) {
                            Image(systemName: style.icon).foregroundStyle(Color.aspireGreen).frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(style.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if selectedStyle == style { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.aspireGreen) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Customize Dashboard") {
                Toggle(isOn: $showHeader) {
                    SettingsRow(icon: "photo", title: "Show Aspire Header", subtitle: "Display logo and selected dashboard style")
                }
                NavigationLink { DashboardSectionVisibilityView() } label: {
                    SettingsRow(icon: "eye.fill", title: "Show / Hide Sections", subtitle: "Control cards, pipeline, visits, alerts and activity")
                }
                NavigationLink { DashboardSectionOrderView() } label: {
                    SettingsRow(icon: "arrow.up.arrow.down", title: "Reorder Sections", subtitle: "Change Hybrid Dashboard section order")
                }
            }

            Section("Current Default") {
                LabeledContent("Landing Dashboard", value: selectedStyle.title)
                Text("The selected style opens automatically whenever you return to Dashboard.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Dashboard Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DashboardSectionVisibilityView: View {
    @AppStorage(DashboardPreferenceKeys.showSummary) private var showSummary = true
    @AppStorage(DashboardPreferenceKeys.showPipeline) private var showPipeline = true
    @AppStorage(DashboardPreferenceKeys.showToday) private var showToday = true
    @AppStorage(DashboardPreferenceKeys.showAlerts) private var showAlerts = true
    @AppStorage(DashboardPreferenceKeys.showQuickActions) private var showQuickActions = true
    @AppStorage(DashboardPreferenceKeys.showMonthlyVisits) private var showMonthlyVisits = true
    @AppStorage(DashboardPreferenceKeys.showReceivables) private var showReceivables = true
    @AppStorage(DashboardPreferenceKeys.showRecentActivity) private var showRecentActivity = true

    var body: some View {
        List {
            Section("Visible Sections") {
                DashboardVisibilityToggle(title: "Summary Cards", icon: "square.grid.2x2", isOn: $showSummary)
                DashboardVisibilityToggle(title: "Business Pipeline", icon: "arrow.right.circle", isOn: $showPipeline)
                DashboardVisibilityToggle(title: "Today's Visits", icon: "calendar", isOn: $showToday)
                DashboardVisibilityToggle(title: "Attention Required", icon: "exclamationmark.triangle", isOn: $showAlerts)
                DashboardVisibilityToggle(title: "Quick Actions", icon: "bolt.fill", isOn: $showQuickActions)
                DashboardVisibilityToggle(title: "Monthly Visits Progress", icon: "leaf.circle", isOn: $showMonthlyVisits)
                DashboardVisibilityToggle(title: "Receivables", icon: "banknote", isOn: $showReceivables)
                DashboardVisibilityToggle(title: "Recent Activity", icon: "clock.arrow.circlepath", isOn: $showRecentActivity)
            }
            Section {
                Button("Show All Sections") {
                    showSummary = true; showPipeline = true; showToday = true; showAlerts = true
                    showQuickActions = true; showMonthlyVisits = true; showReceivables = true; showRecentActivity = true
                }
            }
        }
        .navigationTitle("Dashboard Sections")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DashboardVisibilityToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: icon).foregroundStyle(.primary)
        }
        .tint(.aspireGreen)
    }
}

struct DashboardSectionOrderView: View {
    @AppStorage(DashboardPreferenceKeys.sectionOrder) private var orderRaw = DashboardSectionOrderCodec.defaultValue
    @State private var order: [DashboardSectionID] = DashboardSectionID.defaultOrder

    var body: some View {
        List {
            Section {
                Text("Drag sections into the order you want on the Hybrid Default dashboard. Hidden sections keep their position for when you show them again.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Hybrid Section Order") {
                ForEach(order) { section in
                    Label(section.title, systemImage: section.icon)
                }
                .onMove { source, destination in
                    order.move(fromOffsets: source, toOffset: destination)
                    save()
                }
            }
            Section {
                Button("Reset Default Order") {
                    order = DashboardSectionID.defaultOrder
                    save()
                }
            }
        }
        .navigationTitle("Reorder Sections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear { order = DashboardSectionOrderCodec.decode(orderRaw) }
    }

    private func save() { orderRaw = DashboardSectionOrderCodec.encode(order) }
}

// MARK: - Date Formatters for Dashboard

extension DateFormatter {
    static let weekdayLong: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
