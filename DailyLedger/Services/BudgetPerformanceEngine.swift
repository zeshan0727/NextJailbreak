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

        switch cat {
        case "grocery", "groceries", "supermarket", "food groceries":
            return .grocery
        case "fuel", "petrol", "gasoline":
            return .fuel
        case "restaurants cafes", "restaurant", "restaurants", "dining", "dining out", "eat out", "eating out":
            return .eatOut
        default:
            // An unspecific category is NOT automatically "Other": users
            // must explicitly approve the classification for accurate reports.
            return .outside
        }
    }

    private static func canonical(_ raw: String) -> String {
        raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
