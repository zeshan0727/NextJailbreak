import Darwin
import Foundation

struct SMSImportConfiguration: Codable, Equatable {
    var enabled = true
    var autoRecord = false
    var realtimeCaptureEnabled = false
    var cardAccountIDs: [String: String] = [:]
    var cashAccountID: String?
    var customEnding = ""
    var customAccountID: String?
    var clearLogsRequestID = 0
    var approvedSenders: [String] = ["Cb SMS"]
    var automaticScanIntervalHours = 6
    var scanRequestID = 0

    enum CodingKeys: String, CodingKey {
        case enabled
        case autoRecord
        case realtimeCaptureEnabled
        case cardAccountIDs
        case cashAccountID
        case customEnding
        case customAccountID
        case clearLogsRequestID
        case approvedSenders
        case automaticScanIntervalHours
        case scanRequestID
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        autoRecord = try container.decodeIfPresent(Bool.self, forKey: .autoRecord) ?? false
        realtimeCaptureEnabled = try container.decodeIfPresent(Bool.self, forKey: .realtimeCaptureEnabled) ?? false
        cardAccountIDs = try container.decodeIfPresent([String: String].self, forKey: .cardAccountIDs) ?? [:]
        cashAccountID = try container.decodeIfPresent(String.self, forKey: .cashAccountID)
        customEnding = try container.decodeIfPresent(String.self, forKey: .customEnding) ?? ""
        customAccountID = try container.decodeIfPresent(String.self, forKey: .customAccountID)
        clearLogsRequestID = try container.decodeIfPresent(Int.self, forKey: .clearLogsRequestID) ?? 0
        approvedSenders = try container.decodeIfPresent([String].self, forKey: .approvedSenders) ?? ["Cb SMS"]
        automaticScanIntervalHours = min(max(try container.decodeIfPresent(Int.self, forKey: .automaticScanIntervalHours) ?? 6, 1), 168)
        scanRequestID = try container.decodeIfPresent(Int.self, forKey: .scanRequestID) ?? 0
    }
}

struct SMSImportDraft: Codable, Identifiable, Equatable {
    let id: UUID
    let sourceKey: String
    let sender: String
    let rowID: Int64
    let kind: String
    let currency: String
    let amount: Decimal
    let cardEnding: String
    let vendor: String
    let date: Date
    let details: String
    let queuedAt: Date

    var transactionType: TransactionType {
        switch kind {
        case "cashback", "reversal", "income", "reviewIncome": return .income
        case "withdrawal", "incomingTransfer", "cashDeposit", "reviewTransfer": return .transfer
        default: return .expense
        }
    }

    var displayType: String {
        switch transactionType {
        case .income: return "Income"
        case .expense: return "Expense"
        case .transfer: return "Transfer"
        }
    }

    var cleanedDescription: String {
        Self.extractMessage(from: details)
    }

    var cleanedVendor: String {
        let message = cleanedDescription
        let currencyPattern = "(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)"
        let amountPattern = "[0-9][0-9,]*(?:\\.[0-9]{1,2})?"
        let pattern: String
        switch kind {
        case "withdrawal":
            pattern = "(?i)\\bat\\s+(.+?)(?=\\s+your available|\\s+available balance|$)"
        case "incomingTransfer":
            pattern = "(?i)\\bref\\s+(.+?)(?=\\s+withM-|\\s+at\\s+\\d{1,2}:\\d{2}|$)"
        case "cashback":
            return "Credit Card Cashback"
        case "income":
            pattern = "(?i)\\bfrom\\s+(.+?)(?=\\s+on\\s+\\d|\\s+at\\s+\\d|$)"
        default:
            pattern = "(?i)\\b(?:was\\s+)?used for\\s+\(currencyPattern)\\s*\(amountPattern)\\s+at\\s+(.+?)(?=\\s+at\\s+\\d{1,2}:\\d{2}\\s+\\d{1,2}-[A-Za-z]{3}-\\d{2,4}|\\s+at\\s+\\d{1,2}/\\d{1,2}/\\d{2,4}|\\s+available limit|\\s+balance:|\\s+enquiry\\s+\\d+|$)"
        }
        if let captured = Self.capture(pattern, in: message) {
            return captured.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return vendor
            .replacingOccurrences(
                of: "(?i)\\s+at\\s+\\d{1,2}:\\d{2}\\s+\\d{1,2}-[A-Za-z]{3}-\\d{2,4}.*$",
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractMessage(from raw: String) -> String {
        let compact = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currency = "(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)"
        let amount = "[0-9][0-9,]*(?:\\.[0-9]{1,2})?"
        let patterns = [
            "(?i)\\b(Your card ending\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+\(currency)\\s*\(amount).*?Available Limit(?:\\s+is|:)?\\s+\(currency)?\\s*\(amount))\\b",
            "(?i)\\b(Debit Card\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+\(currency)\\s*\(amount).*?Enquiry\\s+\\d+)\\b",
            "(?i)\\b(Debit Card\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+\(currency)\\s*\(amount).*?Balance:\\s+\(currency)\\s*\(amount))\\b",
            "(?i)\\b(Withdrawal using Debit Card\\s+\\*\\*\\d{4}\\s+for\\s+\(currency)\\s*\(amount).*?available balance is\\s+\(currency)\\s*\(amount))\\b",
            "(?i)\\b(Bill Payment of\\s+\(currency)\\s*\(amount).*?was successful\\.?)",
            "(?i)\\b(Cashback amount of\\s+\(currency)\\s*\(amount).*?Available Limit(?:\\s+is|:)?\\s+\(currency)\\s*\(amount))\\b"
        ]
        for pattern in patterns {
            if let value = capture(pattern, in: compact) { return value }
        }
        let archiveMarkers = [
            "streamtyped", "NSAttributedString", "NSMutableAttributedString",
            "NSKeyedArchiver", "NSDictionary", "NS.rangeval", "NS.objects",
            "$classname", "$classes"
        ]
        if archiveMarkers.contains(where: { compact.localizedCaseInsensitiveContains($0) }) {
            return ""
        }
        return compact
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SMSAICandidate: Codable, Identifiable, Equatable {
    let id: UUID
    let sourceKey: String
    let sender: String
    let rowID: Int64
    let date: Date
    let details: String
    let queuedAt: Date
}

struct SMSImportLogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let level: String
    let message: String
}

struct SMSImportConsoleSnapshot: Codable, Equatable {
    var daemonRunning = false
    var lastHeartbeat: Date?
    var lastScanDate: Date?
    var lastImportDate: Date?
    var lastResult = "No daemon status received yet."
    var totalImported = 0
    var totalDuplicates = 0
    var totalParseFailures = 0
    var pendingCount = 0
    var scanInProgress: Bool?
    var scanProgressCurrent: Int?
    var scanProgressTotal: Int?
    var scanPhase: String?
    var aiCandidateCount: Int?
    var logs: [SMSImportLogEntry] = []
}

enum SMSImportConsoleService {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func loadConfiguration() -> SMSImportConfiguration {
        guard let data = try? Data(contentsOf: configurationURL),
              let value = try? decoder.decode(SMSImportConfiguration.self, from: data) else {
            return SMSImportConfiguration()
        }
        return value
    }

    static func saveConfiguration(_ configuration: SMSImportConfiguration) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let data = try encoder.encode(configuration)
        try data.write(to: configurationURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: configurationURL.path
        )
        // Wake the root daemon only when configuration/manual-scan state changes.
        // The daemon otherwise blocks until the next scheduled scan instead of polling sms.db.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.nextsolution.dailyledger.sms-daemon-wake" as CFString),
            nil,
            nil,
            true
        )
    }

    static func loadSnapshot() -> SMSImportConsoleSnapshot {
        guard let data = try? Data(contentsOf: consoleURL),
              let value = try? decoder.decode(SMSImportConsoleSnapshot.self, from: data) else {
            return SMSImportConsoleSnapshot()
        }
        return value
    }

    static func loadInstallerDiagnostic() -> String {
        (try? String(contentsOf: installerDiagnosticURL, encoding: .utf8)) ?? ""
    }

    static func loadAICandidates() -> [SMSAICandidate] {
        (try? withDraftLock {
            guard let data = try? Data(contentsOf: aiCandidatesURL) else { return [] }
            return (try? decoder.decode([SMSAICandidate].self, from: data)) ?? []
        }) ?? []
    }

    static func completeAICandidate(_ candidate: SMSAICandidate) throws {
        try withDraftLock {
            var candidates: [SMSAICandidate] = []
            if let data = try? Data(contentsOf: aiCandidatesURL) {
                candidates = (try? decoder.decode([SMSAICandidate].self, from: data)) ?? []
            }
            candidates.removeAll { $0.id == candidate.id }
            try encoder.encode(candidates).write(to: aiCandidatesURL, options: .atomic)

            var processed: [String] = []
            if let data = try? Data(contentsOf: aiProcessedURL) {
                processed = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
            if !processed.contains(candidate.id.uuidString) { processed.append(candidate.id.uuidString) }
            if processed.count > 10_000 { processed.removeFirst(processed.count - 10_000) }
            try JSONEncoder().encode(processed).write(to: aiProcessedURL, options: .atomic)
        }
    }

    static func applyAIRecovery(_ result: SMSAIRecognitionResult, to candidate: SMSAICandidate) throws {
        guard result.transactionType != "ignore" else {
            try completeAICandidate(candidate)
            return
        }
        guard let rawAmount = result.amount?.replacingOccurrences(of: ",", with: ""),
              let amount = Decimal(string: rawAmount), amount > 0,
              let currency = result.currency?.trimmingCharacters(in: .whitespacesAndNewlines),
              !currency.isEmpty else {
            throw SMSAIRecognitionError.invalidResponse
        }

        let kind: String
        let normalizedCategory = result.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch result.transactionType {
        case "income":
            kind = (normalizedCategory.contains("refund") || normalizedCategory.contains("reversal"))
                ? "reversal"
                : "reviewIncome"
        case "transfer": kind = "reviewTransfer"
        default: kind = "reviewExpense"
        }
        let alias = result.accountAlias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let vendor = result.vendor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = SMSImportDraft(
            id: candidate.id,
            sourceKey: candidate.sourceKey,
            sender: candidate.sender,
            rowID: candidate.rowID,
            kind: kind,
            currency: currency.uppercased() == "QR" ? "QAR" : currency.uppercased(),
            amount: amount,
            cardEnding: alias.uppercased(),
            vendor: (vendor?.isEmpty == false ? vendor! : "AI Review"),
            date: candidate.date,
            details: candidate.details,
            queuedAt: candidate.queuedAt
        )

        try withDraftLock {
            var drafts: [SMSImportDraft] = []
            if let data = try? Data(contentsOf: draftsURL) {
                drafts = (try? decoder.decode([SMSImportDraft].self, from: data)) ?? []
            }
            drafts.removeAll { $0.id == candidate.id || $0.sourceKey == candidate.sourceKey }
            drafts.append(replacement)
            drafts.sort { $0.rowID > $1.rowID }
            try encoder.encode(drafts).write(to: draftsURL, options: .atomic)

            var candidates: [SMSAICandidate] = []
            if let data = try? Data(contentsOf: aiCandidatesURL) {
                candidates = (try? decoder.decode([SMSAICandidate].self, from: data)) ?? []
            }
            candidates.removeAll { $0.id == candidate.id }
            try encoder.encode(candidates).write(to: aiCandidatesURL, options: .atomic)

            var processed: [String] = []
            if let data = try? Data(contentsOf: aiProcessedURL) {
                processed = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
            if !processed.contains(candidate.id.uuidString) { processed.append(candidate.id.uuidString) }
            if processed.count > 10_000 { processed.removeFirst(processed.count - 10_000) }
            try JSONEncoder().encode(processed).write(to: aiProcessedURL, options: .atomic)
        }
    }

    static func loadDrafts() -> [SMSImportDraft] {
        (try? withDraftLock {
            guard let data = try? Data(contentsOf: draftsURL) else { return [] }
            return (try? decoder.decode([SMSImportDraft].self, from: data)) ?? []
        }) ?? []
    }

    static func completeDraft(_ draft: SMSImportDraft) throws {
        try withDraftLock {
            var drafts: [SMSImportDraft] = []
            if let data = try? Data(contentsOf: draftsURL) {
                drafts = (try? decoder.decode([SMSImportDraft].self, from: data)) ?? []
            }
            drafts.removeAll { $0.id == draft.id }
            try encoder.encode(drafts).write(to: draftsURL, options: .atomic)

            var reviewed: [String] = []
            if let data = try? Data(contentsOf: reviewedURL) {
                reviewed = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
            if !reviewed.contains(draft.id.uuidString) {
                reviewed.append(draft.id.uuidString)
            }
            try JSONEncoder().encode(reviewed).write(to: reviewedURL, options: .atomic)
        }
    }

    static func restoreRejectedForReview(recordedTransactionIDs: Set<UUID>) throws -> Int {
        try withDraftLock {
            var reviewed: [String] = []
            if let data = try? Data(contentsOf: reviewedURL) {
                reviewed = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
            let originalCount = reviewed.count
            reviewed.removeAll { value in
                guard let identifier = UUID(uuidString: value) else { return false }
                return !recordedTransactionIDs.contains(identifier)
            }
            try JSONEncoder().encode(reviewed).write(to: reviewedURL, options: .atomic)
            return originalCount - reviewed.count
        }
    }

    private static func withDraftLock<T>(_ work: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return try work() }
        var writeLock = flock()
        writeLock.l_type = Int16(F_WRLCK)
        writeLock.l_whence = Int16(SEEK_SET)
        guard fcntl(descriptor, F_SETLKW, &writeLock) != -1 else {
            Darwin.close(descriptor)
            return try work()
        }
        defer {
            var unlock = flock()
            unlock.l_type = Int16(F_UNLCK)
            unlock.l_whence = Int16(SEEK_SET)
            _ = fcntl(descriptor, F_SETLK, &unlock)
            Darwin.close(descriptor)
        }
        return try work()
    }

    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("DailyLedger", isDirectory: true)
    }

    static var configurationURL: URL {
        directoryURL.appendingPathComponent("sms-import-config.json")
    }

    static var consoleURL: URL {
        directoryURL.appendingPathComponent("sms-import-console.json")
    }

    static var installerDiagnosticURL: URL {
        directoryURL.appendingPathComponent("sms-import-install.log")
    }

    static var draftsURL: URL {
        directoryURL.appendingPathComponent("sms-import-drafts.json")
    }

    static var reviewedURL: URL {
        directoryURL.appendingPathComponent("sms-import-reviewed.json")
    }

    static var aiCandidatesURL: URL {
        directoryURL.appendingPathComponent("sms-ai-candidates.json")
    }

    static var aiProcessedURL: URL {
        directoryURL.appendingPathComponent("sms-ai-processed.json")
    }

    static var lockURL: URL {
        directoryURL.appendingPathComponent("sms-import-drafts.lock")
    }
}
