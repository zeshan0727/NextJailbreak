import Foundation

enum CustomerType: String, CaseIterable, Codable, Identifiable, Hashable {
    case monthlyMaintenance = "Monthly Maintenance"
    case oneTimeJob = "One-Time Job"
    case project = "Project"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .monthlyMaintenance: return "Monthly"
        case .oneTimeJob: return "One-Time"
        case .project: return "Project"
        }
    }

    var icon: String {
        switch self {
        case .monthlyMaintenance: return "calendar.badge.clock"
        case .oneTimeJob: return "hammer.fill"
        case .project: return "building.2.fill"
        }
    }

    var tracksMonthlyVisits: Bool { self == .monthlyMaintenance }
}

enum JobType: String, CaseIterable, Codable, Identifiable, Hashable {
    case monthlyMaintenance = "Monthly Maintenance"
    case oneTimeJob = "One-Time Job"
    case project = "Project"

    var id: String { rawValue }

    init(customerType: CustomerType) {
        switch customerType {
        case .monthlyMaintenance: self = .monthlyMaintenance
        case .oneTimeJob: self = .oneTimeJob
        case .project: self = .project
        }
    }
}

enum QuoteDiscountMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case none = "No Discount"
    case percentage = "Percentage"
    case amount = "Fixed Amount"
    var id: String { rawValue }
}

enum QuotationStatus: String, CaseIterable, Codable, Identifiable, Hashable {
    case draft = "Draft"
    case sent = "Sent"
    case accepted = "Accepted"
    case rejected = "Rejected"
    case expired = "Expired"
    var id: String { rawValue }
}

struct CatalogItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var details: String
    var unit: String
    var unitPrice: Double
    var category: String
    var isActive: Bool
    var createdAt: Date = Date()
    /// Optional reusable variants such as stone colours, sizes, finishes or service options.
    var variants: [String]? = nil

    var availableVariants: [String] {
        (variants ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

struct Quotation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var number: String
    var customerID: UUID
    var jobType: JobType
    var issueDate: Date
    var validUntil: Date
    var lineItems: [InvoiceLineItem]
    var discountMode: QuoteDiscountMode
    var discountValue: Double
    var notes: String
    var status: QuotationStatus
    var employeeID: UUID? = nil
    /// Optional for backward-compatible decoding. Set after an accepted quotation becomes an invoice.
    var convertedInvoiceID: UUID? = nil
    var acceptedAt: Date? = nil
    var createdAt: Date = Date()

    var subtotal: Double { lineItems.reduce(0) { $0 + $1.amount } }

    var discountAmount: Double {
        switch discountMode {
        case .none:
            return 0
        case .percentage:
            return subtotal * min(max(discountValue, 0), 100) / 100
        case .amount:
            return min(max(discountValue, 0), subtotal)
        }
    }

    var total: Double { max(0, subtotal - discountAmount) }
}

extension Customer {
    var resolvedType: CustomerType { customerType ?? .monthlyMaintenance }
    var resolvedArchived: Bool { isArchived ?? false }
}

extension Invoice {
    var resolvedJobType: JobType { jobType ?? .monthlyMaintenance }
}
