import SwiftUI
import UIKit

struct ProfessionalReportExportView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage("ProfessionalReportTypeV1") private var storedReportType = ProfessionalReportType.incomeStatement.rawValue
    @AppStorage("ProfessionalReportStartDateV1") private var storedStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    @AppStorage("ProfessionalReportEndDateV1") private var storedEndDate = Date().timeIntervalSince1970
    @State private var isGenerating = false
    @State private var shareFile: ReportShareFile?
    @State private var lastGeneratedURL: URL?
    @State private var lastGeneratedFormat: ProfessionalExportFormat?
    @State private var lastGeneratedDocument: ProfessionalReportDocument?
    @State private var errorMessage: String?

    private var selectedType: ProfessionalReportType {
        ProfessionalReportType(rawValue: storedReportType) ?? .incomeStatement
    }

    private var startDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedStartDate) },
            set: { newValue in
                storedStartDate = Calendar.current.startOfDay(for: newValue).timeIntervalSince1970
                if storedStartDate > storedEndDate { storedEndDate = storedStartDate }
            }
        )
    }

    private var endDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedEndDate) },
            set: { newValue in
                storedEndDate = Calendar.current.startOfDay(for: newValue).timeIntervalSince1970
                if storedEndDate < storedStartDate { storedStartDate = storedEndDate }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                reportSelectorCard
                dateCard
                exportCard
                if let lastGeneratedURL, let lastGeneratedFormat {
                    generatedFileCard(url: lastGeneratedURL, format: lastGeneratedFormat)
                    if let lastGeneratedDocument {
                        ReportSnapshotCard(
                            document: lastGeneratedDocument,
                            url: lastGeneratedURL,
                            format: lastGeneratedFormat
                        )
                    }
                }
                methodologyCard
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Export Reports")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareFile) { file in
            ReportActivityView(items: [file.url])
                .ignoresSafeArea()
        }
        .alert("Report Export", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The report could not be generated.")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.18))
                        .frame(width: 54, height: 54)
                    Image(systemName: "doc.badge.arrow.up.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("PDF + EXCEL")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            Text("Professional Report Center")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Create polished financial statements and aging reports, then share them to Mail, WhatsApp, Files, Drive or any supported app.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                heroFeature("Real XLSX", icon: "tablecells")
                heroFeature("Multi-page PDF", icon: "doc.richtext")
                heroFeature("Native Share", icon: "square.and.arrow.up")
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [AppTheme.purple, AppTheme.blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: AppTheme.purple.opacity(0.22), radius: 18, y: 9)
    }

    private func heroFeature(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.9))
    }

    private var reportSelectorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Report", icon: "doc.text.magnifyingglass")
            Menu {
                ForEach(ProfessionalReportType.allCases) { type in
                    Button {
                        storedReportType = type.rawValue
                    } label: {
                        Label(type.rawValue, systemImage: type.icon)
                    }
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: selectedType.icon)
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.purple.opacity(0.11), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedType.rawValue)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(selectedType.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            Text("The selected report and dates are remembered automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .reportCard()
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(selectedType.usesAsOfDateOnly ? "Report Date" : "Custom Period", icon: "calendar")
            if selectedType.usesAsOfDateOnly {
                DatePicker("As Of", selection: endDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                Text("Aging includes every open balance outstanding on this date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    dateField("From", binding: startDate)
                    dateField("To", binding: endDate)
                }
                HStack(spacing: 8) {
                    periodPreset("This Month", preset: .thisMonth)
                    periodPreset("Last Month", preset: .lastMonth)
                    periodPreset("This Year", preset: .thisYear)
                }
            }
        }
        .reportCard()
    }

    private func dateField(_ title: String, binding: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            DatePicker(title, selection: binding, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private enum PeriodPreset {
        case thisMonth, lastMonth, thisYear
    }

    private func periodPreset(_ title: String, preset: PeriodPreset) -> some View {
        Button {
            applyPreset(preset)
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(AppTheme.purple.opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.purple)
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Generate & Share", icon: "square.and.arrow.up")
            HStack(spacing: 12) {
                exportButton(format: .pdf, title: "Generate PDF", subtitle: "Designed document")
                exportButton(format: .excel, title: "Generate Excel", subtitle: "Real .xlsx workbook")
            }
            if isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Building \(selectedType.rawValue)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .reportCard()
    }

    private func exportButton(
        format: ProfessionalExportFormat,
        title: String,
        subtitle: String
    ) -> some View {
        Button {
            generate(format)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: format.icon)
                        .font(.title3.bold())
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.bold())
                }
                Text(title)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption2)
                    .opacity(0.82)
            }
            .foregroundStyle(.white)
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .background(
                format == .pdf
                    ? LinearGradient(colors: [AppTheme.red, AppTheme.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [AppTheme.green, AppTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
        .opacity(isGenerating ? 0.6 : 1)
    }

    private func generatedFileCard(
        url: URL,
        format: ProfessionalExportFormat
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Ready to Share", icon: "checkmark.seal.fill")
            HStack(spacing: 12) {
                Image(systemName: format.icon)
                    .font(.title2.bold())
                    .foregroundStyle(format == .pdf ? AppTheme.red : AppTheme.green)
                    .frame(width: 48, height: 48)
                    .background(
                        (format == .pdf ? AppTheme.red : AppTheme.green).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.lastPathComponent)
                        .font(.subheadline.bold())
                        .lineLimit(2)
                    Text(fileSizeText(url))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    shareFile = ReportShareFile(url: url)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.purple.opacity(0.11), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.purple)
            }
        }
        .reportCard()
    }

    private var methodologyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Report Method", icon: "info.circle.fill")
            if selectedType.usesAsOfDateOnly {
                methodRow("FIFO aging", detail: "Collections and payments settle the oldest open movements first.")
                methodRow("Four buckets", detail: "0–30, 31–60, 61–90 and 90+ days.")
                methodRow("Opening balances", detail: "Shown in 90+ because their original invoice date is unavailable.")
            } else if selectedType == .balanceSheet {
                methodRow("Custom movement", detail: "Opening balance, period movement and closing balance are shown together.")
                methodRow("Dynamic payments", detail: "Positive Payment balances are receivables; negative balances are payables.")
            } else {
                methodRow("Native currency", detail: "QAR, PKR, USD and other currencies remain in separate sections.")
                methodRow("Live ledger", detail: "The report is rebuilt from saved transactions each time you export.")
            }
        }
        .reportCard()
    }

    private func methodRow(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.green)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(AppTheme.purple)
    }

    private func applyPreset(_ preset: PeriodPreset) {
        let calendar = Calendar.current
        let now = Date()
        switch preset {
        case .thisMonth:
            let interval = calendar.dateInterval(of: .month, for: now)
            storedStartDate = (interval?.start ?? now).timeIntervalSince1970
            storedEndDate = calendar.startOfDay(for: now).timeIntervalSince1970
        case .lastMonth:
            let previous = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let interval = calendar.dateInterval(of: .month, for: previous)
            storedStartDate = (interval?.start ?? previous).timeIntervalSince1970
            let inclusiveEnd = interval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? previous
            storedEndDate = inclusiveEnd.timeIntervalSince1970
        case .thisYear:
            let interval = calendar.dateInterval(of: .year, for: now)
            storedStartDate = (interval?.start ?? now).timeIntervalSince1970
            storedEndDate = calendar.startOfDay(for: now).timeIntervalSince1970
        }
    }

    private func generate(_ format: ProfessionalExportFormat) {
        isGenerating = true
        defer { isGenerating = false }
        let document = ProfessionalReportBuilder.build(
            type: selectedType,
            startDate: startDate.wrappedValue,
            endDate: endDate.wrappedValue,
            store: store
        )
        do {
            let url = try ProfessionalReportExporter.export(document, format: format)
            lastGeneratedURL = url
            lastGeneratedFormat = format
            lastGeneratedDocument = document
        } catch {
            errorMessage = "The \(format.rawValue) report could not be generated. \(error.localizedDescription)"
        }
    }

    private func fileSizeText(_ url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return "Ready" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(size))) • Ready"
    }
}

private struct ReportShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ReportActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension View {
    func reportCard() -> some View {
        padding(16)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 1)
            )
    }
}
