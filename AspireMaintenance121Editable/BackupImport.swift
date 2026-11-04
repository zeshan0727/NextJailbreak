import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Reliable backup import

/// Uses UIDocumentPicker in copy mode instead of SwiftUI's security-scoped file importer.
/// Copy mode is more reliable with iCloud Drive and third-party Files providers on iOS 16.
struct AspireBackupDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Accept any Files item and validate its contents after selection. This prevents valid
        // Aspire JSON backups being disabled by providers that report a generic UTType.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

enum AspireBackupFileError: LocalizedError {
    case emptyFile
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected backup file is empty."
        case .unreadableFile:
            return "The selected file could not be read. Please copy it to On My iPhone or iCloud Drive and try again."
        }
    }
}

enum AspireBackupFileReader {
    static func readData(from url: URL) throws -> Data {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        var coordinatedError: NSError?
        var readError: Error?
        var result: Data?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinatedError) { coordinatedURL in
            do {
                result = try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
            } catch {
                readError = error
            }
        }

        if let readError { throw readError }
        if let coordinatedError { throw coordinatedError }
        guard var data = result else { throw AspireBackupFileError.unreadableFile }
        guard !data.isEmpty else { throw AspireBackupFileError.emptyFile }

        // Some share/export tools prepend a UTF-8 BOM. JSONDecoder does not need it.
        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            data.removeFirst(3)
        }
        return data
    }
}
