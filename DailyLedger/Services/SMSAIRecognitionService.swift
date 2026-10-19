import Foundation

struct SMSAIRecognitionResult: Codable, Equatable {
    var transactionType: String
    var amount: String?
    var currency: String?
    var accountAlias: String?
    var vendor: String?
    var category: String?
    var confidence: Double
    var reason: String?
    var provider: String?
}

enum SMSAIRecognitionError: LocalizedError {
    case noProvider
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "Add an OpenAI or DeepSeek API key in Settings first."
        case .invalidResponse:
            return "AI did not return a valid transaction classification."
        }
    }
}

enum SMSAIRecognitionService {
    static let statusChanged = Notification.Name("SMSAIRecognitionStatusChanged")

    static var isAvailable: Bool {
        // SMS database recovery intentionally uses the existing OpenAI credential
        // from the main AI Settings. There is no separate SMS API key.
        OpenAIService.shared.hasAPIKey
    }

    static func cachedResult(for id: UUID) -> SMSAIRecognitionResult? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(id)),
              let result = try? JSONDecoder().decode(SMSAIRecognitionResult.self, from: data) else {
            return nil
        }
        return result
    }

    @discardableResult
    static func analyze(draft: SMSImportDraft) async throws -> SMSAIRecognitionResult {
        let response: String
        let provider: String
        let system = """
        You classify one bank SMS for a personal ledger. Return JSON only. Never invent an account, beneficiary, amount, currency, date, or direction that the SMS does not support. transactionType must be income, expense, transfer, or ignore. Use ignore for OTPs, login/security alerts, balance-only notifications, marketing, service messages, failed/declined transactions without an actual posted movement, and anything that is not a real ledger movement. Use transfer for card payments between the user's own bank/current/card accounts, cash withdrawals, remittances between accounts, or explicit transfers. Confidence must be 0 to 1. Keep vendor and category short.
        """
        let prompt = """
        Classify this bank SMS. JSON schema:
        {"transactionType":"income|expense|transfer|ignore","amount":"number or null","currency":"code or null","accountAlias":"source alias/card ending if stated or null","vendor":"counterparty/purpose or null","category":"short category or null","confidence":0.0,"reason":"short reason"}

        SMS:
        \(draft.details)
        """

        if OpenAIService.shared.hasAPIKey {
            provider = "OpenAI"
            let model = "gpt-4.1-nano"
            response = try await OpenAIService.shared.request(
                messages: [
                    OpenAIMessage(role: "system", content: system),
                    OpenAIMessage(role: "user", content: prompt)
                ],
                model: model,
                maxTokens: 320
            )
        } else if DeepSeekService.shared.hasAPIKey {
            provider = "DeepSeek"
            let model = UserDefaults.standard.string(forKey: "DeepSeekModel") ?? "deepseek-v4-flash"
            response = try await DeepSeekService.shared.request(
                messages: [
                    DeepSeekMessage(role: "system", content: system),
                    DeepSeekMessage(role: "user", content: prompt)
                ],
                model: model,
                maxTokens: 320
            )
        } else {
            throw SMSAIRecognitionError.noProvider
        }

        guard let data = jsonData(from: response),
              var result = try? JSONDecoder().decode(SMSAIRecognitionResult.self, from: data) else {
            throw SMSAIRecognitionError.invalidResponse
        }
        let allowed = ["income", "expense", "transfer", "ignore"]
        result.transactionType = result.transactionType.lowercased()
        guard allowed.contains(result.transactionType) else {
            throw SMSAIRecognitionError.invalidResponse
        }
        result.confidence = min(max(result.confidence, 0), 1)
        result.provider = provider
        if let encoded = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(encoded, forKey: cacheKey(draft.id))
        }
        UserDefaults.standard.set(provider, forKey: "SMSAILastProviderV1")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SMSAILastSuccessV1")
        UserDefaults.standard.set(result.transactionType, forKey: "SMSAILastTypeV1")
        UserDefaults.standard.set(Int((result.confidence * 100).rounded()), forKey: "SMSAILastConfidenceV1")
        UserDefaults.standard.removeObject(forKey: "SMSAILastErrorV1")
        NotificationCenter.default.post(name: statusChanged, object: nil)
        return result
    }

    static func recordFailure(_ error: Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: "SMSAILastErrorV1")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SMSAILastAttemptV1")
        NotificationCenter.default.post(name: statusChanged, object: nil)
    }

    static func analyze(candidate: SMSAICandidate) async throws -> SMSAIRecognitionResult {
        let temporary = SMSImportDraft(
            id: candidate.id,
            sourceKey: candidate.sourceKey,
            sender: candidate.sender,
            rowID: candidate.rowID,
            kind: "reviewTransaction",
            currency: "",
            amount: 0,
            cardEnding: "",
            vendor: "AI Database Recovery",
            date: candidate.date,
            details: candidate.details,
            queuedAt: candidate.queuedAt
        )
        return try await analyze(draft: temporary)
    }

    static func clearCache(for id: UUID) {
        UserDefaults.standard.removeObject(forKey: cacheKey(id))
    }

    static func clearAllCachedResults() {
        let defaults = UserDefaults.standard
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        for key in allKeys where key.hasPrefix("SMSAIRecognitionV1.") {
            defaults.removeObject(forKey: key)
        }
        [
            "SMSAILastProviderV1",
            "SMSAILastSuccessV1",
            "SMSAILastTypeV1",
            "SMSAILastConfidenceV1",
            "SMSAILastErrorV1",
            "SMSAILastAttemptV1",
            "SMSOpenAIWorkerStatusV2",
            "SMSOpenAILastErrorV1",
            "SMSOpenAILastSuccessAtV1",
            "SMSOpenAILastResultTypeV1"
        ].forEach { defaults.removeObject(forKey: $0) }
        let generation = defaults.integer(forKey: "SMSLatest15AIClearGeneration") + 1
        defaults.set(generation, forKey: "SMSLatest15AIClearGeneration")
        defaults.set(Date().timeIntervalSince1970, forKey: "SMSLatest15AIClearedAt")
        NotificationCenter.default.post(name: statusChanged, object: nil)
    }

    private static func cacheKey(_ id: UUID) -> String {
        "SMSAIRecognitionV1.\(id.uuidString)"
    }

    private static func jsonData(from raw: String) -> Data? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"), start <= end else { return nil }
        return String(raw[start...end]).data(using: .utf8)
    }
}

actor SMSOpenAIAutoRecoveryCoordinator {
    static let shared = SMSOpenAIAutoRecoveryCoordinator()

    private var processing = false
    private let statusKey = "SMSOpenAIWorkerStatusV2"
    private let lastErrorKey = "SMSOpenAILastErrorV1"
    private let retryPrefix = "SMSOpenAIRetryCountV2."
    private let nextRetryPrefix = "SMSOpenAINextRetryV2."
    private let blockedPrefix = "SMSOpenAIBlockedV2."

    func processPending(force: Bool = false, limit: Int = 5) async {
        guard !processing else { return }
        guard OpenAIService.shared.hasAPIKey else {
            setStatus("OpenAI API not connected")
            return
        }

        let allCandidates = SMSImportConsoleService.loadAICandidates()
        guard !allCandidates.isEmpty else {
            setStatus("Idle · No unresolved SMS")
            return
        }

        let now = Date().timeIntervalSince1970
        let candidates = allCandidates.filter { candidate in
            if force { return true }
            let id = candidate.id.uuidString
            if UserDefaults.standard.bool(forKey: blockedPrefix + id) { return false }
            let next = UserDefaults.standard.double(forKey: nextRetryPrefix + id)
            return next <= 0 || next <= now
        }

        guard !candidates.isEmpty else {
            setStatus("Paused · Waiting for retry or manual Retry AI Recovery")
            return
        }

        processing = true
        defer { processing = false }

        var completed = 0
        let batch = Array(candidates.prefix(max(1, min(limit, 5))))
        setStatus("Analyzing \(batch.count) unresolved SMS…")

        for candidate in batch {
            let id = candidate.id.uuidString
            do {
                let result = try await SMSAIRecognitionService.analyze(candidate: candidate)
                try SMSImportConsoleService.applyAIRecovery(result, to: candidate)
                completed += 1

                UserDefaults.standard.removeObject(forKey: retryPrefix + id)
                UserDefaults.standard.removeObject(forKey: nextRetryPrefix + id)
                UserDefaults.standard.removeObject(forKey: blockedPrefix + id)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SMSOpenAILastSuccessAtV1")
                UserDefaults.standard.set(result.transactionType, forKey: "SMSOpenAILastResultTypeV1")
                UserDefaults.standard.removeObject(forKey: lastErrorKey)
            } catch {
                let retryKey = retryPrefix + id
                let attempts = UserDefaults.standard.integer(forKey: retryKey) + 1
                UserDefaults.standard.set(attempts, forKey: retryKey)
                UserDefaults.standard.set(error.localizedDescription, forKey: lastErrorKey)

                if attempts >= 3 {
                    UserDefaults.standard.set(true, forKey: blockedPrefix + id)
                    UserDefaults.standard.removeObject(forKey: nextRetryPrefix + id)
                    setStatus("Paused · AI failed 3 times. Tap Retry AI Recovery.")
                } else {
                    let delay: TimeInterval = attempts == 1 ? 60 : 300
                    UserDefaults.standard.set(Date().addingTimeInterval(delay).timeIntervalSince1970,
                                                      forKey: nextRetryPrefix + id)
                    setStatus("AI error · Stopped. Retry available later or tap Retry AI Recovery.")
                }
                return
            }
        }

        let remaining = SMSImportConsoleService.loadAICandidates().count
        if remaining == 0 {
            setStatus(completed > 0 ? "Finished · Recovered \(completed) SMS" : "Idle · No unresolved SMS")
        } else {
            setStatus("Finished batch · \(completed) recovered · \(remaining) waiting")
        }
    }

    func retryPending() async {
        let candidates = SMSImportConsoleService.loadAICandidates()
        for candidate in candidates {
            let id = candidate.id.uuidString
            UserDefaults.standard.removeObject(forKey: retryPrefix + id)
            UserDefaults.standard.removeObject(forKey: nextRetryPrefix + id)
            UserDefaults.standard.removeObject(forKey: blockedPrefix + id)
        }
        UserDefaults.standard.removeObject(forKey: lastErrorKey)
        setStatus(candidates.isEmpty ? "Idle · No unresolved SMS" : "Manual retry started…")
        await processPending(force: true)
    }

    private func setStatus(_ value: String) {
        UserDefaults.standard.set(value, forKey: statusKey)
    }
}
