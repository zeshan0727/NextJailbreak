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
        var changed = false
        for (id, download) in downloads {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            let value = download.progress.fractionCompleted
            if value.isFinite && abs(value - items[index].progress) >= 0.01 {
                items[index].progress = max(0, min(value, 1))
                changed = true
            }
        }
        if changed { objectWillChange.send() }
    }

    func finished(_ download: WKDownload, library: MovieLibrary) {
        guard let id = id(for: download),
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        guard let filename = item.relativePath else { return }
        let destination = Self.folder.appendingPathComponent(filename)
        do {
            if item.isVideo {
                try library.addDownloadedFile(destination, suggestedName:
                    URL(fileURLWithPath: item.name).deletingPathExtension().lastPathComponent)
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
