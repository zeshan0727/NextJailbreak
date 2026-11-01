import Foundation

/// Read-only financial calculation for the separate Reports screen.
/// It does not mutate the budget plan or any financial transaction.
enum BudgetPerformanceBucket: Hashable {
    case fixed(UUID)
    case grocery
    case fuel
    case eatOut
    case other
    case outside
}

struct BudgetSpendRecord: Identifiable {
    let id: UUID
    let amount: Decimal
    let date: Date
    let category: String
    let vendor: String?
    let currencyCode: String
    /// Optional destination-account name used only to match generic transfers
    /// against fixed plans. The original recorded category is never overwritten.
    var fixedMatchHint: String? = nil
}

struct BudgetPerformanceExpense: Identifiable {
    let record: BudgetSpendRecord
    let bucket: BudgetPerformanceBucket
    let matchedManually: Bool

    var id: UUID { record.id }
}

struct BudgetPerformanceLine: Identifiable {
    let id: String
    let title: String
    let budget: Decimal
    let spent: Decimal

    var remaining: Decimal { max(0, budget - spent) }
    var overBudget: Decimal { max(0, spent - budget) }
    var spentPercentage: Double {
        guard budget > 0 else { return spent > 0 ? 100 : 0 }
        return NSDecimalNumber(decimal: spent / budget).doubleValue * 100
    }
}

struct BudgetRecordedCategory: Identifiable {
    let name: String
    let spent: Decimal
    let transactionCount: Int

    var id: String { name.lowercased() }
}

struct BudgetPerformanceResult {
    let cycle: DateInterval
    let lines: [BudgetPerformanceLine]
    let expenses: [BudgetPerformanceExpense]
    let unconvertedByCurrency: [String: Decimal]
    let usesSavedAllocations: Bool

    var totalBudget: Decimal { lines.reduce(0) { $0 + $1.budget } }
    var budgetSpent: Decimal { lines.reduce(0) { $0 + $1.spent } }
    var remaining: Decimal { max(0, totalBudget - budgetSpent) }
    var overBudget: Decimal { max(0, budgetSpent - totalBudget) }
    var outsideSpent: Decimal {
        expenses.filter { $0.bucket == .outside }.reduce(0) { $0 + $1.record.amount }
    }
    var actualSpent: Decimal { budgetSpent + outsideSpent }
    var remainingPercentage: Double {
        guard totalBudget > 0 else { return 0 }
        return max(0, min(100, NSDecimalNumber(decimal: remaining / totalBudget).doubleValue * 100))
    }
    var achievedPercentage: Double {
        guard totalBudget > 0 else { return 0 }
        return NSDecimalNumber(decimal: budgetSpent / totalBudget).doubleValue * 100
    }
    var outsideExpenses: [BudgetPerformanceExpense] { expenses.filter { $0.bucket == .outside } }
    // Fixed, essentials and Other with a planned allocation are automatically
    // categorized, so only genuine Outside Budget records require review.
    var unassignedExpenses: [BudgetPerformanceExpense] {
        expenses.filter { !$0.matchedManually && $0.bucket == .outside }
    }

    /// Read-only breakdown of the OTHER allocation by the category recorded on
    /// each transaction (e.g. Uber recorded as Taxi stays Taxi).
    var otherRecordedCategories: [BudgetRecordedCategory] { recordedCategories(in: .other) }
    var outsideRecordedCategories: [BudgetRecordedCategory] { recordedCategories(in: .outside) }

    private func recordedCategories(in bucket: BudgetPerformanceBucket) -> [BudgetRecordedCategory] {
        var totals: [String: Decimal] = [:]
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        for expense in expenses where expense.bucket == bucket {
            let raw = expense.record.category.trimmingCharacters(in: .whitespacesAndNewlines)
            let original = raw.isEmpty ? "Uncategorized" : raw
            let key = original.lowercased()
            if names[key] == nil { names[key] = original }
            totals[key, default: 0] += expense.record.amount
            counts[key, default: 0] += 1
        }
        return totals.keys.map { key in
            BudgetRecordedCategory(
                name: names[key] ?? key,
                spent: totals[key] ?? 0,
                transactionCount: counts[key] ?? 0
            )
        }.sorted {
            if $0.spent != $1.spent { return $0.spent > $1.spent }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    var assignedExpenses: [BudgetPerformanceExpense] {
        let pendingIDs = Set(unassignedExpenses.map(\.id))
        return expenses.filter { !pendingIDs.contains($0.id) }
    }
}

enum BudgetPerformanceEngine {
    static func build(
        plan: MonthlyFixedBudget,
        cycleStart: Date,
        expenses: [BudgetSpendRecord],
        currencyCode: String,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> BudgetPerformanceResult {
        let interval = BudgetCycle.interval(start: cycleStart, calendar: calendar)
        let fixed = plan.activeItems(.expense, in: interval.start)
        let saved = plan.savedAllocation(in: interval.start)
        let percentages = (
            grocery: saved?.groceryPercent ?? plan.groceryPercent,
            fuel: saved?.fuelPercent ?? plan.fuelPercent,
            eatOut: saved?.eatOutPercent ?? plan.eatOutPercent
        )
        let available = max(Decimal.zero, plan.available(in: interval.start))
        let otherPercent = max(0, 100 - percentages.grocery - percentages.fuel - percentages.eatOut)

        var collected: [BudgetPerformanceBucket: Decimal] = [:]
        var classified: [BudgetPerformanceExpense] = []
        var excluded: [String: Decimal] = [:]

        for expense in expenses where expense.amount > 0 &&
            expense.date >= interval.start &&
            expense.date < interval.end &&
            expense.date <= asOf {
            let expenseCurrency = expense.currencyCode.uppercased()
            guard expenseCurrency == currencyCode.uppercased() else {
                excluded[expenseCurrency, default: 0] += expense.amount
                continue
            }
            let assignment = plan.spendAssignments[expense.id]
            let suggested = bucketFor(expense: expense, assignment: assignment, fixed: fixed)
            // Categories without a planned allocation are outside budget,
            // even when their names are recognizable (e.g. Grocery with no
            // budget configured). Otherwise achievement would be fabricated.
            let bucket: BudgetPerformanceBucket
            switch suggested {
            case .fixed(let id):
                bucket = (fixed.first(where: { $0.id == id })?.amount ?? 0) > 0
                    ? suggested : .outside
            case .grocery:
                bucket = percentages.grocery > 0 && available > 0 ? suggested : .outside
            case .fuel:
                bucket = percentages.fuel > 0 && available > 0 ? suggested : .outside
            case .eatOut:
                bucket = percentages.eatOut > 0 && available > 0 ? suggested : .outside
            case .other:
                bucket = otherPercent > 0 && available > 0 ? suggested : .outside
            case .outside:
                bucket = .outside
            }
            collected[bucket, default: 0] += expense.amount
            classified.append(BudgetPerformanceExpense(
                record: expense, bucket: bucket, matchedManually: assignment != nil
            ))
        }
        classified.sort {
            if $0.record.date != $1.record.date { return $0.record.date > $1.record.date }
            return $0.record.id.uuidString < $1.record.id.uuidString
        }

        var lines = fixed.map { item in
            let bucket = BudgetPerformanceBucket.fixed(item.id)
            return BudgetPerformanceLine(
                id: "fixed:" + item.id.uuidString,
                title: item.title,
                budget: item.amount,
                spent: collected[bucket, default: 0]
            )
        }
        let variable: [(BudgetPerformanceBucket, String, Int)] = [
            (.grocery, "Grocery", percentages.grocery),
            (.fuel, "Fuel", percentages.fuel),
            (.eatOut, "Eat Out", percentages.eatOut),
            (.other, "Other Allocation", otherPercent)
        ]
        for (bucket, title, percent) in variable {
            lines.append(BudgetPerformanceLine(
                id: title, title: title,
                budget: available * Decimal(percent) / 100,
                spent: collected[bucket, default: 0]
            ))
        }

        return BudgetPerformanceResult(
            cycle: interval, lines: lines, expenses: classified,
            unconvertedByCurrency: excluded,
            usesSavedAllocations: saved != nil
        )
    }

    /// Internal account transfers do not count as spending. Money transferred
    /// from a bank into a Payments account is included in Budget Performance.
    static func includesInSpending(
        isExpense: Bool,
        isTransfer: Bool,
        sourceIsBank: Bool,
        sourceIsPayments: Bool,
        destinationIsPayments: Bool
    ) -> Bool {
        isExpense || (isTransfer && sourceIsBank && !sourceIsPayments && destinationIsPayments)
    }

    static func bucketFor(
        expense: BudgetSpendRecord,
        assignment: BudgetSpendAssignment?,
        fixed: [FixedPlanItem]
    ) -> BudgetPerformanceBucket {
        if let assignment {
            switch assignment.kind {
            case .fixed:
                guard let id = assignment.fixedItemID, fixed.contains(where: { $0.id == id }) else {
                    return .outside // inactive/removed fixed plan, never silently assign it
                }
                return .fixed(id)
            case .grocery: return .grocery
            case .fuel: return .fuel
            case .eatOut: return .eatOut
            case .other: return .other
            case .outside: return .outside
            }
        }

        let cat = canonical(expense.category)
        let fixedMatches = fixed.filter { canonical($0.title) == cat }
        if fixedMatches.count == 1 { return .fixed(fixedMatches[0].id) }

        // Only generic transfer labels may use a destination Payments account
        // as a fixed-expense hint. A meaningful original category such as Taxi
        // always wins, and is never silently replaced by an account/merchant.
        if ["", "transfer", "bank transfer", "payment", "payments"].contains(cat),
           let hint = expense.fixedMatchHint {
            let hinted = fixed.filter { canonical($0.title) == canonical(hint) }
            if hinted.count == 1 { return .fixed(hinted[0].id) }
        }

        switch cat {
        case "grocery", "groceries", "supermarket", "food groceries":
            return .grocery
        case "fuel", "petrol", "gasoline":
            return .fuel
        case "restaurants cafes", "restaurant", "restaurants", "dining", "dining out", "eat out", "eating out":
            return .eatOut
        default:
            // Unmatched spending is automatically categorized as Other / Unassigned.
            // build() still safeguards zero-allocation budgets.
            return .other
        }
    }

    private static func canonical(_ raw: String) -> String {
        raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
