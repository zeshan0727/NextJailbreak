import Foundation

struct LedgerChatSearchResult {
    let response: String
    let matched: Bool
    let transactionIDs: [UUID]
}

enum LedgerChatSearch {
    @MainActor
    static func run(query: String, store: LedgerStore, force: Bool = false) -> LedgerChatSearchResult {
        let lowered = query.lowercased()
        let triggers = ["find", "search", "show", "list", "database", "transaction", "spent", "paid", "received", "how much"]
        let amount = extractAmount(from: query)
        let keywords = searchKeywords(from: query)
        guard force || amount != nil || triggers.contains(where: lowered.contains) else {
            return LedgerChatSearchResult(response: "", matched: false, transactionIDs: [])
        }

        let interval = dateInterval(for: lowered)
        let matches = store.transactions.filter { transaction in
            if let interval, !interval.contains(transaction.date) { return false }
            if let amount, transaction.amount != amount { return false }
            if (lowered.contains("expense") || lowered.contains("spent")), transaction.type != .expense { return false }
            if (lowered.contains("income") || lowered.contains("received")), transaction.type != .income { return false }
            guard !keywords.isEmpty else { return true }
            let account = store.account(withID: transaction.accountID)?.name ?? ""
            let text = [transaction.category, transaction.vendor ?? "", transaction.details, account]
                .joined(separator: " ")
                .lowercased()
            return keywords.allSatisfy { text.contains($0) }
        }

        guard !matches.isEmpty else {
            let target = amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? keywords.joined(separator: " ")
            return LedgerChatSearchResult(
                response: "No transactions matched “\(target)”\(periodDescription(lowered)).",
                matched: true,
                transactionIDs: []
            )
        }

        let totals = Dictionary(grouping: matches) {
            store.account(withID: $0.accountID)?.currencyCode ?? store.currencyCode
        }
        .map { currency, items in
            "\(currency) \(NSDecimalNumber(decimal: items.reduce(0) { $0 + $1.amount }).stringValue)"
        }
        .sorted()
        .joined(separator: ", ")

        let lines = matches.prefix(20).map { transaction in
            let currency = store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
            let account = store.account(withID: transaction.accountID)?.name ?? "Unknown account"
            let vendor = transaction.vendor?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = vendor?.isEmpty == false ? vendor! : transaction.category
            return "• \(transaction.date.formatted(date: .abbreviated, time: .omitted)) · \(currency) \(NSDecimalNumber(decimal: transaction.amount).stringValue) · \(label) · \(account)"
        }
        let remainder = matches.count > 20 ? "\n…and \(matches.count - 20) more matches. Refine your search to narrow it down." : ""
        return LedgerChatSearchResult(
            response: "Found \(matches.count) transaction\(matches.count == 1 ? "" : "s") totaling \(totals):\n\(lines.joined(separator: "\n"))\(remainder)",
            matched: true,
            transactionIDs: Array(matches.prefix(20).map(\.id))
        )
    }

    private static func extractAmount(from text: String) -> Decimal? {
        let pattern = #"(?<![A-Za-z])\d[\d,]*(?:\.\d{1,2})?"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range, in: text) else { return nil }
        return Decimal(
            string: String(text[range]).replacingOccurrences(of: ",", with: ""),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func searchKeywords(from text: String) -> [String] {
        let ignored = Set([
            "find", "finding", "search", "show", "list", "me", "my", "transaction", "transactions",
            "data", "database", "amount", "specific", "for", "with", "from", "of", "in", "on", "the", "a",
            "this", "last", "month", "today", "week", "how", "much", "did", "i", "spend", "spent", "paid", "received",
            "payment", "payments", "expense", "expenses", "income", "loan", "loans"
        ])
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && Decimal(string: $0) == nil && !ignored.contains($0) }
    }

    private static func dateInterval(for text: String) -> DateInterval? {
        let calendar = Calendar.current
        if text.contains("today") { return calendar.dateInterval(of: .day, for: Date()) }
        if text.contains("this week") { return calendar.dateInterval(of: .weekOfYear, for: Date()) }
        if text.contains("this month") { return calendar.dateInterval(of: .month, for: Date()) }
        if text.contains("last month") {
            let previous = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            return calendar.dateInterval(of: .month, for: previous)
        }
        return nil
    }

    private static func periodDescription(_ text: String) -> String {
        if text.contains("today") { return " today" }
        if text.contains("this week") { return " this week" }
        if text.contains("this month") { return " this month" }
        if text.contains("last month") { return " last month" }
        return ""
    }
}
