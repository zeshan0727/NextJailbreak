import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// iOS-native Files document picker to save an exported ledger JSON.
/// This is independent of an iCloud app-container entitlement: the user can
/// choose On My iPhone, iCloud Drive, or an installed Files provider.
struct LedgerBackupExportPicker: UIViewControllerRepresentable {
    let fileURL: URL
    let completion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: (Result<URL, Error>) -> Void
        init(completion: @escaping (Result<URL, Error>) -> Void) {
            self.completion = completion
        }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                completion(.failure(CocoaError(.fileWriteUnknown)))
                return
            }
            completion(.success(url))
        }
    }
}

/// Files / Drive document picker that reads an imported file while its
/// security-scoped permission is active. The caller gets owned Data, never a
/// stale security-scoped URL after the picker has been dismissed.
struct LedgerBackupImportPicker: UIViewControllerRepresentable {
    let completion: (Result<Data, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // The .json/.data/.content allow-list still greys out valid backups
        // whose Files-provider advertises a dynamic/unknown file type.
        // Allow every file to be selected; validate its actual bytes after
        // the selection. .item is the supertype for unknown file extensions.
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            asCopy: true
        )
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: (Result<Data, Error>) -> Void
        init(completion: @escaping (Result<Data, Error>) -> Void) {
            self.completion = completion
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(.failure(LedgerPickerError.cancelled))
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                completion(.failure(CocoaError(.fileReadNoSuchFile)))
                return
            }
            let result: Result<Data, Error> = Result {
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
                var fileCoordinationError: NSError?
                var readData: Data?
                var actualReadError: Error?
                NSFileCoordinator().coordinate(readingItemAt: url,
                                               options: [],
                                               error: &fileCoordinationError) { file in
                    do {
                        readData = try Data(contentsOf: file)
                    } catch {
                        actualReadError = error
                    }
                }
                if let fileCoordinationError { throw fileCoordinationError }
                if let actualReadError { throw actualReadError }
                guard let data = readData, !data.isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                guard data.count <= 50 * 1_024 * 1_024 else {
                    throw LedgerPickerError.tooLarge
                }
                return data
            }
            completion(result)
        }
    }
}

enum LedgerPickerError: LocalizedError {
    case cancelled
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "File selection cancelled."
        case .tooLarge:
            return "The selected file exceeds 50 MB. Choose a JSON backup instead of an archive."
        }
    }
}
