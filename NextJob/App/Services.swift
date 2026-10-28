import Foundation
import MessageUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MailAttachment {
    let data: Data
    let mimeType: String
    let fileName: String
}

struct MailDraft: Identifiable {
    let id = UUID()
    let recipients: [String]
    let subject: String
    let body: String
    let attachments: [MailAttachment]
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct PreviewPayload: Identifiable {
    let id = UUID()
    let url: URL
}

enum DocumentPickerError: Error {
    case cancelled
}

struct DocumentPicker: UIViewControllerRepresentable {
    let allowsMultipleSelection: Bool
    let completion: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<[URL], Error>) -> Void

        init(completion: @escaping (Result<[URL], Error>) -> Void) {
            self.completion = completion
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            completion(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(.failure(DocumentPickerError.cancelled))
        }
    }
}

struct MailComposer: UIViewControllerRepresentable {
    let draft: MailDraft
    let completion: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(draft.recipients.filter { !$0.isEmpty })
        composer.setSubject(draft.subject)
        composer.setMessageBody(draft.body, isHTML: false)
        for attachment in draft.attachments {
            composer.addAttachmentData(
                attachment.data,
                mimeType: attachment.mimeType,
                fileName: attachment.fileName
            )
        }
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let completion: () -> Void

        init(completion: @escaping () -> Void) {
            self.completion = completion
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            completion()
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct ZipEntry {
    let name: String
    let data: Data
}

enum StoredZipWriter {
    static func write(entries: [ZipEntry], to destination: URL) throws {
        guard entries.count <= Int(UInt16.max) else { throw ZipError.tooManyFiles }

        var output = Data()
        var centralDirectory = Data()
        var offsets: [UInt32] = []
        let stamp = dosTimestamp(Date())

        for entry in entries {
            let normalizedName = entry.name.replacingOccurrences(of: "\\", with: "/")
            let nameData = Data(normalizedName.utf8)
            guard nameData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  output.count <= Int(UInt32.max) else {
                throw ZipError.fileTooLarge
            }

            let crc = CRC32.checksum(entry.data)
            offsets.append(UInt32(output.count))

            output.appendUInt32(0x04034B50)
            output.appendUInt16(20)
            output.appendUInt16(0x0800)
            output.appendUInt16(0)
            output.appendUInt16(stamp.time)
            output.appendUInt16(stamp.date)
            output.appendUInt32(crc)
            output.appendUInt32(UInt32(entry.data.count))
            output.appendUInt32(UInt32(entry.data.count))
            output.appendUInt16(UInt16(nameData.count))
            output.appendUInt16(0)
            output.append(nameData)
            output.append(entry.data)
        }

        for (index, entry) in entries.enumerated() {
            let normalizedName = entry.name.replacingOccurrences(of: "\\", with: "/")
            let nameData = Data(normalizedName.utf8)
            let crc = CRC32.checksum(entry.data)

            centralDirectory.appendUInt32(0x02014B50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0x0800)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(stamp.time)
            centralDirectory.appendUInt16(stamp.date)
            centralDirectory.appendUInt32(crc)
            centralDirectory.appendUInt32(UInt32(entry.data.count))
            centralDirectory.appendUInt32(UInt32(entry.data.count))
            centralDirectory.appendUInt16(UInt16(nameData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(offsets[index])
            centralDirectory.append(nameData)
        }

        guard output.count <= Int(UInt32.max), centralDirectory.count <= Int(UInt32.max) else {
            throw ZipError.fileTooLarge
        }

        let centralOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.appendUInt32(0x06054B50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(UInt32(centralDirectory.count))
        output.appendUInt32(centralOffset)
        output.appendUInt16(0)

        try output.write(to: destination, options: .atomic)
    }

    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let year = max(1980, min(2107, components.year ?? 1980))
        let month = max(1, min(12, components.month ?? 1))
        let day = max(1, min(31, components.day ?? 1))
        let hour = max(0, min(23, components.hour ?? 0))
        let minute = max(0, min(59, components.minute ?? 0))
        let second = max(0, min(59, components.second ?? 0))

        let time = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (time, dosDate)
    }
}

enum ZipError: LocalizedError {
    case tooManyFiles
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .tooManyFiles: return "This job contains too many files for one ZIP package."
        case .fileTooLarge: return "One or more files are too large for the ZIP package."
        }
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { buffer in
            append(contentsOf: buffer)
        }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { buffer in
            append(contentsOf: buffer)
        }
    }
}
