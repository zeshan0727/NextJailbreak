import SwiftUI
import QuickLook

// Mobile Manager Reporting is a read-only presentation of the latest imported PC snapshot.
// It NEVER silently substitutes inferred TB classifications for desktop report formulas.
// Exact export is supported by sharing an unchanged desktop-generated file from the backup.
private enum FinancialArea: String, CaseIterable {
    case income = "Income Statement"
    case balance = "Balance Sheet"
}

private struct FinancialBucket: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let rows: [TBRow]
}

struct ManagerReportingMobileView: View {
    @EnvironmentObject private var store: MobileStore
    @State private var selectedArea: FinancialArea = .income
    @State private var expanded: Set<String> = []
    @State private var filter = ""
    @State private var showOriginalFiles = false

    private var currency: String { store.selectedEntity?.currency ?? "QAR" }

    private var sourceRows: [TBRow] {
        store.tbRows.filter {
            filter.isEmpty || "\($0.code) \($0.name) \($0.type)".localizedCaseInsensitiveContains(filter)
        }
    }

    // Conservative classification; unfamiliar mappings remain in the unclassified bucket.
    // These rows are *ledger drill-downs*, NOT a reconstructed desktop statement.
    private var buckets: [FinancialBucket] {
        let groups: [(String, String, String, (String) -> Bool)]
        if selectedArea == .income {
            groups = [
                ("Revenue", "Revenue and other income", "arrow.up.forward.circle.fill", { $0.contains("revenue") || $0.contains("income") || $0 == "sales" }),
                ("Direct costs", "Direct costs", "shippingbox.fill", { $0.contains("cost of sales") || $0.contains("cost of goods") || $0.contains("direct cost") || $0 == "cogs" }),
                ("Expenses", "Operating and other expenses", "arrow.down.forward.circle.fill", { $0.contains("expense") || $0.contains("overhead") })
            ]
        } else {
            groups = [
                ("Assets", "Assets", "square.stack.3d.up.fill", { $0.contains("asset") }),
                ("Liabilities", "Liabilities", "arrow.down.left.circle.fill", { $0.contains("liabilit") }),
                ("Equity", "Equity", "building.columns.fill", { $0.contains("equity") || $0.contains("capital") || $0.contains("retained earnings") })
            ]
        }
        return groups.map { group in
            FinancialBucket(id: group.0, name: group.1, symbol: group.2,
                            rows: sourceRows.filter { group.3($0.type.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) })
        }
    }

    private var unclassified: [TBRow] {
        let allCodes = Set(buckets.flatMap(\.rows).map(\.code))
        return sourceRows.filter { !allCodes.contains($0.code) }
    }

    private var originalReportFiles: [FileRow] {
        store.files.filter { f in
            let e = f.url.pathExtension.lowercased()
            guard ["xlsx", "xlsm", "xls", "pdf"].contains(e) else { return false }
            let p = f.relative.lowercased()
            return p.contains("manager") || p.contains("income statement")
                || p.contains("balance sheet") || p.contains("financial report")
                || p.contains("profit and loss") || p.contains("profit_loss")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MobileModuleHeader(title: "Manager Reporting", subtitle: "Xero-driven Windows snapshot • mobile view")
                    MobileCompanyPicker()
                    periodPicker
                    Picker("Statement", selection: $selectedArea) {
                        Text("Income Statement").tag(FinancialArea.income)
                        Text("Balance Sheet").tag(FinancialArea.balance)
                    }
                    .pickerStyle(.segmented)

                    provenanceCard

                    if store.currentDatabaseURL == nil {
                        MobileEmpty(title: "Restore a PC snapshot", detail: "Import the current AccountantsNext full backup to view manager account data and original exports.", symbol: "externaldrive.badge.plus")
                    } else if store.latestTBDate.isEmpty {
                        MobileEmpty(title: "No Manager Reporting TB", detail: "The imported backup has no compatible active Manager Reporting snapshot for this company and reporting period.", symbol: "chart.bar.doc.horizontal")
                    } else {
                        snapshotCard
                        TextField("Find an account in the source TB", text: $filter)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        Text(selectedArea.rawValue)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                        Text("Account-level drill-down from the stored trial balance. Figures and classifications below are not the Windows report's formulas or layout.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(buckets) { bucket in
                            bucketCard(bucket)
                        }
                        if !unclassified.isEmpty {
                            bucketCard(FinancialBucket(id: "Other", name: "Unclassified / other TB accounts", symbol: "questionmark.square.dashed", rows: unclassified))
                        }
                    }
                    originalReportsSection
                }
                .padding(16)
            }
            .background(MobilePalette.canvas)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var periodPicker: some View {
        MobileCard {
            HStack {
                Label("Reporting period", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Desktop selection").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Picker("Month", selection: $store.selectedMonth) {
                    ForEach(1...12, id: \.self) { index in
                        Text(Calendar.current.monthSymbols[index - 1]).tag(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Picker("Year", selection: $store.selectedYear) {
                    ForEach(2024...2032, id: \.self) { year in Text(String(year)).tag(year) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .onChange(of: store.selectedMonth) { _ in Task { await store.refreshEntityData() } }
            .onChange(of: store.selectedYear) { _ in Task { await store.refreshEntityData() } }
        }
    }

    private var provenanceCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(MobilePalette.accent)
                .font(.title3)
            VStack(alignment: .leading, spacing: 5) {
                Text("Single source of truth").font(.subheadline.weight(.semibold))
                Text("Windows Manager Reporting is authoritative. Mobile displays a read-only TB drill-down. Export uses only original PC-generated files, unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(MobilePalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var snapshotCard: some View {
        MobileCard {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("IMPORTED SNAPSHOT").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                    Text(store.latestTBDate).font(.title2.bold()).monospacedDigit()
                    Text(store.periodTitle + " • " + (store.selectedEntity?.name ?? "Company"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 28)).foregroundStyle(MobilePalette.accent)
            }
            Divider()
            HStack {
                summaryMetric("TB accounts", value: "\(store.latestTBAccountCount)")
                Spacer()
                summaryMetric("Unmapped", value: "\(store.latestTBUnmapped)")
                Spacer()
                summaryMetric("Balance check", value: store.latestTBBalanced ? "Passed" : "Review")
            }
        }
    }

    private func summaryMetric(_ name: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func bucketCard(_ bucket: FinancialBucket) -> some View {
        MobileCard {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded.contains(bucket.id) },
                set: { isOpen in
                    if isOpen { expanded.insert(bucket.id) }
                    else { expanded.remove(bucket.id) }
                }
            )) {
                if bucket.rows.isEmpty {
                    Text("No mapped accounts in this category.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.vertical, 9)
                } else {
                    ForEach(bucket.rows) { row in
                        Divider().padding(.vertical, 3)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.name).font(.subheadline).lineLimit(3)
                                Spacer(minLength: 8)
                                Text(money(row.balance, currency))
                                    .font(.caption.monospacedDigit()).multilineTextAlignment(.trailing)
                            }
                            HStack {
                                Text(row.code).font(.caption2.monospaced())
                                Spacer()
                                Text(row.type).font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: bucket.symbol)
                        .foregroundStyle(MobilePalette.accent)
                        .frame(width: 32, height: 32)
                        .background(MobilePalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bucket.name).font(.subheadline.weight(.semibold))
                        Text("\(bucket.rows.count) account\(bucket.rows.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.primary)
        }
    }

    private var originalReportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Original Windows Reports").font(.title3.bold())
                Spacer()
                Text("\(originalReportFiles.count)").font(.subheadline).foregroundStyle(.secondary)
            }
            if originalReportFiles.isEmpty {
                MobileEmpty(title: "No PC report files found", detail: "The backup must include Windows-generated Excel or PDF reports. Mobile will not fabricate a replacement format. Export the report on PC and include its file in the next full backup.", symbol: "doc.badge.arrow.up")
            } else {
                Text("Select the correct company, period and report. These are the exact original files, not regenerated iPhone approximations.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(originalReportFiles.prefix(150)) { file in
                    OriginalDesktopFileRow(file: file)
                }
            }
        }
    }
}

struct OriginalDesktopFileRow: View {
    let file: FileRow
    @State private var preview = false
    var body: some View {
        MobileCard {
            HStack(spacing: 11) {
                Image(systemName: ["xlsx", "xlsm", "xls"].contains(file.url.pathExtension.lowercased()) ? "tablecells.fill" : "doc.richtext")
                    .font(.title3).foregroundStyle(MobilePalette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.url.lastPathComponent)
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(file.relative).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button { preview = true } label: { Label("Preview", systemImage: "eye") }
                    .buttonStyle(.bordered)
                Spacer()
                ShareLink(item: file.url, preview: SharePreview(file.url.lastPathComponent)) {
                    Label("Original file", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(MobilePalette.accent)
            }
            .font(.caption)
        }
        .sheet(isPresented: $preview) {
            QuickLookView(url: file.url).ignoresSafeArea()
        }
    }
}
