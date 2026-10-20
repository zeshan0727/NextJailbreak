import Foundation

/// Non-destructive planning for synced records. Identical IDs are never
/// inserted twice. Differently edited copies are surfaced as conflicts.
enum SafeDeviceMerge {
    static func plan<Record: Identifiable & Equatable>(
        local: [Record], remote: [Record]
    ) -> (additions: [Record], conflicts: Int) where Record.ID: Hashable {
        let indexed = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { original, _ in original })
        var visited = Set<Record.ID>()
        var additions = [Record]()
        var conflicts = 0
        for record in remote {
            guard visited.insert(record.id).inserted else { continue }
            if let prior = indexed[record.id] {
                if prior != record { conflicts += 1 }
            } else {
                additions.append(record)
            }
        }
        return (additions, conflicts)
    }
}
