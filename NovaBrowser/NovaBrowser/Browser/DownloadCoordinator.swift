import Foundation
import WebKit

final class DownloadCoordinator: NSObject, WKDownloadDelegate {
    private var destinations: [ObjectIdentifier: URL] = [:]
    var onSaved: ((DownloadEntry) -> Void)?
    var onFailed: ((String) -> Void)?

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let baseFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: baseFolder, withIntermediateDirectories: true)
            let cleaned = (suggestedFilename as NSString).lastPathComponent
            let filename = cleaned.isEmpty || cleaned == "." ? "download" : cleaned
            var destination = baseFolder.appendingPathComponent(filename)
            let stem = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            var index = 1
            while FileManager.default.fileExists(atPath: destination.path) {
                let suffix = ext.isEmpty ? "" : ".\(ext)"
                destination = baseFolder.appendingPathComponent("\(stem)-\(index)\(suffix)")
                index += 1
            }
            destinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        } catch {
            onFailed?("Cannot create Downloads folder: \(error.localizedDescription)")
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let destination = destinations.removeValue(forKey: ObjectIdentifier(download)) {
            onSaved?(DownloadEntry(filename: destination.lastPathComponent, savedPath: destination.path))
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
        onFailed?(error.localizedDescription)
    }
}
