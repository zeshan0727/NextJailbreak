import Foundation
import Combine
import SwiftUI

/// Owns live sync state. AspireStore remains the only writer of the on-device database.
@MainActor
final class AspireDeviceSyncController: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var status: String
    @Published private(set) var lastSyncAt: Date?

    private enum Defaults {
        static let enabled = "aspire.device.sync.enabled"
        static let lastAt = "aspire.device.sync.lastAt"
    }

    private weak var store: AspireStore?
    private var subscription: AnyCancellable?
    private let ledgerURL: URL
    private var ledger: AspireSyncLedger
    private var isObservingCloud = false
    private var applyingRemoteData = false
    private var pendingLocalScan: DispatchWorkItem?
    private var pendingPublish: DispatchWorkItem?

    init() {
        enabled = UserDefaults.standard.bool(forKey: Defaults.enabled)
        status = enabled ? "Not connected" : "Off"
        lastSyncAt = UserDefaults.standard.object(forKey: Defaults.lastAt) as? Date

        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("AspireMaintenance", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ledgerURL = directory.appendingPathComponent("aspire-device-sync-ledger.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let bytes = try? Data(contentsOf: ledgerURL),
           let previous = try? decoder.decode(AspireSyncLedger.self, from: bytes) {
            ledger = previous
        } else {
            ledger = AspireSyncLedger(deviceID: UUID().uuidString.lowercased())
        }
    }

    func attach(_ store: AspireStore) {
        guard self.store !== store else { return }
        self.store = store
        subscription = store.$data.dropFirst().sink { [weak self] _ in
            guard let self, !self.applyingRemoteData else { return }
            self.queueLocalScan()
        }
        start()
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: Defaults.enabled)
        if value {
            start()
        } else {
            pendingPublish?.cancel()
            pendingLocalScan?.cancel()
            isObservingCloud = false
            AspireDeviceSyncService.shared.stop()
            status = "Off"
        }
    }

    func start() {
        guard enabled, store != nil, !isObservingCloud else { return }
        isObservingCloud = true
        status = "Connecting to iCloud…"
        AspireDeviceSyncService.shared.start { [weak self] result in
            guard let self, self.enabled else { return }
            switch result {
            case .success(let scan): self.receiveCloudScan(scan)
            case .failure(let error): self.status = error.localizedDescription
            }
        }
    }

    func syncNow() {
        guard enabled else { return }
        start()
        status = "Checking for updates…"
        AspireDeviceSyncService.shared.refresh()
        if ledger.initialized { publishNow() }
    }

    func enterBackground() {
        guard enabled else { return }
        pendingPublish?.cancel()
        if ledger.initialized { publishNow() }
        isObservingCloud = false
        AspireDeviceSyncService.shared.stop()
    }

    private func queueLocalScan() {
        guard enabled, ledger.initialized else { return }
        pendingLocalScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.captureLocalEdits() }
        pendingLocalScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func captureLocalEdits() {
        guard enabled, ledger.initialized, !applyingRemoteData,
              let store else { return }
        do {
            let current = try AspireSyncCodec.flatten(store.data)
            let keys = Set(current.keys).union(ledger.lastObserved.keys)
            var changed = false
            for key in keys.sorted() where current[key] != ledger.lastObserved[key] {
                recordLocalChange(key, json: current[key])
                changed = true
            }
            ledger.lastObserved = current
            try saveLedger()
            if changed { queuePublish() }
        } catch {
            status = "Sync paused: \(error.localizedDescription)"
        }
    }

    private func recordLocalChange(_ key: String, json: String?) {
        ledger.sequence += 1
        let item = AspireSyncChange(
            deviceID: ledger.deviceID, changedAt: Date(),
            sequence: ledger.sequence, removed: json == nil, jsonValue: json
        )
        ledger.localChanges[key] = item
        ledger.winners[key] = item
    }

    private func receiveCloudScan(_ scan: AspireSyncScan) {
        guard let store else { return }
        // Metadata can arrive before file contents. Waiting avoids an empty-cloud
        // false positive and prevents an older device from replacing recent changes.
        if scan.downloadsPending {
            status = "Downloading changes…"
            return
        }

        do {
            var remote: [String: AspireSyncChange] = [:]
            for journal in scan.documents {
                for (key, item) in journal.changes {
                    if let earlier = remote[key], !item.supersedes(earlier) { continue }
                    remote[key] = item
                }
            }

            if !ledger.initialized {
                let before = try AspireSyncCodec.flatten(store.data)
                let toApply = remote.filter { key, item in
                    item.removed ? before[key] != nil : before[key] != item.jsonValue
                }
                if !toApply.isEmpty {
                    let merged = try AspireSyncCodec.applying(toApply, to: store.data)
                    try importMergedData(merged, into: store)
                }

                ledger.winners = remote
                ledger.initialized = true
                let present = try AspireSyncCodec.flatten(store.data)
                // Seed only records that are not already represented in the cloud.
                // Remote tombstones are honored and never resurrected here.
                for key in present.keys.sorted() where remote[key] == nil {
                    recordLocalChange(key, json: present[key])
                }
                ledger.lastObserved = present
                try saveLedger()
                if !ledger.localChanges.isEmpty { queuePublish() }
            } else {
                // Include pending offline edits before resolving incoming versions.
                captureLocalEdits()
                let newer = remote.filter { key, item in
                    guard let known = ledger.winners[key] else { return true }
                    return item.supersedes(known)
                }
                if !newer.isEmpty {
                    let current = try AspireSyncCodec.flatten(store.data)
                    let actual = newer.filter { key, item in
                        item.removed ? current[key] != nil : current[key] != item.jsonValue
                    }
                    if !actual.isEmpty {
                        let merged = try AspireSyncCodec.applying(actual, to: store.data)
                        try importMergedData(merged, into: store)
                    }
                    for (key, item) in newer { ledger.winners[key] = item }
                    ledger.lastObserved = try AspireSyncCodec.flatten(store.data)
                    try saveLedger()
                }
            }
            lastSyncAt = Date()
            UserDefaults.standard.set(lastSyncAt, forKey: Defaults.lastAt)
            status = "Connected • changes checked"
        } catch {
            status = "Sync paused: \(error.localizedDescription)"
        }
    }

    private func importMergedData(_ merged: AspireData, into store: AspireStore) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        // Keep a private safety copy before any cloud-originated replacement.
        if store.hasMeaningfulUserData { try saveSafetyCopy(store.exportData()) }
        applyingRemoteData = true
        defer { applyingRemoteData = false }
        try store.importData(encoder.encode(merged))
        store.performAutomaticCloudBackup(reason: "Device sync")
    }

    private func saveSafetyCopy(_ source: @autoclosure () throws -> Data) throws {
        let folder = ledgerURL.deletingLastPathComponent()
            .appendingPathComponent("PreSyncSafety", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent(
            "before-sync-\(Int(Date().timeIntervalSince1970 * 1000)).json"
        )
        try source().write(to: path, options: [.atomic, .completeFileProtectionUnlessOpen])
        let files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
          .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for expired in files.dropFirst(5) { try? FileManager.default.removeItem(at: expired) }
    }

    private func saveLedger() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(ledger).write(
            to: ledgerURL, options: [.atomic, .completeFileProtectionUnlessOpen]
        )
    }

    private func queuePublish() {
        guard enabled, ledger.initialized, !ledger.localChanges.isEmpty else { return }
        pendingPublish?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.publishNow() }
        pendingPublish = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func publishNow() {
        guard enabled, ledger.initialized, !ledger.localChanges.isEmpty else { return }
        let journal = AspireSyncJournal(
            deviceID: ledger.deviceID, changes: ledger.localChanges
        )
        AspireDeviceSyncService.shared.publish(journal) { [weak self] result in
            guard let self, self.enabled else { return }
            switch result {
            case .success: self.status = "Changes saved to iCloud Drive"
            case .failure(let error): self.status = "Upload pending: \(error.localizedDescription)"
            }
        }
    }
}
