import Foundation
import WebKit
import SwiftUI

struct BrowserDownloadItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var status: String
    var date: Date
    var relativePath: String?
    var progress: Double
    var isVideo: Bool
}

@MainActor
final class BrowserDownloadStore: ObservableObject {
    @Published private(set) var items: [BrowserDownloadItem] = []
    @Published var notice: String?
    private let storeKey = "nextcast.browser.downloads.v1"
    private var downloads: [UUID: WKDownload] = [:]
    private var samples: [UUID: (Date, Int64, Double)] = [:]
    private var speeds: [UUID: Double] = [:]

    static var folder: URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("Browser Downloads", isDirectory: true)
    }

    init() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let decoded = try? JSONDecoder().decode([BrowserDownloadItem].self, from: data) {
            // Interrupted downloads cannot be resumed after relaunch in this version.
            items = decoded.map { item in
                var copy = item
                if copy.status == "Downloading" { copy.status = "Interrupted" }
                return copy
            }
        }
    }

    func destination(for suggestedFilename: String) -> URL {
        let filename = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        let clean = filename.isEmpty ? "download.bin" : filename
        return Self.folder.appendingPathComponent(UUID().uuidString + "-" + clean)
    }

    @discardableResult
    func begin(_ download: WKDownload, filename: String, destination: URL) -> UUID {
        let id = UUID()
        downloads[id] = download
        items.insert(BrowserDownloadItem(id: id, name: filename, status: "Downloading",
              date: Date(), relativePath: destination.lastPathComponent,
              progress: 0, isVideo: VideoFormats.supported(destination)), at: 0)
        notice = "Download started: \(filename)"
        save()
        return id
    }

    func id(for download: WKDownload) -> UUID? {
        downloads.first(where: { $0.value === download })?.key
    }

    func tick() {
        let now = Date()
        var changed = false
        for (id, download) in downloads {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            let progress = download.progress
            let fraction = progress.fractionCompleted
            let bytes = max(Int64(0), progress.completedUnitCount)
            if fraction.isFinite, fraction >= 0, fraction <= 1 {
                items[index].progress = fraction
                changed = true
            }
            if let previous = samples[id], now.timeIntervalSince(previous.0) >= 0.8 {
                let newSpeed = max(0, Double(bytes - previous.1) / now.timeIntervalSince(previous.0))
                speeds[id] = previous.2 > 0 ? 0.5 * previous.2 + 0.5 * newSpeed : newSpeed
                samples[id] = (now, bytes, speeds[id] ?? 0)
                changed = true
            } else if samples[id] == nil {
                samples[id] = (now, bytes, 0)
            }
        }
        if changed { objectWillChange.send() }
    }

    func speedLabel(_ item: BrowserDownloadItem) -> String {
        guard let bytes = speeds[item.id], bytes > 0 else { return "Calculating speed" }
        return String(format: "%.2f MB/s", bytes / 1_000_000)
    }

    func remainingLabel(_ item: BrowserDownloadItem) -> String {
        guard let task = downloads[item.id],
              task.progress.totalUnitCount > 0,
              let bytes = speeds[item.id], bytes > 0 else { return "ETA unknown" }
        let rem = max(Int64(0), task.progress.totalUnitCount - task.progress.completedUnitCount)
        let seconds = Int(Double(rem) / bytes)
        if seconds >= 3600 { return String(format: "%dh %02dm left", seconds/3600, seconds%3600/60) }
        if seconds >= 60 { return String(format: "%dm %02ds left", seconds/60, seconds%60) }
        return "\(seconds)s left"
    }

    func finished(_ download: WKDownload, library: MovieLibrary) {
        guard let id = id(for: download),
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        guard let filename = item.relativePath else { return }
        let destination = Self.folder.appendingPathComponent(filename)
        do {
            if let video = try VideoFileInspector.preparedVideoURL(
                destination, name: item.name
            ) {
                // Save the renamed location before moving to Movies so a
                // failed import can be retried without losing the file.
                items[index].relativePath = video.lastPathComponent
                try library.addDownloadedFile(
                    video, suggestedName: VideoFileInspector.cleanTitle(item.name)
                )
                items[index].status = "Added to Movies"
                items[index].relativePath = nil
            } else {
                items[index].status = "Saved to Downloads"
            }
            items[index].progress = 1
            notice = "Downloaded: \(item.name)"
        } catch {
            items[index].status = "Save failed: \(error.localizedDescription)"
            notice = "Could not save \(item.name)"
        }
        downloads.removeValue(forKey: id)
        save()
    }

    func moveToMovies(_ item: BrowserDownloadItem, library: MovieLibrary) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let file = fileURL(items[index]) else {
            notice = "Downloaded file is no longer available."
            return
        }
        do {
            guard let video = try VideoFileInspector.preparedVideoURL(file, name: item.name) else {
                notice = "This file is not recognized as a movie."
                return
            }
            items[index].relativePath = video.lastPathComponent
            try library.addDownloadedFile(
                video, suggestedName: VideoFileInspector.cleanTitle(item.name)
            )
            items[index].relativePath = nil
            items[index].status = "Added to Movies"
            notice = "Added \(item.name) to Movies."
            save()
        } catch {
            notice = "Cannot import movie: \(error.localizedDescription)"
            save()
        }
    }

    func failed(_ download: WKDownload, error: Error) {
        guard let id = id(for: download),
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = "Failed: \(error.localizedDescription)"
        downloads.removeValue(forKey: id)
        notice = "Download failed"
        save()
    }

    func cancel(_ item: BrowserDownloadItem) {
        downloads[item.id]?.cancel(nil)
        downloads.removeValue(forKey: item.id)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].status = "Cancelled"
        }
        save()
    }

    func fileURL(_ item: BrowserDownloadItem) -> URL? {
        guard let name = item.relativePath else { return nil }
        let url = Self.folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func delete(_ item: BrowserDownloadItem) {
        if let url = fileURL(item) { try? FileManager.default.removeItem(at: url) }
        downloads[item.id]?.cancel(nil)
        downloads.removeValue(forKey: item.id)
        items.removeAll { $0.id == item.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }
}
