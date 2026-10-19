import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ImportExportError: LocalizedError {
    case unsupportedFile
    case malformedCSV

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "This file is not a Next Ledger JSON backup or supported CSV file."
        case .malformedCSV:
            return "The CSV file does not contain recognizable transaction columns."
        }
    }
}

struct ImportPayload {
    let transactions: [LedgerTransaction]
    let accounts: [LedgerAccount]
    let settings: LedgerSettings?
    let fixedBudget: MonthlyFixedBudget?

    init(transactions: [LedgerTransaction], accounts: [LedgerAccount],
         settings: LedgerSettings?, fixedBudget: MonthlyFixedBudget? = nil) {
        self.transactions = transactions
        self.accounts = accounts
        self.settings = settings
        self.fixedBudget = fixedBudget
    }
}

enum ImportExportCodec {
    static func backupData(
        transactions: [LedgerTransaction],
        accounts: [LedgerAccount],
        settings: LedgerSettings,
        fixedBudget: MonthlyFixedBudget
    ) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(
            LedgerData(version: 3, transactions: transactions, accounts: accounts,
                       settings: settings, fixedBudget: fixedBudget)
        )) ?? Data()
    }

    static func csvData(transactions: [LedgerTransaction], accounts: [LedgerAccount]) -> Data {
        var rows = [[
            "id", "type", "amount", "destination_amount", "currency", "date",
            "category", "vendor", "details", "account", "transfer_account"
        ]]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let accountLookup = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        rows.append(contentsOf: transactions.map { item in
            let source = item.accountID.flatMap { accountLookup[$0] }
            let destination = item.destinationAccountID.flatMap { accountLookup[$0] }
            return [
                item.id.uuidString,
                item.type.rawValue,
                NSDecimalNumber(decimal: item.amount).stringValue,
                item.destinationAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
                source?.currencyCode ?? "",
                formatter.string(from: item.date),
                item.category,
                item.vendor ?? "",
                item.details,
                source?.name ?? "",
                destination?.name ?? ""
            ]
        })
        let text = rows.map { $0.map(escapeCSV).joined(separator: ",") }.joined(separator: "\n")
        return Data(text.utf8)
    }

    static func decode(url: URL) throws -> ImportPayload {
        let data = try Data(contentsOf: url)
        return try decode(data: data)
    }

    static func decode(data: Data) throws -> ImportPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let ledger = try? decoder.decode(LedgerData.self, from: data) {
            return ImportPayload(
                transactions: ledger.transactions,
                accounts: ledger.accounts,
                settings: ledger.settings,
                fixedBudget: ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["fixedBudget"] != nil
                    ? ledger.fixedBudget : nil
            )
        }
        if let transactions = try? decoder.decode([LedgerTransaction].self, from: data) {
            return ImportPayload(transactions: transactions, accounts: [], settings: nil)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportExportError.unsupportedFile
        }
        return try decodeCSV(text)
    }

    static func decodeCSV(_ text: String) throws -> ImportPayload {
        let rows = parseCSV(text)
        guard let first = rows.first else { throw ImportExportError.malformedCSV }
        let header = first.map(normalizedHeader)
        if header.contains("account"), header.contains("transfer account"), !header.contains("type") {
            return try decodeLegacyFinanceCSV(rows, header: header)
        }
        return try decodeDailyLedgerCSV(rows, header: header)
    }

    private static func decodeDailyLedgerCSV(
        _ rows: [[String]],
        header: [String]
    ) throws -> ImportPayload {
        guard let typeIndex = header.firstIndex(of: "type"),
              let amountIndex = header.firstIndex(of: "amount"),
              let dateIndex = header.firstIndex(of: "date") else {
            throw ImportExportError.malformedCSV
        }

        let idIndex = header.firstIndex(of: "id")
        let destinationAmountIndex = header.firstIndex(of: "destination amount")
        let currencyIndex = header.firstIndex(of: "currency")
        let categoryIndex = header.firstIndex(of: "category")
        let vendorIndex = header.firstIndex(of: "vendor") ?? header.firstIndex(of: "merchant")
        let detailsIndex = header.firstIndex(of: "details") ?? header.firstIndex(of: "note")
        let accountIndex = header.firstIndex(of: "account")
        let transferAccountIndex = header.firstIndex(of: "transfer account")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        var accountNames: [String] = []
        for row in rows.dropFirst() {
            for index in [accountIndex, transferAccountIndex].compactMap({ $0 }) where row.indices.contains(index) {
                let name = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty && !accountNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    accountNames.append(name)
                }
            }
        }
        let accounts = accountNames.map { importedAccount(named: $0) }
        let accountsByName = Dictionary(uniqueKeysWithValues: accounts.map { ($0.name.lowercased(), $0) })

        let transactions = rows.dropFirst().enumerated().compactMap { offset, row -> LedgerTransaction? in
            guard row.indices.contains(typeIndex), row.indices.contains(amountIndex), row.indices.contains(dateIndex),
                  let type = TransactionType(rawValue: row[typeIndex].lowercased()),
                  let amount = decimal(row[amountIndex]),
                  let date = formatter.date(from: row[dateIndex]) ?? fallbackFormatter.date(from: row[dateIndex]) else {
                return nil
            }
            let id = idIndex.flatMap { row.indices.contains($0) ? UUID(uuidString: row[$0]) : nil }
                ?? stableUUID("daily-ledger-csv|\(offset)|\(row.joined(separator: "|"))")
            let category = value(row, at: categoryIndex).nilIfBlank ?? (type == .transfer ? "Transfer" : "Other")
            let vendor = value(row, at: vendorIndex).nilIfBlank
            let details = value(row, at: detailsIndex)
            let sourceName = value(row, at: accountIndex).lowercased()
            let destinationName = value(row, at: transferAccountIndex).lowercased()
            let sourceAccount = accountsByName[sourceName]
            let destinationAccount = accountsByName[destinationName]
            let destinationAmount = value(row, at: destinationAmountIndex).nilIfBlank.flatMap(decimal)
            _ = value(row, at: currencyIndex)
            return LedgerTransaction(
                id: id,
                type: type,
                amount: abs(amount),
                date: date,
                category: category,
                vendor: vendor,
                details: details,
                accountID: sourceAccount?.id,
                destinationAccountID: destinationAccount?.id,
                destinationAmount: destinationAmount.map { abs($0) }
            )
        }
        return ImportPayload(transactions: transactions, accounts: accounts, settings: nil)
    }

    private struct LegacyRow {
        let index: Int
        let dateText: String
        let date: Date
        let description: String
        let category: String
        let payee: String
        let notes: String
        let tag: String
        let account: String
        let transferAccount: String
        let amount: Decimal

        var combinedDetails: String {
            var parts: [String] = []
            for value in [description, notes, tag] {
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && !parts.contains(cleaned) { parts.append(cleaned) }
            }
            return parts.joined(separator: "\n")
        }
    }

    private static func decodeLegacyFinanceCSV(
        _ rows: [[String]],
        header: [String]
    ) throws -> ImportPayload {
        guard let dateIndex = header.firstIndex(of: "date"),
              let accountIndex = header.firstIndex(of: "account"),
              let transferIndex = header.firstIndex(of: "transfer account"),
              let amountIndex = header.firstIndex(of: "amount") else {
            throw ImportExportError.malformedCSV
        }
        let descriptionIndex = header.firstIndex(of: "description")
        let categoryIndex = header.firstIndex(of: "category")
        let payeeIndex = header.firstIndex(of: "payee")
        let notesIndex = header.firstIndex(of: "notes")
        let tagIndex = header.firstIndex(of: "tag")
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let legacyRows = rows.dropFirst().enumerated().compactMap { offset, row -> LegacyRow? in
            guard row.indices.contains(dateIndex), row.indices.contains(accountIndex),
                  row.indices.contains(transferIndex), row.indices.contains(amountIndex),
                  let date = dateFormatter.date(from: row[dateIndex]),
                  let amount = decimal(row[amountIndex]) else { return nil }
            return LegacyRow(
                index: offset,
                dateText: row[dateIndex],
                date: date,
                description: value(row, at: descriptionIndex),
                category: value(row, at: categoryIndex),
                payee: value(row, at: payeeIndex),
                notes: value(row, at: notesIndex),
                tag: value(row, at: tagIndex),
                account: row[accountIndex].trimmingCharacters(in: .whitespacesAndNewlines),
                transferAccount: row[transferIndex].trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amount
            )
        }
        guard !legacyRows.isEmpty else { throw ImportExportError.malformedCSV }

        var accountNames: [String] = []
        for row in legacyRows {
            for name in [row.account, row.transferAccount] where !name.isEmpty {
                if !accountNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    accountNames.append(name)
                }
            }
        }
        let accounts = accountNames.map { importedAccount(named: $0) }
        let accountsByName = Dictionary(uniqueKeysWithValues: accounts.map { ($0.name.lowercased(), $0) })
        let transferRows = legacyRows.filter { !$0.transferAccount.isEmpty }
        let ordinaryRows = legacyRows.filter { $0.transferAccount.isEmpty }

        let groupedTransfers = Dictionary(grouping: transferRows) { row in
            let pair = [row.account.lowercased(), row.transferAccount.lowercased()].sorted().joined(separator: "|")
            return "\(row.dateText)|\(pair)"
        }
        var transactions: [LedgerTransaction] = ordinaryRows.map { row in
            let type: TransactionType = row.amount < 0 ? .expense : .income
            return LedgerTransaction(
                id: stableUUID("legacy-row|\(row.index)|\(row.dateText)|\(row.account)|\(row.amount)"),
                type: type,
                amount: abs(row.amount),
                date: row.date,
                category: row.category.isEmpty ? "Other" : row.category,
                vendor: row.payee.nilIfBlank,
                details: row.combinedDetails,
                accountID: accountsByName[row.account.lowercased()]?.id
            )
        }

        for group in groupedTransfers.values {
            var negatives = group.filter { $0.amount < 0 }.sorted { $0.index < $1.index }
            var positives = group.filter { $0.amount >= 0 }.sorted { $0.index < $1.index }
            while !negatives.isEmpty && !positives.isEmpty {
                let source = negatives.removeFirst()
                let destinationIndex = positives.firstIndex(where: {
                    $0.account.caseInsensitiveCompare(source.transferAccount) == .orderedSame &&
                    $0.transferAccount.caseInsensitiveCompare(source.account) == .orderedSame
                }) ?? 0
                let destination = positives.remove(at: destinationIndex)
                transactions.append(transferTransaction(
                    source: source,
                    destination: destination,
                    accountsByName: accountsByName
                ))
            }
            for row in negatives + positives {
                let sourceName = row.amount < 0 ? row.account : row.transferAccount
                let destinationName = row.amount < 0 ? row.transferAccount : row.account
                transactions.append(LedgerTransaction(
                    id: stableUUID("legacy-unpaired-transfer|\(row.index)|\(row.dateText)"),
                    type: .transfer,
                    amount: abs(row.amount),
                    date: row.date,
                    category: "Transfer",
                    details: row.combinedDetails,
                    accountID: accountsByName[sourceName.lowercased()]?.id,
                    destinationAccountID: accountsByName[destinationName.lowercased()]?.id,
                    destinationAmount: abs(row.amount)
                ))
            }
        }
        transactions.sort { $0.date > $1.date }
        return ImportPayload(transactions: transactions, accounts: accounts, settings: nil)
    }

    private static func transferTransaction(
        source: LegacyRow,
        destination: LegacyRow,
        accountsByName: [String: LedgerAccount]
    ) -> LedgerTransaction {
        let details = source.combinedDetails.isEmpty ? destination.combinedDetails : source.combinedDetails
        return LedgerTransaction(
            id: stableUUID("legacy-transfer|\(source.index)|\(destination.index)|\(source.dateText)"),
            type: .transfer,
            amount: abs(source.amount),
            date: source.date,
            category: "Transfer",
            details: details,
            accountID: accountsByName[source.account.lowercased()]?.id,
            destinationAccountID: accountsByName[destination.account.lowercased()]?.id,
            destinationAmount: abs(destination.amount)
        )
    }

    private static func importedAccount(named name: String) -> LedgerAccount {
        let key = name.lowercased()
        let qatar = ["cash", "debit card", "credit card", "investment account"]
        let pakistan = ["hbl", "ubl", "jazz cash", "easy paisa", "sada pay", "savings account"]
        let payments = [
            "rashid", "car loan", "laila", "ami", "adnan", "amara mom", "others",
            "cbq loan", "junaid", "amara gold", "fahad", "khuram", "nomi bhai",
            "naeem", "rizwan", "shahbaz chuchu", "umar sheikh"
        ]
        let assets = ["vehicle", "mobiles", "property shop", "visa uk"]
        let qarAdditional = ["car loan", "adnan", "cbq loan", "khuram", "vehicle", "mobiles", "amara", "trading", "saving"]

        let group: AccountGroup
        if qatar.contains(key) { group = .qatar }
        else if pakistan.contains(key) { group = .pakistan }
        else if payments.contains(key) { group = .payments }
        else if assets.contains(key) { group = .assets }
        else { group = .other }

        let currency: String
        if key.contains("usd") { currency = "USD" }
        else if qatar.contains(key) || qarAdditional.contains(key) { currency = "QAR" }
        else { currency = "PKR" }

        let icon: String
        if key.contains("cash") { icon = "banknote.fill" }
        else if key.contains("loan") || key.contains("vehicle") { icon = "car.fill" }
        else if key.contains("mobile") { icon = "iphone.gen3" }
        else if key.contains("property") { icon = "house.fill" }
        else if group == .assets { icon = "building.columns.fill" }
        else if group == .payments { icon = "person.2.fill" }
        else { icon = "creditcard.fill" }

        return LedgerAccount(
            id: stableUUID("legacy-account|\(key)"),
            name: name,
            currencyCode: currency,
            group: group,
            icon: icon
        )
    }

    private static func stableUUID(_ source: String) -> UUID {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_111
        for byte in source.utf8 {
            first ^= UInt64(byte)
            first &*= 1_099_511_628_211
            second = (second &* 1_099_511_628_211) ^ UInt64(byte &+ 31)
        }
        let hex = String(format: "%016llx%016llx", first, second)
        let value = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-5\(hex.dropFirst(13).prefix(3))-a\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: value) ?? UUID()
    }

    private static func normalizedHeader(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decimal(_ value: String) -> Decimal? {
        Decimal(
            string: value.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func value(_ row: [String], at index: Int?) -> String {
        guard let index, row.indices.contains(index) else { return "" }
        return row[index]
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !inQuotes {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}

private extension String {
    var nilIfBlank: String? {
        let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
