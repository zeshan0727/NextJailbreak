import Foundation

struct Employee: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var role: String
    var phone: String
    var email: String
    var monthlySalary: Double
    var joiningDate: Date
    var isActive: Bool
    var notes: String
}

struct BankAccount: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String
    var bankName: String
    var accountHolderName: String
    var accountNumber: String
    var iban: String
    var swiftCode: String
    var currencyCode: String
    var isDefault: Bool
}

struct AdvancePayment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var customerID: UUID
    var date: Date
    var amount: Double
    var paymentAccount: String
    var reference: String
    var notes: String
    var employeeID: UUID?
}

struct ExpenseRefund: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var expenseID: UUID
    var date: Date
    var amount: Double
    var notes: String
}

struct InvoicePDFOverlayImage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var imageData: Data
    /// Normalized A4 coordinates (0...1), so the layout stays device-independent.
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct PDFNormalizedRect: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    func clamped() -> PDFNormalizedRect {
        let w = max(0.04, min(1, width))
        let h = max(0.025, min(1, height))
        return PDFNormalizedRect(
            x: max(0, min(1 - w, x)),
            y: max(0, min(1 - h, y)),
            width: w,
            height: h
        )
    }
}

struct InvoicePDFSettings: Codable, Equatable, Hashable {
    var showLogo: Bool
    var showCompanyName: Bool
    var showCompanyContact: Bool
    var showBillTo: Bool
    var showInvoiceMeta: Bool
    var showItems: Bool
    var showPayment: Bool
    var showTerms: Bool
    var showFooter: Bool
    var showPaymentStatus: Bool

    var invoiceTitle: String
    var billToTitle: String
    var paymentTitle: String
    var termsTitle: String
    var footerText: String
    var paidText: String
    var unpaidText: String
    var partialPaidText: String
    var companyNameOverride: String
    var companyContactOverride: String
    var logoData: Data?
    var overlayImages: [InvoicePDFOverlayImage]
    /// Optional for backward-compatible decoding. Keys are PDFEditableZone.rawValue.
    var zoneFrames: [String: PDFNormalizedRect]? = nil

    static let aspireDefault = InvoicePDFSettings(
        showLogo: true,
        showCompanyName: true,
        showCompanyContact: true,
        showBillTo: true,
        showInvoiceMeta: true,
        showItems: true,
        showPayment: true,
        showTerms: true,
        showFooter: true,
        showPaymentStatus: true,
        invoiceTitle: "INVOICE",
        billToTitle: "BILL TO",
        paymentTitle: "PAYMENT METHOD",
        termsTitle: "TERMS OR NOTES",
        footerText: "Built on Service  •  Landscaping  •  Gardening  •  General Maintenance",
        paidText: "PAID",
        unpaidText: "UNPAID",
        partialPaidText: "PART PAID",
        companyNameOverride: "",
        companyContactOverride: "",
        logoData: nil,
        overlayImages: [],
        zoneFrames: nil
    )

    static var aspireQuotationDefault: InvoicePDFSettings {
        var value = aspireDefault
        value.invoiceTitle = "QUOTATION"
        value.billToTitle = "QUOTATION TO"
        value.paymentTitle = "SUMMARY / PAYMENT"
        value.termsTitle = "TERMS / NOTES"
        value.paidText = "ACCEPTED"
        value.unpaidText = "DRAFT"
        value.partialPaidText = "SENT"
        return value
    }

    static var aspireReceiptDefault: InvoicePDFSettings {
        var value = aspireDefault
        value.invoiceTitle = "PAYMENT RECEIPT"
        value.billToTitle = "RECEIVED FROM"
        value.paymentTitle = "PAYMENT DETAILS"
        value.termsTitle = "REFERENCE / NOTES"
        value.paidText = "PAID"
        value.unpaidText = "RECEIVED"
        value.partialPaidText = "PART PAID"
        value.showTerms = true
        return value
    }

    func frame(for zone: PDFEditableZone) -> PDFNormalizedRect {
        (zoneFrames?[zone.rawValue] ?? zone.defaultFrame).clamped()
    }

    mutating func setFrame(_ frame: PDFNormalizedRect, for zone: PDFEditableZone) {
        var frames = zoneFrames ?? [:]
        frames[zone.rawValue] = frame.clamped()
        zoneFrames = frames
    }

    mutating func resetFrame(for zone: PDFEditableZone) {
        var frames = zoneFrames ?? [:]
        frames.removeValue(forKey: zone.rawValue)
        zoneFrames = frames.isEmpty ? nil : frames
    }
}

enum PDFEditableZone: String, CaseIterable, Identifiable {
    case logo
    case companyName
    case companyContact
    case invoiceTitle
    case paymentStatus
    case billTo
    case invoiceMeta
    case items
    case payment
    case terms
    case footer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logo: return "Logo"
        case .companyName: return "Company Name"
        case .companyContact: return "Company Contact"
        case .invoiceTitle: return "Document Title"
        case .paymentStatus: return "Document Status"
        case .billTo: return "Customer / Bill To"
        case .invoiceMeta: return "Dates / Details"
        case .items: return "Items / Amount"
        case .payment: return "Payment Details"
        case .terms: return "Terms / Notes"
        case .footer: return "Footer"
        }
    }

    var defaultFrame: PDFNormalizedRect {
        switch self {
        case .logo: return PDFNormalizedRect(x: 0.07, y: 0.025, width: 0.22, height: 0.13)
        case .companyName: return PDFNormalizedRect(x: 0.30, y: 0.045, width: 0.35, height: 0.07)
        case .companyContact: return PDFNormalizedRect(x: 0.07, y: 0.145, width: 0.86, height: 0.035)
        case .invoiceTitle: return PDFNormalizedRect(x: 0.63, y: 0.035, width: 0.30, height: 0.09)
        case .paymentStatus: return PDFNormalizedRect(x: 0.68, y: 0.925, width: 0.25, height: 0.035)
        case .billTo: return PDFNormalizedRect(x: 0.07, y: 0.20, width: 0.46, height: 0.14)
        case .invoiceMeta: return PDFNormalizedRect(x: 0.57, y: 0.20, width: 0.36, height: 0.12)
        case .items: return PDFNormalizedRect(x: 0.07, y: 0.355, width: 0.86, height: 0.22)
        case .payment: return PDFNormalizedRect(x: 0.07, y: 0.615, width: 0.56, height: 0.16)
        case .terms: return PDFNormalizedRect(x: 0.07, y: 0.815, width: 0.62, height: 0.11)
        case .footer: return PDFNormalizedRect(x: 0.01, y: 0.965, width: 0.98, height: 0.032)
        }
    }
}

enum PrintDocumentKind: String, CaseIterable, Identifiable {
    case invoice = "Invoice"
    case quotation = "Quotation"
    case receipt = "Payment Receipt"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .invoice: return "doc.text.fill"
        case .quotation: return "doc.text.magnifyingglass"
        case .receipt: return "checkmark.seal.fill"
        }
    }
}

enum ReceivableDashboardKind: String, CaseIterable, Identifiable {
    case outstanding
    case overdue
    case longOverdue
    case advances

    var id: String { rawValue }
    var title: String {
        switch self {
        case .outstanding: return "Outstanding Receivables"
        case .overdue: return "Overdue Receivables"
        case .longOverdue: return "30+ Days Receivables"
        case .advances: return "Advance Collections"
        }
    }
}
