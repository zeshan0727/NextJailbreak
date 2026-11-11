import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// A dedicated UIKit document picker. iOS shows a single-tap selection when
/// allowsMultipleSelection is false; the previous app always requested
/// multi-select, which requires an extra Open confirmation in Files.
struct ReliableVideoPicker: UIViewControllerRepresentable {
    var multiple: Bool = false
    var didSelect: ([URL]) -> Void
    var didCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(didSelect: didSelect, didCancel: didCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // .data is a broad type, including containers without a built-in UTType
        // such as MKV. Explicit movie permits videos from some cloud providers.
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.data, .movie, .audiovisualContent],
            asCopy: true
        )
        picker.allowsMultipleSelection = multiple
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let didSelect: ([URL]) -> Void
        let didCancel: () -> Void

        init(didSelect: @escaping ([URL]) -> Void, didCancel: @escaping () -> Void) {
            self.didSelect = didSelect
            self.didCancel = didCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // The picker creates local readable copies before invoking this
            // callback. Keep the selection callback on main so the library
            // can immediately enqueue an import and display its progress.
            DispatchQueue.main.async { [didSelect] in
                didSelect(urls)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            DispatchQueue.main.async { [didCancel] in didCancel() }
        }
    }
}
