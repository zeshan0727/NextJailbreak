import Charts
import Foundation
import SwiftUI
import UIKit

enum DeveloperLabKey {
    static let enabled = "NLDevEnabled"

    static let density = "NLDevDensity"
    static let cardDepth = "NLDevCardDepth"
    static let cardCornerRadius = "NLDevCardCornerRadius"
    static let cardShadowOpacity = "NLDevCardShadowOpacity"
    static let cardShadowRadius = "NLDevCardShadowRadius"
    static let cardBorderWidth = "NLDevCardBorderWidth"
    static let reportBlockSpacing = "NLDevReportBlockSpacing"
    static let reportPagePadding = "NLDevReportPagePadding"

    static let chartType = "NLDevChartType"
    static let chartDepth = "NLDevChartDepth"
    static let chartHeight = "NLDevChartHeight"
    static let chartCornerRadius = "NLDevChartCornerRadius"
    static let chartSideBySide = "NLDevChartSideBySide"
    static let chartShowLegend = "NLDevChartShowLegend"
    static let chartShowIncome = "NLDevChartShowIncome"
    static let chartShowExpense = "NLDevChartShowExpense"
    static let chartShowXAxis = "NLDevChartShowXAxis"
    static let chartShowYAxis = "NLDevChartShowYAxis"
    static let chartShowGrid = "NLDevChartShowGrid"
    static let chartShowPoints = "NLDevChartShowPoints"
    static let chartShowValues = "NLDevChartShowValues"

    static let showReportPeriodPicker = "NLDevShowReportPeriodPicker"
    static let showReportPeriodNavigator = "NLDevShowReportPeriodNavigator"
    static let showReportActivityChart = "NLDevShowReportActivityChart"
    static let showReportCategoryBreakdown = "NLDevShowReportCategoryBreakdown"
    static let showReportTransactionList = "NLDevShowReportTransactionList"
    static let showReportDownload = "NLDevShowReportDownload"
    static let showReportFooterTotal = "NLDevShowReportFooterTotal"
    static let showReportTransactionCount = "NLDevShowReportTransactionCount"
    static let reportTransactionOrder = "NLDevReportTransactionOrder"
    static let reportCategoryLimit = "NLDevReportCategoryLimit"
    static let showCategoryProgress = "NLDevShowCategoryProgress"
    static let showReportsRegisters = "NLDevShowReportsRegisters"
    static let showReportsPlanning = "NLDevShowReportsPlanning"
    static let showReportsCore = "NLDevShowReportsCore"
    static let showReportsStatements = "NLDevShowReportsStatements"

    static let showSummaryNetBalance = "NLDevShowSummaryNetBalance"
    static let showSummaryRateNote = "NLDevShowSummaryRateNote"
    static let showSummaryConnectors = "NLDevShowSummaryConnectors"
    static let showSummaryIncomeColumn = "NLDevShowSummaryIncomeColumn"
    static let showSummaryExpenseColumn = "NLDevShowSummaryExpenseColumn"
    static let showSummaryPrimaryCards = "NLDevShowSummaryPrimaryCards"
    static let showSummaryRefunds = "NLDevShowSummaryRefunds"
    static let showSummaryLoans = "NLDevShowSummaryLoans"
    static let showSummaryOperators = "NLDevShowSummaryOperators"
    static let showSummaryOpeningBalance = "NLDevShowSummaryOpeningBalance"
    static let showSummaryCustomBalanceCards = "NLDevShowSummaryCustomBalanceCards"
    static let showSummaryPKRConversion = "NLDevShowSummaryPKRConversion"
    static let summaryCompactCards = "NLDevSummaryCompactCards"
    static let summaryLoanSort = "NLDevSummaryLoanSort"

    static let dashboardShowHeader = "NLDevDashboardShowHeader"
    static let dashboardShowSpending = "NLDevDashboardShowSpending"
    static let dashboardShowDateFilter = "NLDevDashboardShowDateFilter"
    static let dashboardShowBalance = "NLDevDashboardShowBalance"
    static let dashboardShowQuickActions = "NLDevDashboardShowQuickActions"
    static let dashboardShowRecent = "NLDevDashboardShowRecent"
    static let dashboardColumns = "NLDevDashboardColumns"
    static let dashboardHorizontalPadding = "NLDevDashboardHorizontalPadding"
    static let dashboardSectionSpacing = "NLDevDashboardSectionSpacing"
    static let dashboardRecentLimit = "NLDevDashboardRecentLimit"

    static let transactionShowIcon = "NLDevTransactionShowIcon"
    static let transactionShowDate = "NLDevTransactionShowDate"
    static let transactionShowSecondary = "NLDevTransactionShowSecondary"
    static let transactionShowRunningBalance = "NLDevTransactionShowRunningBalance"
    static let transactionShowTransferSecondary = "NLDevTransactionShowTransferSecondary"
    static let transactionCompactRows = "NLDevTransactionCompactRows"

    static let all: [String] = [
        enabled,
        density, cardDepth, cardCornerRadius, cardShadowOpacity, cardShadowRadius,
        cardBorderWidth, reportBlockSpacing, reportPagePadding,
        chartType, chartDepth, chartHeight, chartCornerRadius, chartSideBySide,
        chartShowLegend, chartShowIncome, chartShowExpense, chartShowXAxis,
        chartShowYAxis, chartShowGrid, chartShowPoints, chartShowValues,
        showReportPeriodPicker, showReportPeriodNavigator, showReportActivityChart,
        showReportCategoryBreakdown, showReportTransactionList, showReportDownload,
        showReportFooterTotal, showReportTransactionCount, reportTransactionOrder,
        reportCategoryLimit, showCategoryProgress, showReportsRegisters,
        showReportsPlanning, showReportsCore, showReportsStatements,
        showSummaryNetBalance, showSummaryRateNote, showSummaryConnectors,
        showSummaryIncomeColumn, showSummaryExpenseColumn, showSummaryPrimaryCards,
        showSummaryRefunds, showSummaryLoans, showSummaryOperators,
        showSummaryOpeningBalance, showSummaryCustomBalanceCards,
        showSummaryPKRConversion, summaryCompactCards, summaryLoanSort,
        dashboardShowHeader, dashboardShowSpending, dashboardShowDateFilter,
        dashboardShowBalance, dashboardShowQuickActions, dashboardShowRecent,
        dashboardColumns, dashboardHorizontalPadding, dashboardSectionSpacing,
        dashboardRecentLimit, transactionShowIcon, transactionShowDate,
        transactionShowSecondary, transactionShowRunningBalance,
        transactionShowTransferSecondary, transactionCompactRows
    ]
}

enum DeveloperDensity: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case standard = "Standard"
    case spacious = "Spacious"
    var id: String { rawValue }
}

enum DeveloperDepthStyle: String, CaseIterable, Identifiable {
    case flat2D = "2D / Flat"
    case soft3D = "Soft 3D"
    case deep3D = "Deep 3D"
    var id: String { rawValue }
}

enum DeveloperChartType: String, CaseIterable, Identifiable {
    case bar = "Bar"
    case line = "Line"
    case area = "Area"
    var id: String { rawValue }
}

enum DeveloperTransactionOrder: String, CaseIterable, Identifiable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    var id: String { rawValue }
}

enum DeveloperLoanSort: String, CaseIterable, Identifiable {
    case alphabetical = "Currency A–Z"
    case qarFirst = "QAR First"
    case largestFirst = "Largest First"
    var id: String { rawValue }
}

enum DeveloperLabPreset: String, CaseIterable, Identifiable {
    case defaultLook = "Default / Safe"
    case compact2D = "Compact 2D"
    case soft3D = "Soft 3D"
    case deep3D = "Deep 3D"
    case reportMinimal = "Report Minimal"
    case dashboardFocus = "Dashboard Focus"
    var id: String { rawValue }
}

enum DeveloperLabStore {
    static func exportJSON() -> String {
        let defaults = UserDefaults.standard
        var values: [String: Any] = [:]
        for key in DeveloperLabKey.all {
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        guard JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    static func importJSON(_ string: String) -> Bool {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let values = object as? [String: Any] else { return false }
        let allowed = Set(DeveloperLabKey.all)
        var imported = false
        for (key, value) in values where allowed.contains(key) {
            UserDefaults.standard.set(value, forKey: key)
            imported = true
        }
        return imported
    }

    static func resetAll() {
        for key in DeveloperLabKey.all {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func apply(_ preset: DeveloperLabPreset) {
        resetAll()
        let d = UserDefaults.standard
        d.set(true, forKey: DeveloperLabKey.enabled)
        switch preset {
        case .defaultLook:
            break
        case .compact2D:
            d.set(DeveloperDensity.compact.rawValue, forKey: DeveloperLabKey.density)
            d.set(DeveloperDepthStyle.flat2D.rawValue, forKey: DeveloperLabKey.cardDepth)
            d.set(14.0, forKey: DeveloperLabKey.cardCornerRadius)
            d.set(10.0, forKey: DeveloperLabKey.reportBlockSpacing)
            d.set(10.0, forKey: DeveloperLabKey.reportPagePadding)
            d.set(true, forKey: DeveloperLabKey.summaryCompactCards)
            d.set(true, forKey: DeveloperLabKey.transactionCompactRows)
            d.set(10.0, forKey: DeveloperLabKey.dashboardSectionSpacing)
            d.set(12.0, forKey: DeveloperLabKey.dashboardHorizontalPadding)
        case .soft3D:
            d.set(DeveloperDepthStyle.soft3D.rawValue, forKey: DeveloperLabKey.cardDepth)
            d.set(0.16, forKey: DeveloperLabKey.cardShadowOpacity)
            d.set(10.0, forKey: DeveloperLabKey.cardShadowRadius)
            d.set(DeveloperDepthStyle.soft3D.rawValue, forKey: DeveloperLabKey.chartDepth)
        case .deep3D:
            d.set(DeveloperDepthStyle.deep3D.rawValue, forKey: DeveloperLabKey.cardDepth)
            d.set(0.24, forKey: DeveloperLabKey.cardShadowOpacity)
            d.set(16.0, forKey: DeveloperLabKey.cardShadowRadius)
            d.set(1.2, forKey: DeveloperLabKey.cardBorderWidth)
            d.set(DeveloperDepthStyle.deep3D.rawValue, forKey: DeveloperLabKey.chartDepth)
        case .reportMinimal:
            d.set(false, forKey: DeveloperLabKey.showSummaryRateNote)
            d.set(false, forKey: DeveloperLabKey.showSummaryConnectors)
            d.set(false, forKey: DeveloperLabKey.showSummaryOperators)
            d.set(false, forKey: DeveloperLabKey.showCategoryProgress)
            d.set(false, forKey: DeveloperLabKey.showReportTransactionCount)
            d.set(true, forKey: DeveloperLabKey.summaryCompactCards)
        case .dashboardFocus:
            d.set(false, forKey: DeveloperLabKey.dashboardShowHeader)
            d.set(false, forKey: DeveloperLabKey.dashboardShowDateFilter)
            d.set(true, forKey: DeveloperLabKey.dashboardShowBalance)
            d.set(true, forKey: DeveloperLabKey.dashboardShowQuickActions)
            d.set(true, forKey: DeveloperLabKey.dashboardShowRecent)
            d.set(8, forKey: DeveloperLabKey.dashboardRecentLimit)
        }
    }
}

struct DeveloperSurfaceModifier: ViewModifier {
    @AppStorage(DeveloperLabKey.enabled) private var enabled = true
    @AppStorage(DeveloperLabKey.cardDepth) private var depth = DeveloperDepthStyle.flat2D.rawValue
    @AppStorage(DeveloperLabKey.cardShadowOpacity) private var shadowOpacity = 0.12
    @AppStorage(DeveloperLabKey.cardShadowRadius) private var shadowRadius = 8.0
    @AppStorage(DeveloperLabKey.cardBorderWidth) private var borderWidth = 0.0
    @AppStorage(DeveloperLabKey.cardCornerRadius) private var cornerRadius = 20.0

    func body(content: Content) -> some View {
        let style = DeveloperDepthStyle(rawValue: depth) ?? .flat2D
        let angle: Double = enabled ? (style == .soft3D ? 1.6 : (style == .deep3D ? 3.5 : 0)) : 0
        let x: CGFloat = enabled ? (style == .deep3D ? 5 : (style == .soft3D ? 2 : 0)) : 0
        let y: CGFloat = enabled ? (style == .deep3D ? 8 : (style == .soft3D ? 4 : 0)) : 0
        let effectiveShadow = enabled && style != .flat2D ? shadowOpacity : 0
        content
            .overlay {
                if enabled && borderWidth > 0 {
                    RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
                        .stroke(.primary.opacity(0.12), lineWidth: CGFloat(borderWidth))
                }
            }
            .shadow(
                color: .black.opacity(effectiveShadow),
                radius: enabled && style != .flat2D ? CGFloat(shadowRadius) : 0,
                x: x,
                y: y
            )
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 1, y: -0.35, z: 0),
                perspective: enabled && style != .flat2D ? 0.55 : 0
            )
    }
}

extension View {
    func developerSurface() -> some View {
        modifier(DeveloperSurfaceModifier())
    }
}

struct DeveloperChartPoint: Identifiable {
    let id: String
    let label: String
    let income: Double
    let expense: Double
}

private struct DeveloperChartLegend: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct DeveloperActivityChart: View {
    let points: [DeveloperChartPoint]

    @AppStorage(DeveloperLabKey.enabled) private var enabled = true
    @AppStorage(DeveloperLabKey.chartType) private var chartType = DeveloperChartType.bar.rawValue
    @AppStorage(DeveloperLabKey.chartDepth) private var chartDepth = DeveloperDepthStyle.flat2D.rawValue
    @AppStorage(DeveloperLabKey.chartHeight) private var chartHeight = 230.0
    @AppStorage(DeveloperLabKey.chartCornerRadius) private var barCornerRadius = 3.0
    @AppStorage(DeveloperLabKey.chartSideBySide) private var sideBySide = true
    @AppStorage(DeveloperLabKey.chartShowLegend) private var showLegend = true
    @AppStorage(DeveloperLabKey.chartShowIncome) private var showIncome = true
    @AppStorage(DeveloperLabKey.chartShowExpense) private var showExpense = true
    @AppStorage(DeveloperLabKey.chartShowXAxis) private var showXAxis = true
    @AppStorage(DeveloperLabKey.chartShowYAxis) private var showYAxis = true
    @AppStorage(DeveloperLabKey.chartShowGrid) private var showGrid = true
    @AppStorage(DeveloperLabKey.chartShowPoints) private var showPoints = false
    @AppStorage(DeveloperLabKey.chartShowValues) private var showValues = false

    private var effectiveType: DeveloperChartType {
        enabled ? (DeveloperChartType(rawValue: chartType) ?? .bar) : .bar
    }

    private var effectiveDepth: DeveloperDepthStyle {
        enabled ? (DeveloperDepthStyle(rawValue: chartDepth) ?? .flat2D) : .flat2D
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if (!enabled || showLegend) {
                HStack(spacing: 12) {
                    if !enabled || showIncome { DeveloperChartLegend(color: AppTheme.green, title: "Income") }
                    if !enabled || showExpense { DeveloperChartLegend(color: AppTheme.red, title: "Expense") }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Chart(points) { point in
                if !enabled || showIncome {
                    incomeMarks(point)
                }
                if !enabled || showExpense {
                    expenseMarks(point)
                }
            }
            .chartLegend(.hidden)
            .chartXAxis {
                if !enabled || showXAxis {
                    AxisMarks { _ in
                        if !enabled || showGrid { AxisGridLine() }
                        AxisTick()
                        AxisValueLabel()
                    }
                }
            }
            .chartYAxis {
                if !enabled || showYAxis {
                    AxisMarks(position: .leading) { _ in
                        if !enabled || showGrid { AxisGridLine() }
                        AxisTick()
                        AxisValueLabel()
                    }
                }
            }
            .frame(height: enabled ? CGFloat(chartHeight) : 230)
            .rotation3DEffect(
                .degrees(effectiveDepth == .soft3D ? 2.2 : (effectiveDepth == .deep3D ? 4.8 : 0)),
                axis: (x: 1, y: -0.15, z: 0),
                perspective: effectiveDepth == .flat2D ? 0 : 0.55
            )
            .shadow(
                color: .black.opacity(effectiveDepth == .flat2D ? 0 : (effectiveDepth == .soft3D ? 0.12 : 0.20)),
                radius: effectiveDepth == .flat2D ? 0 : (effectiveDepth == .soft3D ? 6 : 12),
                x: effectiveDepth == .deep3D ? 4 : 0,
                y: effectiveDepth == .flat2D ? 0 : (effectiveDepth == .soft3D ? 4 : 8)
            )
        }
    }

    @ChartContentBuilder
    private func incomeMarks(_ point: DeveloperChartPoint) -> some ChartContent {
        switch effectiveType {
        case .bar:
            if enabled && sideBySide {
                BarMark(
                    x: .value("Period", point.label),
                    y: .value("Income", point.income)
                )
                .foregroundStyle(AppTheme.green.gradient)
                .position(by: .value("Type", "Income"))
                .cornerRadius(CGFloat(enabled ? barCornerRadius : 3))
                .annotation(position: .top) {
                    if enabled && showValues && point.income != 0 {
                        Text(String(format: "%.0f", point.income)).font(.caption2)
                    }
                }
            } else {
                BarMark(
                    x: .value("Period", point.label),
                    y: .value("Income", point.income)
                )
                .foregroundStyle(AppTheme.green.gradient)
                .cornerRadius(CGFloat(enabled ? barCornerRadius : 3))
                .annotation(position: .top) {
                    if enabled && showValues && point.income != 0 {
                        Text(String(format: "%.0f", point.income)).font(.caption2)
                    }
                }
            }
        case .line:
            LineMark(
                x: .value("Period", point.label),
                y: .value("Income", point.income)
            )
            .foregroundStyle(AppTheme.green)
            .interpolationMethod(.catmullRom)
            if enabled && showPoints {
                PointMark(
                    x: .value("Period", point.label),
                    y: .value("Income", point.income)
                )
                .foregroundStyle(AppTheme.green)
            }
        case .area:
            AreaMark(
                x: .value("Period", point.label),
                y: .value("Income", point.income)
            )
            .foregroundStyle(AppTheme.green.opacity(0.24))
            .interpolationMethod(.catmullRom)
            LineMark(
                x: .value("Period", point.label),
                y: .value("Income", point.income)
            )
            .foregroundStyle(AppTheme.green)
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder
    private func expenseMarks(_ point: DeveloperChartPoint) -> some ChartContent {
        switch effectiveType {
        case .bar:
            if enabled && sideBySide {
                BarMark(
                    x: .value("Period", point.label),
                    y: .value("Expense", point.expense)
                )
                .foregroundStyle(AppTheme.red.gradient)
                .position(by: .value("Type", "Expense"))
                .cornerRadius(CGFloat(enabled ? barCornerRadius : 3))
                .annotation(position: .top) {
                    if enabled && showValues && point.expense != 0 {
                        Text(String(format: "%.0f", point.expense)).font(.caption2)
                    }
                }
            } else {
                BarMark(
                    x: .value("Period", point.label),
                    y: .value("Expense", point.expense)
                )
                .foregroundStyle(AppTheme.red.gradient)
                .cornerRadius(CGFloat(enabled ? barCornerRadius : 3))
                .annotation(position: .top) {
                    if enabled && showValues && point.expense != 0 {
                        Text(String(format: "%.0f", point.expense)).font(.caption2)
                    }
                }
            }
        case .line:
            LineMark(
                x: .value("Period", point.label),
                y: .value("Expense", point.expense)
            )
            .foregroundStyle(AppTheme.red)
            .interpolationMethod(.catmullRom)
            if enabled && showPoints {
                PointMark(
                    x: .value("Period", point.label),
                    y: .value("Expense", point.expense)
                )
                .foregroundStyle(AppTheme.red)
            }
        case .area:
            AreaMark(
                x: .value("Period", point.label),
                y: .value("Expense", point.expense)
            )
            .foregroundStyle(AppTheme.red.opacity(0.20))
            .interpolationMethod(.catmullRom)
            LineMark(
                x: .value("Period", point.label),
                y: .value("Expense", point.expense)
            )
            .foregroundStyle(AppTheme.red)
            .interpolationMethod(.catmullRom)
        }
    }
}

struct DeveloperLabView: View {
    @AppStorage(DeveloperLabKey.enabled) private var enabled = true
    @State private var notice = ""
    @State private var showingNotice = false

    var body: some View {
        List {
            Section {
                Toggle("Enable Developer Overrides", isOn: $enabled)
                Label(
                    enabled ? "Overrides are live" : "Safe mode: normal app behavior",
                    systemImage: enabled ? "hammer.fill" : "shield.fill"
                )
                .foregroundStyle(enabled ? AppTheme.orange : AppTheme.green)
            } header: {
                Text("Master Control")
            } footer: {
                Text("Turning this off does not erase your choices. It temporarily restores the normal Next Ledger layout and visuals.")
            }

            Section("Customization") {
                NavigationLink { DeveloperAppearanceSettingsView() } label: {
                    Label("UI / 2D / 3D / Cards", systemImage: "cube.transparent.fill")
                }
                NavigationLink { DeveloperChartSettingsView() } label: {
                    Label("Charts & Graphs", systemImage: "chart.xyaxis.line")
                }
                NavigationLink { DeveloperFinancialSummarySettingsView() } label: {
                    Label("Financial Summary", systemImage: "rectangle.3.group.fill")
                }
                NavigationLink { DeveloperReportSettingsView() } label: {
                    Label("Reports & Tables", systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink { DeveloperDashboardSettingsView() } label: {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
                NavigationLink { DeveloperTransactionSettingsView() } label: {
                    Label("Transaction Rows", systemImage: "list.bullet.rectangle")
                }
            }

            Section("Presets") {
                ForEach(DeveloperLabPreset.allCases) { preset in
                    Button {
                        DeveloperLabStore.apply(preset)
                        notice = "Applied preset: \(preset.rawValue)"
                        showingNotice = true
                    } label: {
                        HStack {
                            Text(preset.rawValue)
                            Spacer()
                            Image(systemName: "wand.and.stars")
                        }
                    }
                }
            }

            Section("Developer Tools") {
                Button {
                    UIPasteboard.general.string = DeveloperLabStore.exportJSON()
                    notice = "Developer settings JSON copied to clipboard."
                    showingNotice = true
                } label: {
                    Label("Copy Settings JSON", systemImage: "doc.on.doc.fill")
                }

                Button {
                    let value = UIPasteboard.general.string ?? ""
                    let success = DeveloperLabStore.importJSON(value)
                    notice = success ? "Settings imported from clipboard." : "Clipboard does not contain valid Developer Lab JSON."
                    showingNotice = true
                } label: {
                    Label("Import Settings JSON from Clipboard", systemImage: "doc.on.clipboard.fill")
                }

                Button(role: .destructive) {
                    DeveloperLabStore.resetAll()
                    notice = "Developer settings reset to defaults."
                    showingNotice = true
                } label: {
                    Label("Reset All Developer Settings", systemImage: "arrow.counterclockwise.circle.fill")
                }
            }
        }
        .navigationTitle("Developer Lab")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Developer Lab", isPresented: $showingNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(notice)
        }
    }
}

private struct DeveloperAppearanceSettingsView: View {
    @AppStorage(DeveloperLabKey.density) private var density = DeveloperDensity.standard.rawValue
    @AppStorage(DeveloperLabKey.cardDepth) private var cardDepth = DeveloperDepthStyle.flat2D.rawValue
    @AppStorage(DeveloperLabKey.cardCornerRadius) private var cardCornerRadius = 20.0
    @AppStorage(DeveloperLabKey.cardShadowOpacity) private var cardShadowOpacity = 0.12
    @AppStorage(DeveloperLabKey.cardShadowRadius) private var cardShadowRadius = 8.0
    @AppStorage(DeveloperLabKey.cardBorderWidth) private var cardBorderWidth = 0.0
    @AppStorage(DeveloperLabKey.reportBlockSpacing) private var reportBlockSpacing = 18.0
    @AppStorage(DeveloperLabKey.reportPagePadding) private var reportPagePadding = 16.0

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Density", selection: $density) {
                    ForEach(DeveloperDensity.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Stepper("Report block spacing: \(Int(reportBlockSpacing))", value: $reportBlockSpacing, in: 4...36, step: 2)
                Stepper("Report page padding: \(Int(reportPagePadding))", value: $reportPagePadding, in: 0...32, step: 2)
            }
            Section("Card Geometry") {
                Picker("Depth", selection: $cardDepth) {
                    ForEach(DeveloperDepthStyle.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Stepper("Corner radius: \(Int(cardCornerRadius))", value: $cardCornerRadius, in: 0...40, step: 2)
                VStack(alignment: .leading) {
                    Text("Shadow opacity · \(Int(cardShadowOpacity * 100))%")
                    Slider(value: $cardShadowOpacity, in: 0...0.35, step: 0.01)
                }
                Stepper("Shadow radius: \(Int(cardShadowRadius))", value: $cardShadowRadius, in: 0...24, step: 1)
                VStack(alignment: .leading) {
                    Text("Border width · \(cardBorderWidth, specifier: "%.1f")")
                    Slider(value: $cardBorderWidth, in: 0...3, step: 0.1)
                }
            }
            Section("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Live Card Preview", systemImage: "cube.fill")
                        .font(.headline)
                    Text("Use 2D for maximum clarity, Soft 3D for subtle depth, or Deep 3D for a more dimensional developer-style interface.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: CGFloat(cardCornerRadius), style: .continuous))
                .developerSurface()
            }
        }
        .navigationTitle("UI / 2D / 3D")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeveloperChartSettingsView: View {
    @AppStorage(DeveloperLabKey.chartType) private var chartType = DeveloperChartType.bar.rawValue
    @AppStorage(DeveloperLabKey.chartDepth) private var chartDepth = DeveloperDepthStyle.flat2D.rawValue
    @AppStorage(DeveloperLabKey.chartHeight) private var chartHeight = 230.0
    @AppStorage(DeveloperLabKey.chartCornerRadius) private var chartCornerRadius = 3.0
    @AppStorage(DeveloperLabKey.chartSideBySide) private var sideBySide = true
    @AppStorage(DeveloperLabKey.chartShowLegend) private var showLegend = true
    @AppStorage(DeveloperLabKey.chartShowIncome) private var showIncome = true
    @AppStorage(DeveloperLabKey.chartShowExpense) private var showExpense = true
    @AppStorage(DeveloperLabKey.chartShowXAxis) private var showXAxis = true
    @AppStorage(DeveloperLabKey.chartShowYAxis) private var showYAxis = true
    @AppStorage(DeveloperLabKey.chartShowGrid) private var showGrid = true
    @AppStorage(DeveloperLabKey.chartShowPoints) private var showPoints = false
    @AppStorage(DeveloperLabKey.chartShowValues) private var showValues = false

    private let preview = [
        DeveloperChartPoint(id: "1", label: "1", income: 2200, expense: 1400),
        DeveloperChartPoint(id: "2", label: "2", income: 3200, expense: 2400),
        DeveloperChartPoint(id: "3", label: "3", income: 1800, expense: 900),
        DeveloperChartPoint(id: "4", label: "4", income: 4100, expense: 2800)
    ]

    var body: some View {
        Form {
            Section("Chart Type") {
                Picker("Style", selection: $chartType) {
                    ForEach(DeveloperChartType.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("Depth", selection: $chartDepth) {
                    ForEach(DeveloperDepthStyle.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Stepper("Height: \(Int(chartHeight)) pt", value: $chartHeight, in: 140...420, step: 10)
                if chartType == DeveloperChartType.bar.rawValue {
                    Toggle("Side-by-side income / expense bars", isOn: $sideBySide)
                    Stepper("Bar corner radius: \(Int(chartCornerRadius))", value: $chartCornerRadius, in: 0...16, step: 1)
                }
            }
            Section("Series") {
                Toggle("Show Income", isOn: $showIncome)
                Toggle("Show Expense", isOn: $showExpense)
                Toggle("Show Legend", isOn: $showLegend)
                Toggle("Show Point Markers", isOn: $showPoints)
                Toggle("Show Value Labels", isOn: $showValues)
            }
            Section("Axes") {
                Toggle("Show X Axis", isOn: $showXAxis)
                Toggle("Show Y Axis", isOn: $showYAxis)
                Toggle("Show Grid Lines", isOn: $showGrid)
            }
            Section("Live Preview") {
                DeveloperActivityChart(points: preview)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle("Charts & Graphs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeveloperFinancialSummarySettingsView: View {
    @AppStorage(DeveloperLabKey.showSummaryNetBalance) private var showNet = true
    @AppStorage(DeveloperLabKey.showSummaryRateNote) private var showRate = true
    @AppStorage(DeveloperLabKey.showSummaryConnectors) private var showConnectors = true
    @AppStorage(DeveloperLabKey.showSummaryIncomeColumn) private var showIncome = true
    @AppStorage(DeveloperLabKey.showSummaryExpenseColumn) private var showExpense = true
    @AppStorage(DeveloperLabKey.showSummaryPrimaryCards) private var showPrimary = true
    @AppStorage(DeveloperLabKey.showSummaryRefunds) private var showRefunds = true
    @AppStorage(DeveloperLabKey.showSummaryLoans) private var showLoans = true
    @AppStorage(DeveloperLabKey.showSummaryOperators) private var showOperators = true
    @AppStorage(DeveloperLabKey.showSummaryOpeningBalance) private var showOpening = true
    @AppStorage(DeveloperLabKey.showSummaryCustomBalanceCards) private var showCustom = true
    @AppStorage(DeveloperLabKey.showSummaryPKRConversion) private var showPKR = true
    @AppStorage(DeveloperLabKey.summaryCompactCards) private var compactCards = true
    @AppStorage(DeveloperLabKey.summaryLoanSort) private var loanSort = DeveloperLoanSort.alphabetical.rawValue

    var body: some View {
        Form {
            Section("Main Summary") {
                Toggle("Show Net Balance", isOn: $showNet)
                Toggle("Show Fixed-Rate Note", isOn: $showRate)
                Toggle("Show Connector Lines", isOn: $showConnectors)
                Toggle("Show Formula Operators (= / +)", isOn: $showOperators)
                Toggle("Compact Flow Cards", isOn: $compactCards)
            }
            Section("Money Flow Columns") {
                Toggle("Show Income Column", isOn: $showIncome)
                Toggle("Show Money Out Column", isOn: $showExpense)
                Toggle("Show Direct Income / Expense Cards", isOn: $showPrimary)
                Toggle("Show Refunds", isOn: $showRefunds)
                Toggle("Show Loan Movement Cards", isOn: $showLoans)
                Toggle("Show PKR → QAR Secondary Value", isOn: $showPKR)
                Picker("Loan Currency Sort", selection: $loanSort) {
                    ForEach(DeveloperLoanSort.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
            }
            Section("Balance Cards") {
                Toggle("Show Opening Balance Section", isOn: $showOpening)
                Toggle("Show Custom Balance Cards", isOn: $showCustom)
            }
        }
        .navigationTitle("Financial Summary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeveloperReportSettingsView: View {
    @AppStorage(DeveloperLabKey.showReportPeriodPicker) private var showPeriodPicker = true
    @AppStorage(DeveloperLabKey.showReportPeriodNavigator) private var showPeriodNavigator = true
    @AppStorage(DeveloperLabKey.showReportActivityChart) private var showChart = true
    @AppStorage(DeveloperLabKey.showReportCategoryBreakdown) private var showCategories = true
    @AppStorage(DeveloperLabKey.showReportTransactionList) private var showTransactions = true
    @AppStorage(DeveloperLabKey.showReportDownload) private var showDownload = true
    @AppStorage(DeveloperLabKey.showReportFooterTotal) private var showFooter = true
    @AppStorage(DeveloperLabKey.showReportTransactionCount) private var showCount = true
    @AppStorage(DeveloperLabKey.reportTransactionOrder) private var transactionOrder = DeveloperTransactionOrder.newest.rawValue
    @AppStorage(DeveloperLabKey.reportCategoryLimit) private var categoryLimit = 20
    @AppStorage(DeveloperLabKey.showCategoryProgress) private var showProgress = true
    @AppStorage(DeveloperLabKey.showReportsRegisters) private var showRegisters = true
    @AppStorage(DeveloperLabKey.showReportsPlanning) private var showPlanning = true
    @AppStorage(DeveloperLabKey.showReportsCore) private var showCore = true
    @AppStorage(DeveloperLabKey.showReportsStatements) private var showStatements = true

    var body: some View {
        Form {
            Section("Report Detail Screen") {
                Toggle("Show Period Selector", isOn: $showPeriodPicker)
                Toggle("Show Period Navigator", isOn: $showPeriodNavigator)
                Toggle("Show Activity Chart", isOn: $showChart)
                Toggle("Show Category Breakdown", isOn: $showCategories)
                Toggle("Show Transaction List", isOn: $showTransactions)
                Toggle("Show Download Button", isOn: $showDownload)
                Toggle("Show Footer Total", isOn: $showFooter)
                Toggle("Show Transaction Count", isOn: $showCount)
                Picker("Transaction Order", selection: $transactionOrder) {
                    ForEach(DeveloperTransactionOrder.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Stepper("Maximum category rows: \(categoryLimit)", value: $categoryLimit, in: 1...50)
                Toggle("Show Category Progress Bars", isOn: $showProgress)
            }
            Section("Reports Home") {
                Toggle("Accounting Registers", isOn: $showRegisters)
                Toggle("Planning & Comparison", isOn: $showPlanning)
                Toggle("Core Reports", isOn: $showCore)
                Toggle("Statements & Aging", isOn: $showStatements)
            }
        }
        .navigationTitle("Reports & Tables")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeveloperDashboardSettingsView: View {
    @AppStorage(DeveloperLabKey.dashboardShowHeader) private var showHeader = true
    @AppStorage(DeveloperLabKey.dashboardShowSpending) private var showSpending = true
    @AppStorage(DeveloperLabKey.dashboardShowDateFilter) private var showDateFilter = true
    @AppStorage(DeveloperLabKey.dashboardShowBalance) private var showBalance = true
    @AppStorage(DeveloperLabKey.dashboardShowQuickActions) private var showQuickActions = true
    @AppStorage(DeveloperLabKey.dashboardShowRecent) private var showRecent = true
    @AppStorage(DeveloperLabKey.dashboardColumns) private var columns = 2
    @AppStorage(DeveloperLabKey.dashboardHorizontalPadding) private var horizontalPadding = 18.0
    @AppStorage(DeveloperLabKey.dashboardSectionSpacing) private var sectionSpacing = 22.0
    @AppStorage(DeveloperLabKey.dashboardRecentLimit) private var recentLimit = 6

    var body: some View {
        Form {
            Section("Sections") {
                Toggle("Header / Logo", isOn: $showHeader)
                Toggle("Spending Shortcuts", isOn: $showSpending)
                Toggle("Date Filter", isOn: $showDateFilter)
                Toggle("Balance Card", isOn: $showBalance)
                Toggle("Quick Add Buttons", isOn: $showQuickActions)
                Toggle("Recent Transactions", isOn: $showRecent)
            }
            Section("Layout") {
                Stepper("Spending grid columns: \(columns)", value: $columns, in: 1...3)
                Stepper("Horizontal padding: \(Int(horizontalPadding))", value: $horizontalPadding, in: 0...32, step: 2)
                Stepper("Section spacing: \(Int(sectionSpacing))", value: $sectionSpacing, in: 4...40, step: 2)
                Stepper("Recent transactions: \(recentLimit)", value: $recentLimit, in: 1...20)
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeveloperTransactionSettingsView: View {
    @AppStorage(DeveloperLabKey.transactionShowIcon) private var showIcon = true
    @AppStorage(DeveloperLabKey.transactionShowDate) private var showDate = true
    @AppStorage(DeveloperLabKey.transactionShowSecondary) private var showSecondary = true
    @AppStorage(DeveloperLabKey.transactionShowRunningBalance) private var showRunningBalance = true
    @AppStorage(DeveloperLabKey.transactionShowTransferSecondary) private var showTransferSecondary = true
    @AppStorage(DeveloperLabKey.transactionCompactRows) private var compactRows = false

    var body: some View {
        Form {
            Section("Transaction Row Content") {
                Toggle("Category / Type Icon", isOn: $showIcon)
                Toggle("Date & Time", isOn: $showDate)
                Toggle("Secondary Description", isOn: $showSecondary)
                Toggle("Running Balance", isOn: $showRunningBalance)
                Toggle("Transfer Destination Amount", isOn: $showTransferSecondary)
                Toggle("Compact Row Spacing", isOn: $compactRows)
            }
        }
        .navigationTitle("Transaction Rows")
        .navigationBarTitleDisplayMode(.inline)
    }
}
