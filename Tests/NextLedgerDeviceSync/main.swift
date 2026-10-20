import Foundation

struct Record: Identifiable, Equatable {
    let id: UUID
    let name: String
}

func expect(_ condition: @autoclosure () -> Bool, _ reason: String) {
    precondition(condition(), reason)
}

let a = UUID(), b = UUID(), c = UUID()
let first = Record(id: a, name: "device A transaction")
let second = Record(id: b, name: "device B transaction")
let updated = Record(id: a, name: "conflicting edited value")
let third = Record(id: c, name: "new account")

let initial = SafeDeviceMerge.plan(local: [first], remote: [second, second])
expect(initial.additions == [second], "Must add only one copy of repeated remote UUID")
expect(initial.conflicts == 0, "Distinct IDs do not conflict")

let collision = SafeDeviceMerge.plan(local: [first, second], remote: [updated, second, third])
expect(collision.additions == [third], "Must preserve existing UUID values and add new UUID only")
expect(collision.conflicts == 1, "Different edits with same UUID must be reported")
expect(first.name == "device A transaction", "Must never overwrite an existing transaction")

let noRemote = SafeDeviceMerge.plan(local: [first], remote: [Record]())
expect(noRemote.additions.isEmpty && noRemote.conflicts == 0, "Empty remote must not erase data")

let same = SafeDeviceMerge.plan(local: [first], remote: [first])
expect(same.additions.isEmpty && same.conflicts == 0, "Identical history is idempotent")
print("Next Ledger Device Sync: 4 non-destructive reconciliation cases passed.")
