import PDFKit
import SwiftUI
import UIKit

struct ReportSnapshotPayload: Identifiable {
    let id = UUID()
    let document: ProfessionalReportDocument
    let url: URL
    let format: ProfessionalExportFormat
}

struct ReportSnapshotCard: View {
    let document: ProfessionalReportDocument
    let url: URL
    let format: ProfessionalExportFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Report Snapshot", systemImage: "doc.text.image.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.purple)
                Spacer()
                Text(format.rawValue.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            if format == .pdf, let thumbnail = pdfThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18)))
            } else {
                documentSnapshot
            }

            Text(document.title)
                .font(.subheadline.bold())
            Text(document.periodText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var pdfThumbnail: UIImage? {
        guard let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) else { return nil }
        return page.thumbnail(of: CGSize(width: 760, height: 980), for: .mediaBox)
    }

    private var documentSnapshot: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(document.tables.prefix(2).enumerated()), id: \.offset) { _, table in
                VStack(alignment: .leading, spacing: 5) {
                    Text(table.title)
                        .font(.caption.bold())
                    ForEach(Array(table.rows.prefix(5).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(Array(row.cells.prefix(3).enumerated()), id: \.offset) { _, cell in
                                Text(snapshotText(cell))
                                    .font(.system(size: 10, design: .rounded))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(9)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func snapshotText(_ cell: ProfessionalReportCell) -> String {
        switch cell {
        case .text(let value): return value
        case .number(let value): return NSDecimalNumber(decimal: value).stringValue
        }
    }
}

struct ReportGeneratedSnapshotSheet: View {
    @Environment(\.dismiss) private var dismiss
    let payload: ReportSnapshotPayload
    @State private var shareFile: QuickReportShareFile?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ReportSnapshotCard(document: payload.document, url: payload.url, format: payload.format)
                    Button {
                        shareFile = QuickReportShareFile(url: payload.url)
                    } label: {
                        Label("Share / Save \(payload.format.rawValue)", systemImage: "square.and.arrow.up.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.purple)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Generated Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareFile) { file in
                QuickReportActivityView(items: [file.url])
                    .ignoresSafeArea()
            }
        }
    }
}

struct ReportDownloadButton: View {
    @EnvironmentObject private var store: LedgerStore

    let type: ProfessionalReportType
    let startDate: Date
    let endDate: Date
    let transactionIDs: [UUID]
    let accountIDs: [UUID]
    let currencyCode: String?
    let reportTitle: String?

    init(
        type: ProfessionalReportType,
        startDate: Date,
        endDate: Date,
        transactionIDs: [UUID] = [],
        accountIDs: [UUID] = [],
        currencyCode: String? = nil,
        reportTitle: String? = nil
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.transactionIDs = transactionIDs
        self.accountIDs = accountIDs
        self.currencyCode = currencyCode
        self.reportTitle = reportTitle
    }

    private var reportScope: ProfessionalReportScope {
        var value = ProfessionalReportScope()
        value.transactionIDs = Set(transactionIDs)
        value.accountIDs = Set(accountIDs)
        value.currencyCode = currencyCode
        value.reportTitle = reportTitle
        return value
    }

    @State private var isGenerating = false
    @State private var snapshot: ReportSnapshotPayload?
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Button { generate(.pdf) } label: {
                Label("PDF", systemImage: "doc.richtext.fill")
            }
            Button { generate(.excel) } label: {
                Label("Excel", systemImage: "tablecells.fill")
            }
        } label: {
            Group {
                if isGenerating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.purple)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(isGenerating)
        .accessibilityLabel("Download \(type.rawValue)")
        .sheet(item: $snapshot) { payload in
            ReportGeneratedSnapshotSheet(payload: payload)
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

    private func generate(_ format: ProfessionalExportFormat) {
        isGenerating = true
        defer { isGenerating = false }
        let document = ProfessionalReportBuilder.build(
            type: type,
            startDate: startDate,
            endDate: endDate,
            store: store,
            scope: reportScope
        )
        do {
            let url = try ProfessionalReportExporter.export(document, format: format)
            snapshot = ReportSnapshotPayload(document: document, url: url, format: format)
        } catch {
            errorMessage = "The \(format.rawValue) report could not be generated. \(error.localizedDescription)"
        }
    }
}

struct AccountStatementDownloadButton: View {
    @EnvironmentObject private var store: LedgerStore
    let accountID: UUID
    @State private var isGenerating = false
    @State private var snapshot: ReportSnapshotPayload?
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Button { generate(.pdf) } label: {
                Label("Account Statement PDF", systemImage: "doc.richtext.fill")
            }
            Button { generate(.excel) } label: {
                Label("Account Statement Excel", systemImage: "tablecells.fill")
            }
        } label: {
            if isGenerating {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "square.and.arrow.down.fill")
                    .foregroundStyle(AppTheme.purple)
            }
        }
        .disabled(isGenerating)
        .accessibilityLabel("Download account statement")
        .sheet(item: $snapshot) { payload in
            ReportGeneratedSnapshotSheet(payload: payload)
        }
        .alert("Account Export", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The account statement could not be generated.")
        }
    }

    private func generate(_ format: ProfessionalExportFormat) {
        guard let account = store.account(withID: accountID) else { return }
        isGenerating = true
        defer { isGenerating = false }
        let ids = store.relatedAccountIDs(for: accountID)
        let dates = store.transactions.compactMap { tx -> Date? in
            let belongs = tx.accountID.map(ids.contains) == true || tx.destinationAccountID.map(ids.contains) == true
            return belongs ? tx.date : nil
        }
        let start = dates.min() ?? account.createdAt
        let end = Date()
        let document = ProfessionalReportBuilder.accountStatement(
            accountID: accountID,
            startDate: start,
            endDate: end,
            store: store
        )
        do {
            let url = try ProfessionalReportExporter.export(document, format: format)
            snapshot = ReportSnapshotPayload(document: document, url: url, format: format)
        } catch {
            errorMessage = "The \(format.rawValue) account statement could not be generated. \(error.localizedDescription)"
        }
    }
}

struct ProfessionalReportTypeView: View {
    let type: ProfessionalReportType

    @AppStorage("ProfessionalReportStartDateV1") private var storedStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    @AppStorage("ProfessionalReportEndDateV1") private var storedEndDate = Date().timeIntervalSince1970

    private var startDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedStartDate) },
            set: { value in
                storedStartDate = Calendar.current.startOfDay(for: value).timeIntervalSince1970
                if storedStartDate > storedEndDate { storedEndDate = storedStartDate }
            }
        )
    }

    private var endDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedEndDate) },
            set: { value in
                storedEndDate = Calendar.current.startOfDay(for: value).timeIntervalSince1970
                if storedEndDate < storedStartDate { storedStartDate = storedEndDate }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: type.icon)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.purple.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(type.rawValue).font(.headline)
                        Text(type.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 5)
            }
            Section(type.usesAsOfDateOnly ? "Report Date" : "Period") {
                if type.usesAsOfDateOnly {
                    DatePicker("As of", selection: endDate, displayedComponents: .date)
                } else {
                    DatePicker("From", selection: startDate, displayedComponents: .date)
                    DatePicker("To", selection: endDate, in: startDate.wrappedValue..., displayedComponents: .date)
                }
            }
            Section {
                Label("Generate PDF or Excel from the download button. A snapshot is shown before sharing.", systemImage: "doc.text.image.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(type.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ReportDownloadButton(type: type, startDate: startDate.wrappedValue, endDate: endDate.wrappedValue)
            }
        }
    }
}

struct QuickReportShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct QuickReportActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
