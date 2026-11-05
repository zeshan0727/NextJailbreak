import AuthenticationServices
import Foundation
import ImageIO
import MessageUI
import Security
import SwiftUI
import UIKit

// MARK: - Secure Storage

enum SecureStore {
    private static let service = "com.aspiregroup.maintenance"

    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }

    static func load(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Gmail Connector

enum GmailConnectionError: LocalizedError {
    case schedulerNotConfigured
    case invalidEndpoint
    case invalidResponse
    case missingAuthorizationURL
    case cancelled
    case callbackMissingConnection
    case server(String)

    var errorDescription: String? {
        switch self {
        case .schedulerNotConfigured: return "Enter the HTTPS scheduler URL and API key first."
        case .invalidEndpoint: return "The scheduler URL must be a valid HTTPS address."
        case .invalidResponse: return "The Gmail connection service returned an invalid response."
        case .missingAuthorizationURL: return "The scheduler did not return a Google authorization link."
        case .cancelled: return "Gmail connection was cancelled."
        case .callbackMissingConnection: return "Google authorization completed without connector details."
        case .server(let message): return message
        }
    }
}

struct GmailConnectionRecord: Codable, Equatable {
    var connectorID: String
    var emailAddress: String
    var connectedAt: Date
}

private struct GmailStartPayload: Encodable {
    var callbackScheme: String
    var appName: String
}

private struct GmailStartResponse: Decodable {
    var authorizationURL: String?
    var sessionID: String?
    var message: String?
}

private struct GmailStatusResponse: Decodable {
    var connected: Bool?
    var connectorID: String?
    var emailAddress: String?
    var message: String?
}

@MainActor
final class GmailOAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GmailOAuthClient()
    private var activeSession: ASWebAuthenticationSession?

    func connect(configuration: EmailConfiguration, apiKey: String) async throws -> GmailConnectionRecord {
        var request = try makeRequest(path: "v1/connectors/gmail/start", method: "POST", configuration: configuration, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GmailStartPayload(callbackScheme: "aspiremaintenance", appName: "Aspire Maintenance"))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let start = try JSONDecoder().decode(GmailStartResponse.self, from: data)
        guard let rawURL = start.authorizationURL, let url = URL(string: rawURL) else {
            throw GmailConnectionError.missingAuthorizationURL
        }

        let callback = try await authenticate(at: url)
        if let record = connection(from: callback) { return record }
        guard let sessionID = start.sessionID else { throw GmailConnectionError.callbackMissingConnection }
        return try await fetchStatus(sessionID: sessionID, configuration: configuration, apiKey: apiKey)
    }

    func disconnect(configuration: EmailConfiguration, apiKey: String) async throws {
        guard !configuration.connectorID.isEmpty else { return }
        let encoded = configuration.connectorID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? configuration.connectorID
        let request = try makeRequest(path: "v1/connectors/gmail/\(encoded)", method: "DELETE", configuration: configuration, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }

    private func authenticate(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "aspiremaintenance") { callbackURL, error in
                self.activeSession = nil
                if let authenticationError = error as? ASWebAuthenticationSessionError,
                   authenticationError.code == .canceledLogin {
                    continuation.resume(throwing: GmailConnectionError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GmailConnectionError.callbackMissingConnection)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            guard session.start() else {
                activeSession = nil
                continuation.resume(throwing: GmailConnectionError.invalidResponse)
                return
            }
        }
    }

    private func connection(from url: URL) -> GmailConnectionRecord? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let connectorID = values["connector_id"] ?? values["connectorID"]
        let email = values["email"] ?? values["email_address"]
        guard let connectorID, !connectorID.isEmpty, let email, !email.isEmpty else { return nil }
        return GmailConnectionRecord(connectorID: connectorID, emailAddress: email, connectedAt: Date())
    }

    private func fetchStatus(sessionID: String, configuration: EmailConfiguration, apiKey: String) async throws -> GmailConnectionRecord {
        let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionID
        let request = try makeRequest(path: "v1/connectors/gmail/status?session_id=\(encoded)", method: "GET", configuration: configuration, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let status = try JSONDecoder().decode(GmailStatusResponse.self, from: data)
        guard status.connected == true,
              let connectorID = status.connectorID,
              let emailAddress = status.emailAddress else {
            throw GmailConnectionError.server(status.message ?? "Gmail connection is not complete.")
        }
        return GmailConnectionRecord(connectorID: connectorID, emailAddress: emailAddress, connectedAt: Date())
    }

    private func makeRequest(path: String, method: String, configuration: EmailConfiguration, apiKey: String) throws -> URLRequest {
        let endpoint = configuration.schedulerEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, !key.isEmpty else { throw GmailConnectionError.schedulerNotConfigured }
        let normalized = endpoint.hasSuffix("/") ? endpoint : endpoint + "/"
        guard let baseURL = URL(string: normalized), baseURL.scheme?.lowercased() == "https",
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw GmailConnectionError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("AspireMaintenance-iOS/1.1.2", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GmailConnectionError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(GmailStartResponse.self, from: data).message)
                ?? "Gmail connection failed (\(http.statusCode))."
            throw GmailConnectionError.server(message)
        }
    }
}

struct DirectEmailAttachment {
    var fileName: String
    var mimeType: String
    var data: Data
}

private struct DirectEmailAttachmentPayload: Encodable {
    var fileName: String
    var mimeType: String
    var base64: String
}

private struct DirectEmailPayload: Encodable {
    var recipients: [String]
    var subject: String
    var body: String
    var remoteConnectorID: String
    var senderLabel: String
    var attachments: [DirectEmailAttachmentPayload]
}

private struct DirectEmailResponse: Decodable {
    var id: String?
    var message: String?
}

enum DirectEmailError: LocalizedError {
    case gmailNotReady
    case invalidRecipient
    case invalidEndpoint
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .gmailNotReady: return "Connect Gmail in Settings before sending directly."
        case .invalidRecipient: return "The customer email address is not valid."
        case .invalidEndpoint: return "The saved scheduler URL is invalid."
        case .invalidResponse: return "The email service returned an invalid response."
        case .server(let message): return message
        }
    }
}

struct DirectEmailService {
    func send(recipient: String, subject: String, body: String, attachments: [DirectEmailAttachment], configuration: EmailConfiguration, apiKey: String) async throws -> String {
        guard !configuration.connectorID.isEmpty,
              !configuration.connectedEmail.isEmpty,
              !configuration.schedulerEndpoint.isEmpty,
              !apiKey.isEmpty else { throw DirectEmailError.gmailNotReady }
        guard Self.isValidEmail(recipient) else { throw DirectEmailError.invalidRecipient }

        let normalized = configuration.schedulerEndpoint.hasSuffix("/") ? configuration.schedulerEndpoint : configuration.schedulerEndpoint + "/"
        guard let baseURL = URL(string: normalized), baseURL.scheme?.lowercased() == "https",
              let url = URL(string: "v1/file-shares", relativeTo: baseURL)?.absoluteURL else {
            throw DirectEmailError.invalidEndpoint
        }

        let payload = DirectEmailPayload(
            recipients: [recipient],
            subject: subject,
            body: body,
            remoteConnectorID: configuration.connectorID,
            senderLabel: configuration.connectedEmail,
            attachments: attachments.map {
                DirectEmailAttachmentPayload(fileName: $0.fileName, mimeType: $0.mimeType, base64: $0.data.base64EncodedString())
            }
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AspireMaintenance-iOS/1.1.2", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DirectEmailError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(DirectEmailResponse.self, from: data).message)
                ?? "Email sending failed (\(http.statusCode))."
            throw DirectEmailError.server(message)
        }
        return (try? JSONDecoder().decode(DirectEmailResponse.self, from: data).message) ?? "Invoice sent successfully."
    }

    static func isValidEmail(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = cleaned.firstIndex(of: "@"), cleaned[cleaned.index(after: at)...].contains(".") else { return false }
        return !cleaned.contains(" ") && cleaned.count <= 254
    }
}

// MARK: - Image Processing

enum ImageUtilities {
    /// Downsamples user-selected images before persistence so Photos/files do not make
    /// dashboard scrolling or PDF preview rendering unnecessarily expensive.
    static func normalizedImageData(_ data: Data, maxPixelSize: Int = 1400) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let uiImage = UIImage(cgImage: image)
        if image.alphaInfo == .premultipliedFirst || image.alphaInfo == .premultipliedLast ||
            image.alphaInfo == .first || image.alphaInfo == .last {
            return uiImage.pngData()
        }
        return uiImage.jpegData(compressionQuality: 0.88)
    }
}

// MARK: - Invoice PDF

struct InvoicePDFService {
    private let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private let green = UIColor(red: 0.10, green: 0.48, blue: 0.29, alpha: 1)
    private let gold = UIColor(red: 0.91, green: 0.63, blue: 0.15, alpha: 1)
    private let dark = UIColor(red: 0.12, green: 0.16, blue: 0.15, alpha: 1)

    func makePDF(
        invoice: Invoice,
        customer: Customer,
        company: CompanyProfile,
        settings: InvoicePDFSettings = .aspireDefault,
        bankAccount: BankAccount? = nil,
        appLogoData: Data? = nil,
        employeeName: String? = nil
    ) -> Data {
        UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            UIColor.white.setFill(); UIRectFill(page)
            green.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: page.width, height: 12))
            gold.withAlphaComponent(0.09).setFill(); UIBezierPath(ovalIn: CGRect(x: -120, y: 650, width: 300, height: 300)).fill()

            if settings.showLogo { drawLogo(settings: settings, appLogoData: appLogoData) }
            if settings.showCompanyName { drawCompanyName(company: company, settings: settings) }
            if settings.showCompanyContact { drawCompanyContact(company: company, settings: settings) }
            drawTitle(invoice: invoice, settings: settings)
            if settings.showPaymentStatus { drawStatus(invoice: invoice, settings: settings) }
            if settings.showBillTo { drawCustomer(customer: customer, settings: settings) }
            if settings.showInvoiceMeta { drawMeta(invoice: invoice, employeeName: employeeName, settings: settings) }
            if settings.showItems { drawItems(invoice: invoice, company: company, settings: settings) }
            if settings.showPayment { drawPayment(company: company, bankAccount: bankAccount, settings: settings) }
            if settings.showTerms { drawTerms(invoice: invoice, settings: settings) }
            drawOverlayImages(settings.overlayImages)
            if settings.showFooter { drawFooter(settings: settings) }
            if settings.showItems {
                drawContinuationPages(context: context, invoice: invoice, company: company)
            }
        }
    }

    private func zone(_ zone: PDFEditableZone, settings: InvoicePDFSettings) -> CGRect {
        let n = settings.frame(for: zone)
        return CGRect(x: page.width * n.x, y: page.height * n.y, width: page.width * n.width, height: page.height * n.height)
    }

    private func inset(_ rect: CGRect, _ amount: CGFloat = 4) -> CGRect { rect.insetBy(dx: amount, dy: amount) }

    private func drawLogo(settings: InvoicePDFSettings, appLogoData: Data?) {
        let chosenData = settings.logoData ?? appLogoData
        let logo = chosenData.flatMap(UIImage.init(data:)) ?? UIImage(named: "AspireLogo")
        guard let logo else { return }
        logo.draw(in: aspectFitRect(imageSize: logo.size, in: inset(zone(.logo, settings: settings), 3)))
    }

    private func drawCompanyName(company: CompanyProfile, settings: InvoicePDFSettings) {
        let value = settings.companyNameOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? company.fullName : settings.companyNameOverride
        let rect = inset(zone(.companyName, settings: settings), 2)
        drawText(value, in: rect, font: .systemFont(ofSize: fontSize(14, for: rect), weight: .bold), color: green)
    }

    private func drawCompanyContact(company: CompanyProfile, settings: InvoicePDFSettings) {
        let automatic = [company.address, company.phone, company.email, company.website].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "  •  ")
        let value = settings.companyContactOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? automatic : settings.companyContactOverride
        let rect = inset(zone(.companyContact, settings: settings), 1)
        drawText(value, in: rect, font: .systemFont(ofSize: fontSize(8.5, for: rect)), color: .darkGray, alignment: .center)
    }

    private func drawTitle(invoice: Invoice, settings: InvoicePDFSettings) {
        let rect = zone(.invoiceTitle, settings: settings)
        let baseTitle = settings.invoiceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "INVOICE" : settings.invoiceTitle
        let revised = !(invoice.revisions ?? []).isEmpty
        let title = revised ? "REVISED " + baseTitle : baseTitle
        drawText(title, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.65), font: .systemFont(ofSize: fontSize(revised ? 23 : 31, for: rect), weight: .heavy), color: dark, alignment: .right)
        drawText(invoice.number, in: CGRect(x: rect.minX, y: rect.minY + rect.height * 0.68, width: rect.width, height: rect.height * 0.28), font: .monospacedSystemFont(ofSize: fontSize(10.5, for: rect), weight: .semibold), color: green, alignment: .right)
    }

    private func drawStatus(invoice: Invoice, settings: InvoicePDFSettings) {
        let rect = inset(zone(.paymentStatus, settings: settings), 1)
        let text: String
        let color: UIColor
        switch invoice.status {
        case .paid: text = settings.paidText.isEmpty ? "PAID" : settings.paidText; color = green
        case .partial: text = settings.partialPaidText.isEmpty ? "PART PAID" : settings.partialPaidText; color = gold
        case .void: text = "VOID"; color = .darkGray
        default: text = settings.unpaidText.isEmpty ? "UNPAID" : settings.unpaidText; color = .systemRed
        }
        color.withAlphaComponent(0.11).setFill(); UIBezierPath(roundedRect: rect, cornerRadius: min(9, rect.height / 3)).fill()
        drawText(text.uppercased(), in: inset(rect, 4), font: .systemFont(ofSize: fontSize(11, for: rect), weight: .heavy), color: color, alignment: .center)
    }

    private func drawCustomer(customer: Customer, settings: InvoicePDFSettings) {
        let rect = inset(zone(.billTo, settings: settings), 2)
        let title = settings.billToTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "BILL TO" : settings.billToTitle
        drawText(title, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 18), font: .systemFont(ofSize: fontSize(12, for: rect), weight: .bold), color: green)
        drawText(customer.name, in: CGRect(x: rect.minX, y: rect.minY + 21, width: rect.width, height: 24), font: .systemFont(ofSize: fontSize(13, for: rect), weight: .bold), color: dark)
        let details = [customer.address, customer.phone, customer.email].filter { !$0.isEmpty }.joined(separator: "\n")
        drawText(details, in: CGRect(x: rect.minX, y: rect.minY + 47, width: rect.width, height: max(18, rect.height - 47)), font: .systemFont(ofSize: fontSize(9, for: rect)), color: .darkGray)
    }

    private func drawMeta(invoice: Invoice, employeeName: String?, settings: InvoicePDFSettings) {
        let rect = inset(zone(.invoiceMeta, settings: settings), 2)
        var labels = ["ISSUE DATE", "DUE DATE", "SERVICE MONTH"]
        var values = [DateFormatter.shortDate.string(from: invoice.issueDate), DateFormatter.shortDate.string(from: invoice.dueDate), DateFormatter.monthAndYear.string(from: invoice.serviceMonth)]
        if let employeeName, !employeeName.isEmpty { labels.append("JOB DONE BY"); values.append(employeeName) }
        let left = CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.48, height: rect.height)
        let right = CGRect(x: rect.minX + rect.width * 0.49, y: rect.minY, width: rect.width * 0.51, height: rect.height)
        drawText(labels.joined(separator: "\n"), in: left, font: .systemFont(ofSize: fontSize(8.5, for: rect), weight: .bold), color: dark)
        drawText(values.joined(separator: "\n"), in: right, font: .systemFont(ofSize: fontSize(8.5, for: rect)), color: dark, alignment: .right)
    }

    private func drawItems(invoice: Invoice, company: CompanyProfile, settings: InvoicePDFSettings) {
        let rect = inset(zone(.items, settings: settings), 1)
        guard rect.width > 80, rect.height > 55 else { return }
        let headerH: CGFloat = min(28, max(20, rect.height * 0.14))
        green.setFill(); UIRectFill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerH))
        let descW = rect.width * 0.55
        let qtyW = rect.width * 0.11
        let priceW = rect.width * 0.16
        let amountW = rect.width - descW - qtyW - priceW
        drawText("DESCRIPTION", in: CGRect(x: rect.minX + 6, y: rect.minY + 5, width: descW - 8, height: headerH - 8), font: .systemFont(ofSize: 8.5, weight: .bold), color: .white)
        drawText("QTY", in: CGRect(x: rect.minX + descW, y: rect.minY + 5, width: qtyW, height: headerH - 8), font: .systemFont(ofSize: 8.5, weight: .bold), color: .white, alignment: .center)
        drawText("PRICE", in: CGRect(x: rect.minX + descW + qtyW, y: rect.minY + 5, width: priceW, height: headerH - 8), font: .systemFont(ofSize: 8.5, weight: .bold), color: .white, alignment: .right)
        drawText("AMOUNT", in: CGRect(x: rect.maxX - amountW, y: rect.minY + 5, width: amountW - 5, height: headerH - 8), font: .systemFont(ofSize: 8.5, weight: .bold), color: .white, alignment: .right)

        let items = Array(invoice.lineItems.prefix(firstPageLineCount(for: invoice)))
        let totalH: CGFloat = min(34, max(26, rect.height * 0.18))
        let available = max(0, rect.height - headerH - totalH - 4)
        let descriptionWidth = descW - 8

        var titleFont: CGFloat = 8.3
        var secondaryFont: CGFloat = 7.0
        var desiredHeights = invoiceItemRowHeights(items, width: descriptionWidth, titleFont: titleFont, secondaryFont: secondaryFont)
        var desiredTotal = desiredHeights.reduce(0, +)
        if desiredTotal > available {
            titleFont = 7.5
            secondaryFont = 6.3
            desiredHeights = invoiceItemRowHeights(items, width: descriptionWidth, titleFont: titleFont, secondaryFont: secondaryFont)
            desiredTotal = desiredHeights.reduce(0, +)
        }
        if desiredTotal > available {
            titleFont = 6.8
            secondaryFont = 5.8
            desiredHeights = invoiceItemRowHeights(items, width: descriptionWidth, titleFont: titleFont, secondaryFont: secondaryFont)
            desiredTotal = desiredHeights.reduce(0, +)
        }

        let scale: CGFloat = desiredTotal > available && desiredTotal > 0 ? available / desiredTotal : 1
        let extra = desiredTotal < available && !items.isEmpty ? min(3, (available - desiredTotal) / CGFloat(items.count)) : 0
        var y = rect.minY + headerH

        for (offset, item) in items.enumerated() {
            let natural = desiredHeights.indices.contains(offset) ? desiredHeights[offset] : 22
            let rowH = max(16, natural * scale + extra)
            let remaining = max(0, rect.maxY - totalH - y)
            guard remaining > 0 else { break }
            let actualRowH = min(rowH, remaining)

            UIColor(white: 0.965, alpha: 1).setFill()
            UIRectFill(CGRect(x: rect.minX, y: y, width: rect.width, height: max(0, actualRowH - 1)))

            let descriptionRect = CGRect(x: rect.minX + 6, y: y + 3, width: descriptionWidth, height: max(10, actualRowH - 5))
            let titleHeight = min(descriptionRect.height, invoiceMeasuredTextHeight(item.description, width: descriptionRect.width, size: titleFont, weight: .semibold))
            drawText(item.description, in: CGRect(x: descriptionRect.minX, y: descriptionRect.minY, width: descriptionRect.width, height: titleHeight), font: .systemFont(ofSize: titleFont, weight: .semibold), color: dark)

            if item.hasSecondaryText {
                let secondaryY = descriptionRect.minY + titleHeight + 1
                let secondaryHeight = max(0, descriptionRect.maxY - secondaryY)
                if secondaryHeight > 0 {
                    drawText(item.secondaryDisplayText, in: CGRect(x: descriptionRect.minX, y: secondaryY, width: descriptionRect.width, height: secondaryHeight), font: .systemFont(ofSize: secondaryFont), color: .darkGray)
                }
            }

            let valueY = y + max(4, (actualRowH - 18) / 2)
            drawText(String(format: "%.2f", item.quantity), in: CGRect(x: rect.minX + descW, y: valueY, width: qtyW, height: 18), font: .systemFont(ofSize: 8.1), color: dark, alignment: .center)
            drawText(CurrencyFormatter.string(item.unitPrice, code: company.currencyCode), in: CGRect(x: rect.minX + descW + qtyW, y: valueY, width: priceW, height: 18), font: .systemFont(ofSize: 7.5), color: dark, alignment: .right)
            drawText(CurrencyFormatter.string(item.amount, code: company.currencyCode), in: CGRect(x: rect.maxX - amountW, y: valueY, width: amountW - 5, height: 18), font: .systemFont(ofSize: 7.5, weight: .semibold), color: dark, alignment: .right)
            y += actualRowH
        }

        let totalRect = CGRect(x: rect.minX + rect.width * 0.57, y: rect.maxY - totalH, width: rect.width * 0.43, height: totalH)
        gold.setFill(); UIRectFill(totalRect)
        drawText("TOTAL", in: CGRect(x: totalRect.minX + 8, y: totalRect.minY + 8, width: totalRect.width * 0.35, height: 18), font: .systemFont(ofSize: 10.5, weight: .heavy), color: dark)
        drawText(CurrencyFormatter.string(invoice.total, code: company.currencyCode), in: CGRect(x: totalRect.minX + totalRect.width * 0.38, y: totalRect.minY + 8, width: totalRect.width * 0.58 - 6, height: 18), font: .systemFont(ofSize: 10.5, weight: .heavy), color: dark, alignment: .right)
    }

    private func firstPageLineCount(for invoice: Invoice) -> Int {
        invoice.lineItems.contains { $0.hasSecondaryText } ? 5 : 6
    }

    /// The configurable original invoice template has space for 5-6 rows.
    /// Continue the remaining rows on numbered supplementary pages rather than
    /// silently omitting items added to an already issued invoice.
    private func drawContinuationPages(
        context: UIGraphicsPDFRendererContext,
        invoice: Invoice,
        company: CompanyProfile
    ) {
        let firstCount = firstPageLineCount(for: invoice)
        let remaining = Array(invoice.lineItems.dropFirst(firstCount))
        guard !remaining.isEmpty else { return }

        var index = 0
        var pageNumber = 2
        while index < remaining.count {
            context.beginPage()
            UIColor.white.setFill()
            UIRectFill(page)
            green.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: page.width, height: 12))

            drawText(
                company.fullName,
                in: CGRect(x: 36, y: 33, width: 520, height: 30),
                font: .systemFont(ofSize: 15, weight: .bold), color: green
            )
            drawText(
                "INVOICE ITEMS — CONTINUED",
                in: CGRect(x: 36, y: 72, width: 475, height: 26),
                font: .systemFont(ofSize: 17, weight: .heavy), color: dark
            )
            drawText(
                "\(invoice.number)  •  Page \(pageNumber)",
                in: CGRect(x: 36, y: 100, width: 523, height: 18),
                font: .monospacedSystemFont(ofSize: 10, weight: .medium),
                color: green
            )

            let left: CGFloat = 36
            let tableWidth: CGFloat = 523
            let descWidth: CGFloat = 280
            let qtyWidth: CGFloat = 52
            let priceWidth: CGFloat = 90
            let totalWidth: CGFloat = 99
            var y: CGFloat = 137
            green.setFill()
            UIRectFill(CGRect(x: left, y: y, width: tableWidth, height: 30))
            drawText("DESCRIPTION", in: CGRect(x: left + 7, y: y + 7, width: 270, height: 20),
                     font: .systemFont(ofSize: 9, weight: .bold), color: .white)
            drawText("QTY", in: CGRect(x: left + descWidth, y: y + 7, width: qtyWidth, height: 20),
                     font: .systemFont(ofSize: 9, weight: .bold), color: .white, alignment: .center)
            drawText("PRICE", in: CGRect(x: left + descWidth + qtyWidth, y: y + 7, width: priceWidth, height: 20),
                     font: .systemFont(ofSize: 9, weight: .bold), color: .white, alignment: .right)
            drawText("AMOUNT", in: CGRect(x: left + descWidth + qtyWidth + priceWidth, y: y + 7, width: totalWidth - 8, height: 20),
                     font: .systemFont(ofSize: 9, weight: .bold), color: .white, alignment: .right)
            y += 30

            while index < remaining.count {
                let item = remaining[index]
                let nameHeight = invoiceMeasuredTextHeight(item.description, width: descWidth - 16, size: 9.5, weight: .semibold)
                let detailsHeight = item.hasSecondaryText
                    ? invoiceMeasuredTextHeight(item.secondaryDisplayText, width: descWidth - 16, size: 8, weight: .regular)
                    : 0
                let desiredHeight = max(37, nameHeight + detailsHeight + 15)
                // Leave enough space for a grand total and a footer on the final page.
                guard y + desiredHeight < 719 || y <= 167 else { break }
                let rowHeight = min(desiredHeight, 545)
                UIColor(white: index.isMultiple(of: 2) ? 0.965 : 0.99, alpha: 1).setFill()
                UIRectFill(CGRect(x: left, y: y, width: tableWidth, height: rowHeight))

                drawText(
                    item.description, in: CGRect(x: left + 7, y: y + 6, width: descWidth - 14, height: min(nameHeight + 2, rowHeight - 10)),
                    font: .systemFont(ofSize: 9.5, weight: .semibold), color: dark
                )
                if item.hasSecondaryText {
                    drawText(
                        item.secondaryDisplayText,
                        in: CGRect(x: left + 7, y: y + 6 + nameHeight, width: descWidth - 14, height: max(0, rowHeight - nameHeight - 8)),
                        font: .systemFont(ofSize: 8), color: .darkGray
                    )
                }
                drawText(
                    String(format: "%.2f", item.quantity),
                    in: CGRect(x: left + descWidth, y: y + 9, width: qtyWidth, height: 18),
                    font: .systemFont(ofSize: 9), color: dark, alignment: .center
                )
                drawText(
                    CurrencyFormatter.string(item.unitPrice, code: company.currencyCode),
                    in: CGRect(x: left + descWidth + qtyWidth, y: y + 9, width: priceWidth, height: 18),
                    font: .systemFont(ofSize: 8), color: dark, alignment: .right
                )
                drawText(
                    CurrencyFormatter.string(item.amount, code: company.currencyCode),
                    in: CGRect(x: left + descWidth + qtyWidth + priceWidth, y: y + 9, width: totalWidth - 8, height: 18),
                    font: .systemFont(ofSize: 8, weight: .semibold), color: dark, alignment: .right
                )
                y += rowHeight
                index += 1
            }

            if index == remaining.count {
                gold.setFill()
                UIRectFill(CGRect(x: left + 290, y: min(y + 18, 742), width: 233, height: 35))
                let totalY = min(y + 24, 748)
                drawText("TOTAL", in: CGRect(x: left + 298, y: totalY, width: 75, height: 20),
                         font: .systemFont(ofSize: 10, weight: .bold), color: dark)
                drawText(
                    CurrencyFormatter.string(invoice.total, code: company.currencyCode),
                    in: CGRect(x: left + 369, y: totalY, width: 140, height: 20),
                    font: .systemFont(ofSize: 10, weight: .bold), color: dark, alignment: .right
                )
            }
            drawText(
                "Aspire Maintenance • \(invoice.number)",
                in: CGRect(x: 36, y: 796, width: 520, height: 20),
                font: .systemFont(ofSize: 8), color: .gray, alignment: .center
            )
            pageNumber += 1
        }
    }

    private func invoiceItemRowHeights(_ items: [InvoiceLineItem], width: CGFloat, titleFont: CGFloat, secondaryFont: CGFloat) -> [CGFloat] {
        items.map { item in
            let titleHeight = invoiceMeasuredTextHeight(item.description, width: width, size: titleFont, weight: .semibold)
            let secondaryHeight = item.hasSecondaryText ? invoiceMeasuredTextHeight(item.secondaryDisplayText, width: width, size: secondaryFont, weight: .regular) : 0
            return max(22, 7 + titleHeight + (secondaryHeight > 0 ? secondaryHeight + 2 : 0))
        }
    }

    private func invoiceMeasuredTextHeight(_ text: String, width: CGFloat, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
        guard !text.isEmpty, width > 1 else { return 0 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .paragraphStyle: paragraph],
            context: nil
        )
        return ceil(bounds.height)
    }

    private func drawPayment(company: CompanyProfile, bankAccount: BankAccount?, settings: InvoicePDFSettings) {
        let rect = inset(zone(.payment, settings: settings), 2)
        let title = settings.paymentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "PAYMENT METHOD" : settings.paymentTitle
        drawText(title, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 20), font: .systemFont(ofSize: fontSize(12, for: rect), weight: .bold), color: green)
        var lines: [String] = []
        if let bankAccount {
            if !bankAccount.label.isEmpty { lines.append(bankAccount.label) }
            if !bankAccount.bankName.isEmpty { lines.append("Bank Name: \(bankAccount.bankName)") }
            if !bankAccount.accountHolderName.isEmpty { lines.append("Account Holder: \(bankAccount.accountHolderName)") }
            if !bankAccount.accountNumber.isEmpty { lines.append("Account Number: \(bankAccount.accountNumber)") }
            if !bankAccount.iban.isEmpty { lines.append("IBAN: \(bankAccount.iban)") }
            if !bankAccount.swiftCode.isEmpty { lines.append("SWIFT: \(bankAccount.swiftCode)") }
            lines.append("Currency: \(bankAccount.currencyCode.isEmpty ? company.currencyCode : bankAccount.currencyCode)")
        } else {
            if !company.bankName.isEmpty { lines.append("Bank Name: \(company.bankName)") }
            if !company.accountHolderName.isEmpty { lines.append("Account Holder: \(company.accountHolderName)") }
            if !company.accountNumber.isEmpty { lines.append("Account Number: \(company.accountNumber)") }
            if !company.iban.isEmpty { lines.append("IBAN: \(company.iban)") }
            if !company.swiftCode.isEmpty { lines.append("SWIFT: \(company.swiftCode)") }
            lines.append("Currency: \(company.currencyCode)")
        }
        if !company.taxRegistrationNumber.isEmpty { lines.append("TRN: \(company.taxRegistrationNumber)") }
        drawText(lines.joined(separator: "\n"), in: CGRect(x: rect.minX, y: rect.minY + 23, width: rect.width, height: max(18, rect.height - 23)), font: .systemFont(ofSize: fontSize(8.7, for: rect)), color: dark)
    }

    private func drawTerms(invoice: Invoice, settings: InvoicePDFSettings) {
        let rect = inset(zone(.terms, settings: settings), 2)
        let title = settings.termsTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "TERMS OR NOTES" : settings.termsTitle
        drawText(title, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 20), font: .systemFont(ofSize: fontSize(11.5, for: rect), weight: .bold), color: green)
        drawText(invoice.notes, in: CGRect(x: rect.minX, y: rect.minY + 22, width: rect.width, height: max(18, rect.height - 22)), font: .systemFont(ofSize: fontSize(8.8, for: rect)), color: dark)
    }

    private func drawFooter(settings: InvoicePDFSettings) {
        let rect = zone(.footer, settings: settings)
        green.setFill(); UIRectFill(rect)
        let text = settings.footerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? InvoicePDFSettings.aspireDefault.footerText : settings.footerText
        drawText(text, in: inset(rect, 3), font: .systemFont(ofSize: fontSize(7.5, for: rect), weight: .medium), color: .white, alignment: .center)
    }

    private func drawOverlayImages(_ overlays: [InvoicePDFOverlayImage]) {
        for overlay in overlays.prefix(12) {
            guard let image = UIImage(data: overlay.imageData) else { continue }
            let rect = CGRect(x: page.width * CGFloat(max(0, min(1, overlay.x))), y: page.height * CGFloat(max(0, min(1, overlay.y))), width: page.width * CGFloat(max(0.03, min(1, overlay.width))), height: page.height * CGFloat(max(0.03, min(1, overlay.height))))
            image.draw(in: aspectFitRect(imageSize: image.size, in: rect), blendMode: .normal, alpha: 1)
        }
    }

    private func fontSize(_ preferred: CGFloat, for rect: CGRect) -> CGFloat {
        max(6, min(preferred, max(7, min(rect.height * 0.42, rect.width * 0.10))))
    }

    private func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment; paragraph.lineBreakMode = .byWordWrapping
        text.draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}

// MARK: - Mail & Sharing

struct MailDraft: Identifiable {
    let id = UUID()
    var recipient: String
    var subject: String
    var body: String
    var attachmentData: Data
    var attachmentName: String
}

struct MailComposer: UIViewControllerRepresentable {
    var draft: MailDraft
    var onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([draft.recipient])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        controller.addAttachmentData(draft.attachmentData, mimeType: "application/pdf", fileName: draft.attachmentName)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
            onFinish(result)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum TemporaryFileService {
    static func write(data: Data, fileName: String) throws -> URL {
        let cleaned = fileName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(cleaned)
        try data.write(to: url, options: .atomic)
        return url
    }
}
