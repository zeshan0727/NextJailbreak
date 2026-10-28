import Foundation

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum JobStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted
    case inProgress
    case waitingForDocuments
    case readyForReview
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .waitingForDocuments: return "Waiting for Documents"
        case .readyForReview: return "Ready for Review"
        case .completed: return "Completed"
        }
    }

    var icon: String {
        switch self {
        case .notStarted: return "circle.dashed"
        case .inProgress: return "clock.arrow.circlepath"
        case .waitingForDocuments: return "doc.badge.ellipsis"
        case .readyForReview: return "checklist"
        case .completed: return "checkmark.seal.fill"
        }
    }
}

enum AttachmentKind: String, Codable, CaseIterable, Identifiable {
    case sourceDocument
    case completedWork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sourceDocument: return "Source Documents"
        case .completedWork: return "Completed Work"
        }
    }
}

struct JobAttachment: Identifiable, Codable, Hashable {
    var id: UUID
    var originalName: String
    var storedName: String
    var kind: AttachmentKind
    var addedAt: Date
    var byteCount: Int64

    init(
        id: UUID = UUID(),
        originalName: String,
        storedName: String,
        kind: AttachmentKind,
        addedAt: Date = Date(),
        byteCount: Int64 = 0
    ) {
        self.id = id
        self.originalName = originalName
        self.storedName = storedName
        self.kind = kind
        self.addedAt = addedAt
        self.byteCount = byteCount
    }
}

struct JobType: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var defaultPrice: Double
    var targetHours: Double
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        defaultPrice: Double = 0,
        targetHours: Double = 1,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.defaultPrice = defaultPrice
        self.targetHours = targetHours
        self.isArchived = isArchived
    }
}

struct AccountingJob: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var clientReference: String
    var jobTypeID: UUID?
    var customTypeName: String
    var status: JobStatus
    var assignedDate: Date
    var dueDate: Date
    var completionDate: Date?
    var price: Double
    var targetHours: Double
    var actualHours: Double
    var requirements: String
    var notes: String
    var attachments: [JobAttachment]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        clientReference: String = "",
        jobTypeID: UUID? = nil,
        customTypeName: String = "",
        status: JobStatus = .notStarted,
        assignedDate: Date = Date(),
        dueDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
        completionDate: Date? = nil,
        price: Double = 0,
        targetHours: Double = 1,
        actualHours: Double = 0,
        requirements: String = "",
        notes: String = "",
        attachments: [JobAttachment] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.clientReference = clientReference
        self.jobTypeID = jobTypeID
        self.customTypeName = customTypeName
        self.status = status
        self.assignedDate = assignedDate
        self.dueDate = dueDate
        self.completionDate = completionDate
        self.price = price
        self.targetHours = targetHours
        self.actualHours = actualHours
        self.requirements = requirements
        self.notes = notes
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct AppSettings: Codable, Hashable {
    var companyName: String = "KB Accountants"
    var companyEmail: String = ""
    var senderName: String = "Zeeshan Barvi"
    var senderEmail: String = ""
    var currency: String = "QAR"
    var theme: AppTheme = .system
}

struct NextJobSnapshot: Codable {
    var jobs: [AccountingJob]
    var jobTypes: [JobType]
    var settings: AppSettings
}

struct JobDraft {
    var id: UUID?
    var title: String = ""
    var clientReference: String = ""
    var jobTypeID: UUID?
    var customTypeName: String = ""
    var status: JobStatus = .notStarted
    var assignedDate: Date = Date()
    var dueDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    var completionDateEnabled: Bool = false
    var completionDate: Date = Date()
    var price: Double = 0
    var targetHours: Double = 1
    var actualHours: Double = 0
    var requirements: String = ""
    var notes: String = ""
    var attachments: [JobAttachment] = []
    var createdAt: Date = Date()

    init() {}

    init(job: AccountingJob) {
        id = job.id
        title = job.title
        clientReference = job.clientReference
        jobTypeID = job.jobTypeID
        customTypeName = job.customTypeName
        status = job.status
        assignedDate = job.assignedDate
        dueDate = job.dueDate
        completionDateEnabled = job.completionDate != nil
        completionDate = job.completionDate ?? Date()
        price = job.price
        targetHours = job.targetHours
        actualHours = job.actualHours
        requirements = job.requirements
        notes = job.notes
        attachments = job.attachments
        createdAt = job.createdAt
    }

    func makeJob() -> AccountingJob {
        AccountingJob(
            id: id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            clientReference: clientReference.trimmingCharacters(in: .whitespacesAndNewlines),
            jobTypeID: jobTypeID,
            customTypeName: customTypeName.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            assignedDate: assignedDate,
            dueDate: dueDate,
            completionDate: completionDateEnabled ? completionDate : nil,
            price: max(0, price),
            targetHours: max(0, targetHours),
            actualHours: max(0, actualHours),
            requirements: requirements.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            attachments: attachments,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}
