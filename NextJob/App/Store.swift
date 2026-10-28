import Combine
import Foundation

@MainActor
final class JobStore: ObservableObject {
    @Published private(set) var jobs: [AccountingJob] = []
    @Published private(set) var jobTypes: [JobType] = []
    @Published private(set) var settings = AppSettings()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
        seedJobTypesIfNeeded()
    }

    var sortedJobs: [AccountingJob] {
        jobs.sorted { lhs, rhs in
            if lhs.status == .completed, rhs.status != .completed { return false }
            if lhs.status != .completed, rhs.status == .completed { return true }
            return lhs.dueDate < rhs.dueDate
        }
    }

    var completedValue: Double {
        jobs.filter { $0.status == .completed }.reduce(0) { $0 + $1.price }
    }

    var outstandingValue: Double {
        jobs.filter { $0.status != .completed }.reduce(0) { $0 + $1.price }
    }

    var totalTargetHours: Double {
        jobs.reduce(0) { $0 + $1.targetHours }
    }

    var totalActualHours: Double {
        jobs.reduce(0) { $0 + $1.actualHours }
    }

    func count(for status: JobStatus) -> Int {
        jobs.filter { $0.status == status }.count
    }

    func job(id: UUID) -> AccountingJob? {
        jobs.first { $0.id == id }
    }

    func type(id: UUID?) -> JobType? {
        guard let id else { return nil }
        return jobTypes.first { $0.id == id }
    }

    func typeName(for job: AccountingJob) -> String {
        if let type = type(id: job.jobTypeID) { return type.name }
        if !job.customTypeName.isEmpty { return job.customTypeName }
        return "Unspecified"
    }

    func upsert(_ job: AccountingJob) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
        save()
    }

    func delete(_ job: AccountingJob) {
        jobs.removeAll { $0.id == job.id }
        try? fileManager.removeItem(at: jobFolderURL(jobID: job.id, create: false))
        save()
    }

    func setStatus(_ status: JobStatus, for jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = status
        jobs[index].updatedAt = Date()
        if status == .completed, jobs[index].completionDate == nil {
            jobs[index].completionDate = Date()
        } else if status != .completed {
            jobs[index].completionDate = nil
        }
        save()
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        save()
    }

    func addJobType(_ type: JobType) {
        jobTypes.append(type)
        jobTypes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    func updateJobType(_ type: JobType) {
        guard let index = jobTypes.firstIndex(where: { $0.id == type.id }) else { return }
        jobTypes[index] = type
        jobTypes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    func deleteJobType(_ type: JobType) {
        jobTypes.removeAll { $0.id == type.id }
        for index in jobs.indices where jobs[index].jobTypeID == type.id {
            jobs[index].jobTypeID = nil
            if jobs[index].customTypeName.isEmpty {
                jobs[index].customTypeName = type.name
            }
        }
        save()
    }

    func importFiles(_ urls: [URL], to jobID: UUID, kind: AttachmentKind) throws {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else {
            throw StoreError.jobNotFound
        }

        let folder = jobFolderURL(jobID: jobID, create: true)
        var newAttachments: [JobAttachment] = []

        for sourceURL in urls {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

            let originalName = sourceURL.lastPathComponent.isEmpty ? "Document" : sourceURL.lastPathComponent
            let safeName = uniqueStoredName(for: originalName, in: folder)
            let destination = folder.appendingPathComponent(safeName)
            try fileManager.copyItem(at: sourceURL, to: destination)
            let values = try? destination.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = Int64(values?.fileSize ?? 0)
            newAttachments.append(
                JobAttachment(
                    originalName: originalName,
                    storedName: safeName,
                    kind: kind,
                    byteCount: byteCount
                )
            )
        }

        jobs[jobIndex].attachments.append(contentsOf: newAttachments)
        jobs[jobIndex].updatedAt = Date()
        save()
    }

    func removeAttachment(_ attachment: JobAttachment, from jobID: UUID) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let url = fileURL(for: attachment, jobID: jobID)
        try? fileManager.removeItem(at: url)
        jobs[jobIndex].attachments.removeAll { $0.id == attachment.id }
        jobs[jobIndex].updatedAt = Date()
        save()
    }

    func fileURL(for attachment: JobAttachment, jobID: UUID) -> URL {
        jobFolderURL(jobID: jobID, create: false).appendingPathComponent(attachment.storedName)
    }

    func makeJobPackage(jobID: UUID) throws -> URL {
        guard let job = job(id: jobID) else { throw StoreError.jobNotFound }
        let dateText = DateFormatter.packageDate.string(from: Date())
        let baseName = sanitizedFileName(job.title.isEmpty ? "Job" : job.title)
        let destination = fileManager.temporaryDirectory
            .appendingPathComponent("\(baseName)-\(dateText).zip")

        try? fileManager.removeItem(at: destination)

        var entries: [ZipEntry] = [
            ZipEntry(name: "Job Summary.txt", data: Data(summaryText(for: job).utf8))
        ]

        for attachment in job.attachments {
            let source = fileURL(for: attachment, jobID: job.id)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let data = try Data(contentsOf: source)
            let folder = attachment.kind == .sourceDocument ? "Source Documents" : "Completed Work"
            entries.append(ZipEntry(name: "\(folder)/\(attachment.originalName)", data: data))
        }

        try StoredZipWriter.write(entries: entries, to: destination)
        return destination
    }

    func summaryText(for job: AccountingJob) -> String {
        let completed = job.completionDate.map { DateFormatter.mediumDate.string(from: $0) } ?? "Not completed"
        return """
        NEXT JOB - JOB SUMMARY

        Job: \(job.title)
        Client / Reference: \(job.clientReference.isEmpty ? "Not provided" : job.clientReference)
        Type: \(typeName(for: job))
        Status: \(job.status.title)
        Assigned: \(DateFormatter.mediumDate.string(from: job.assignedDate))
        Due: \(DateFormatter.mediumDate.string(from: job.dueDate))
        Completed: \(completed)
        Price: \(settings.currency) \(String(format: "%.2f", job.price))
        Target Time: \(String(format: "%.1f", job.targetHours)) hours
        Actual Time: \(String(format: "%.1f", job.actualHours)) hours

        DOCUMENTS / REQUIREMENTS
        \(job.requirements.isEmpty ? "None recorded" : job.requirements)

        WORK NOTES
        \(job.notes.isEmpty ? "None recorded" : job.notes)

        Source documents: \(job.attachments.filter { $0.kind == .sourceDocument }.count)
        Completed work files: \(job.attachments.filter { $0.kind == .completedWork }.count)
        """
    }

    private func seedJobTypesIfNeeded() {
        guard jobTypes.isEmpty else { return }
        jobTypes = [
            JobType(name: "Bank Reconciliation", targetHours: 2),
            JobType(name: "Bookkeeping", targetHours: 4),
            JobType(name: "Company Accounts", targetHours: 8),
            JobType(name: "Management Accounts", targetHours: 6),
            JobType(name: "Payroll", targetHours: 2),
            JobType(name: "Tax / VAT Return", targetHours: 4),
            JobType(name: "Year-End Accounts", targetHours: 10),
            JobType(name: "Other", targetHours: 1)
        ]
        save()
    }

    private func load() {
        let url = dataFileURL
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(NextJobSnapshot.self, from: data) else {
            return
        }
        jobs = snapshot.jobs
        jobTypes = snapshot.jobTypes
        settings = snapshot.settings
    }

    private func save() {
        do {
            let folder = appSupportFolder
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let snapshot = NextJobSnapshot(jobs: jobs, jobTypes: jobTypes, settings: settings)
            let data = try encoder.encode(snapshot)
            try data.write(to: dataFileURL, options: .atomic)
        } catch {
            assertionFailure("Next Job save failed: \(error)")
        }
    }

    private var appSupportFolder: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NextJob", isDirectory: true)
    }

    private var dataFileURL: URL {
        appSupportFolder.appendingPathComponent("next-job-data.json")
    }

    private func jobFolderURL(jobID: UUID, create: Bool) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents
            .appendingPathComponent("Next Job Files", isDirectory: true)
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
        if create {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private func uniqueStoredName(for originalName: String, in folder: URL) -> String {
        let clean = sanitizedFileName(originalName)
        let extensionText = (clean as NSString).pathExtension
        let stem = (clean as NSString).deletingPathExtension
        var candidate = clean
        var counter = 2
        while fileManager.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = extensionText.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(extensionText)"
            counter += 1
        }
        return candidate
    }

    private func sanitizedFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let parts = value.components(separatedBy: invalid)
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "-")
        return joined.isEmpty ? "File" : joined
    }
}

enum StoreError: LocalizedError {
    case jobNotFound

    var errorDescription: String? {
        switch self {
        case .jobNotFound: return "The selected job could not be found."
        }
    }
}

extension DateFormatter {
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let packageDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
