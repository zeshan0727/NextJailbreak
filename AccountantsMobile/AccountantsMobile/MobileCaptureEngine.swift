import SwiftUI
import VisionKit
import Vision
import CryptoKit
import ZIPFoundation
import UniformTypeIdentifiers
import UIKit

// On-device capture only. There are deliberately no endpoints or AI/cloud uploads.
// A Windows voucher service must review and process submission packages independently.

enum CaptureKind: String, Codable, CaseIterable, Identifiable {
    case payment = "Payment Voucher"
    case receipt = "Receipt Voucher"
    var id: String { rawValue }
}

enum CaptureReceiptType: String, Codable, CaseIterable, Identifiable {
    case bank = "Bank Transfer Receipt"
    case cheque = "Cheque Receipt Voucher"
    case cash = "Cash Receipt Voucher"
    var id: String { rawValue }
    var prefix: String {
        switch self {
        case .bank: return "BTR"
        case .cheque: return "CHRV"
        case .cash: return "CRV"
        }
    }
}

enum CapturePaymentMode: String, Codable, CaseIterable, Identifiable {
    case manual = "Manual PV"
    case electronic = "Electronic PV — PC approval required"
    var id: String { rawValue }
}

struct CaptureEvidence: Codable, Identifiable, Hashable {
    var id = UUID()
    var displayName: String
    var storedName: String
    var sha256: String
    var sizeBytes: Int64
}

struct CaptureRequest: Codable, Identifiable {
    var id: UUID
    var schemaVersion: Int
    var createdAt: Date
    var companyID: Int64
    var companyCode: String
    var companyName: String
    var kind: CaptureKind
    var receiptType: CaptureReceiptType
    var paymentMode: CapturePaymentMode
    var party: String
    var receivedBy: String
    var amount: Decimal
    var currency: String
    var transactionDate: Date
    var reference: String
    var against: String
    var bankDetails: String
    var purpose: String
    var notes: String
    var evidence: [CaptureEvidence]
    var extractedText: String
    var reviewedOnMobile: Bool
    var state: String // localDraft / packagePrepared. Never "posted" without PC acknowledgment.
}

enum CaptureProblem: LocalizedError {
    case noDeviceCamera, invalidDocument, missingCompany, missingFields, noEvidence, tooManyPages, unreadableDrafts
    var errorDescription: String? {
        switch self {
        case .noDeviceCamera: return "Document scanning isn't available on this device. Use Attach Document instead."
        case .invalidDocument: return "The evidence file was unreadable or exceeded 15 MB."
        case .missingCompany: return "Import a Windows backup and select the correct company before preparing a PC voucher request."
        case .missingFields: return "Enter a valid amount, counterparty and purpose before saving."
        case .noEvidence: return "Scan or attach at least one supporting document."
        case .tooManyPages: return "A request supports up to 12 scanned pages or attachments."
        case .unreadableDrafts: return "Existing capture records couldn't be decoded. They are preserved and new saves are blocked until repaired."
        }
    }
}

@MainActor
final class CaptureInbox: ObservableObject {
    @Published private(set) var requests: [CaptureRequest] = []
    @Published var loadError = ""

    private let fm = FileManager.default
    private var root: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AccountantsMobile/Capture", isDirectory: true)
    }
    private var requestsFile: URL { root.appendingPathComponent("requests.json") }
    private var evidenceRoot: URL { root.appendingPathComponent("evidence", isDirectory: true) }

    init() {
        do {
            let file = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AccountantsMobile/Capture/requests.json")
            if fm.fileExists(atPath: file.path) {
                requests = try JSONDecoder().decode([CaptureRequest].self, from: Data(contentsOf: file))
            }
        } catch { loadError = error.localizedDescription }
    }

    private func setup() throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: evidenceRoot, withIntermediateDirectories: true)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: evidenceRoot.path)
    }

    func save(_ request: CaptureRequest, newPages: [UIImage], importedFile: URL?) throws {
        guard loadError.isEmpty else { throw CaptureProblem.unreadableDrafts }
        guard !request.companyName.isEmpty, request.companyID > 0 else { throw CaptureProblem.missingCompany }
        guard request.amount > 0, !request.party.isEmpty,
              !request.purpose.isEmpty else { throw CaptureProblem.missingFields }
        guard newPages.count + (importedFile == nil ? 0 : 1) > 0 else { throw CaptureProblem.noEvidence }
        guard newPages.count + (importedFile == nil ? 0 : 1) <= 12 else { throw CaptureProblem.tooManyPages }
        try setup()
        var item = request
        var added: [URL] = []
        do {
            for (index, page) in newPages.enumerated() {
                guard let jpeg = page.jpegData(compressionQuality: 0.86),
                      jpeg.count <= 15 * 1024 * 1024 else { throw CaptureProblem.invalidDocument }
                let name = UUID().uuidString + ".jpg"
                let file = evidenceRoot.appendingPathComponent(name)
                try jpeg.write(to: file, options: [.atomic, .completeFileProtection])
                added.append(file)
                item.evidence.append(CaptureEvidence(
                    displayName: "Scan-page-\(index + 1).jpg", storedName: name,
                    sha256: SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined(),
                    sizeBytes: Int64(jpeg.count)
                ))
            }
            if let original = importedFile {
                let scoped = original.startAccessingSecurityScopedResource()
                defer { if scoped { original.stopAccessingSecurityScopedResource() } }
                let metadata = try original.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard metadata.isRegularFile == true, (metadata.fileSize ?? Int.max) <= 15 * 1024 * 1024
                else { throw CaptureProblem.invalidDocument }
                let data = try Data(contentsOf: original)
                let suffix = original.pathExtension.lowercased().filter { $0.isASCII && $0.isLetter || $0.isNumber }
                let name = UUID().uuidString + (suffix.isEmpty ? "" : "." + suffix)
                let target = evidenceRoot.appendingPathComponent(name)
                try data.write(to: target, options: [.atomic, .completeFileProtection])
                added.append(target)
                item.evidence.append(CaptureEvidence(
                    displayName: original.lastPathComponent, storedName: name,
                    sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                    sizeBytes: Int64(data.count)
                ))
            }
            var updated = requests
            updated.insert(item, at: 0)
            try JSONEncoder().encode(updated).write(to: requestsFile, options: [.atomic, .completeFileProtection])
            requests = updated
        } catch {
            for path in added { try? fm.removeItem(at: path) }
            throw error
        }
    }

    func exportPCRequest(_ item: CaptureRequest) throws -> URL {
        try setup()
        let working = fm.temporaryDirectory.appendingPathComponent("PCRequest-\(item.id.uuidString)", isDirectory: true)
        try? fm.removeItem(at: working)
        try fm.createDirectory(at: working, withIntermediateDirectories: true)
        let evidenceTarget = working.appendingPathComponent("evidence", isDirectory: true)
        try fm.createDirectory(at: evidenceTarget, withIntermediateDirectories: true)
        var evidenceChecksums: [String: String] = [:]
        for attachment in item.evidence {
            // storedName is always a UUID-generated filename, not external input.
            guard !attachment.storedName.contains("/") && !attachment.storedName.contains("\\")
            else { throw CaptureProblem.invalidDocument }
            let source = evidenceRoot.appendingPathComponent(attachment.storedName)
            let data = try Data(contentsOf: source)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == attachment.sha256 else { throw CaptureProblem.invalidDocument }
            evidenceChecksums[attachment.storedName] = digest
            try data.write(to: evidenceTarget.appendingPathComponent(attachment.storedName),
                           options: [.atomic, .completeFileProtection])
        }
        let json = try JSONEncoder().encode(item)
        try json.write(to: working.appendingPathComponent("request.json"),
                       options: [.atomic, .completeFileProtection])
        let manifest: [String: Any] = [
            "schema": "AccountantsNext.MobileCapture.v1",
            "requestID": item.id.uuidString,
            "recordStatus": "AWAITING_WINDOWS_IMPORT_AND_APPROVAL",
            "requestSHA256": SHA256.hash(data: json).map { String(format: "%02x", $0) }.joined(),
            "evidenceSHA256": evidenceChecksums
        ]
        let md = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try md.write(to: working.appendingPathComponent("manifest.json"),
                     options: [.atomic, .completeFileProtection])
        let zip = fm.temporaryDirectory.appendingPathComponent("AccountantsNext-PCRequest-\(item.id.uuidString).zip")
        try? fm.removeItem(at: zip)
        try fm.zipItem(at: working, to: zip)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: zip.path)
        return zip
    }

    func evidenceURL(_ file: CaptureEvidence) -> URL? {
        let u = evidenceRoot.appendingPathComponent(file.storedName)
        return fm.fileExists(atPath: u.path) ? u : nil
    }
}

enum OnDeviceDocumentOCR {
    static func recognize(_ images: [UIImage], completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var pages: [String] = []
                for image in images {
                    guard let cg = image.cgImage else { continue }
                    let req = VNRecognizeTextRequest()
                    req.recognitionLevel = .accurate
                    req.usesLanguageCorrection = true
                    req.recognitionLanguages = ["en-US"]
                    try VNImageRequestHandler(cgImage: cg).perform([req])
                    let text = (req.results ?? []).compactMap {
                        $0.topCandidates(1).first?.string
                    }.joined(separator: "\n")
                    pages.append(text)
                }
                DispatchQueue.main.async { completion(.success(pages.joined(separator: "\n--- PAGE ---\n"))) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    static func amounts(in text: String) -> [String] {
        // Suggestions only. Never auto-approve an OCR monetary value.
        let pattern = #"(?i)\b(?:QAR|QR|USD|AED)\s*[:\-]?\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return Array(Set(matches.compactMap { m -> String? in
            guard m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
            return ns.substring(with: m.range(at: 1))
        })).sorted().prefix(6).map { $0 }
    }
}

struct DocumentScanner: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    var onFailure: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let view = VNDocumentCameraViewController()
        view.delegate = context.coordinator
        return view
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(parent: DocumentScanner) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onScan([])
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onFailure(error.localizedDescription)
        }
    }
}

struct PCSubmissionShare: UIViewControllerRepresentable {
    let file: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
