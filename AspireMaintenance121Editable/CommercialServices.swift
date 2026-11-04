import UIKit

struct QuotationPDFService {
    private let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private let green = UIColor(red: 0.10, green: 0.48, blue: 0.29, alpha: 1)
    private let gold = UIColor(red: 0.91, green: 0.63, blue: 0.15, alpha: 1)
    private let dark = UIColor(red: 0.12, green: 0.16, blue: 0.15, alpha: 1)

    func makePDF(
        quotation: Quotation,
        customer: Customer,
        company: CompanyProfile,
        settings: InvoicePDFSettings = .aspireQuotationDefault,
        bankAccount: BankAccount?,
        appLogoData: Data?,
        employeeName: String?
    ) -> Data {
        let pageSlices = quotationPages(quotation: quotation, settings: settings)

        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            for (pageIndex, slice) in pageSlices.enumerated() {
                context.beginPage()
                UIColor.white.setFill(); UIRectFill(page)
                green.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: page.width, height: 12))

                if settings.showLogo { drawLogo(settings: settings, appLogoData: appLogoData) }
                if settings.showCompanyName { drawCompanyName(company: company, settings: settings) }
                if settings.showCompanyContact { drawCompanyContact(company: company, settings: settings) }
                drawTitle(quotation: quotation, settings: settings)

                if pageIndex == 0 {
                    if settings.showPaymentStatus { drawStatus(quotation: quotation, settings: settings) }
                    if settings.showBillTo { drawCustomer(customer: customer, settings: settings) }
                    if settings.showInvoiceMeta { drawMeta(quotation: quotation, employeeName: employeeName, settings: settings) }
                } else {
                    drawContinuationLabel(pageNumber: pageIndex + 1)
                }

                if settings.showItems {
                    let rect = quotationItemsRect(pageIndex: pageIndex, isFinalPage: slice.isFinal, settings: settings)
                    drawItemsPage(
                        items: slice.items,
                        quotation: quotation,
                        company: company,
                        rect: rect,
                        includeTotals: slice.isFinal
                    )
                }

                if slice.isFinal {
                    if settings.showPayment { drawSummary(quotation: quotation, company: company, bankAccount: bankAccount, settings: settings) }
                    if settings.showTerms { drawTerms(quotation: quotation, settings: settings) }
                }

                if pageIndex == 0 { drawOverlayImages(settings.overlayImages) }
                if settings.showFooter { drawFooter(settings: settings) }
                drawPageNumber(pageIndex + 1, of: pageSlices.count, settings: settings)
            }
        }
    }

    private struct QuotationPageSlice {
        var items: [InvoiceLineItem]
        var isFinal: Bool
    }

    /// Splits quotation rows across as many PDF pages as needed.  A page is only
    /// marked final when the remaining rows *and* subtotal/discount/total block
    /// can fit without shrinking or clipping the description text.
    private func quotationPages(quotation: Quotation, settings: InvoicePDFSettings) -> [QuotationPageSlice] {
        let allItems = quotation.lineItems
        guard settings.showItems, !allItems.isEmpty else {
            return [QuotationPageSlice(items: allItems, isFinal: true)]
        }

        var result: [QuotationPageSlice] = []
        var remaining = allItems
        var pageIndex = 0

        while !remaining.isEmpty {
            let finalRect = quotationItemsRect(pageIndex: pageIndex, isFinalPage: true, settings: settings)
            if fittingPrefixCount(remaining, in: finalRect, quotation: quotation, includeTotals: true) >= remaining.count {
                result.append(QuotationPageSlice(items: remaining, isFinal: true))
                remaining.removeAll()
                break
            }

            let flowingRect = quotationItemsRect(pageIndex: pageIndex, isFinalPage: false, settings: settings)
            var count = fittingPrefixCount(remaining, in: flowingRect, quotation: quotation, includeTotals: false)
            count = max(1, count)

            // Keep at least one row for the final page when possible so the
            // total block is visually connected to quotation content.
            if count >= remaining.count, remaining.count > 1 {
                count = remaining.count - 1
            }

            result.append(QuotationPageSlice(items: Array(remaining.prefix(count)), isFinal: false))
            remaining.removeFirst(min(count, remaining.count))
            pageIndex += 1
        }

        if result.isEmpty {
            return [QuotationPageSlice(items: [], isFinal: true)]
        }
        if result.last?.isFinal != true {
            result.append(QuotationPageSlice(items: [], isFinal: true))
        }
        return result
    }

    private func quotationItemsRect(pageIndex: Int, isFinalPage: Bool, settings: InvoicePDFSettings) -> CGRect {
        let base = zone(.items, settings: settings).insetBy(dx: 1, dy: 1)
        let footerTop = settings.showFooter ? zone(.footer, settings: settings).minY - 8 : page.height - 28

        if pageIndex == 0 {
            if isFinalPage { return base }
            return CGRect(x: base.minX, y: base.minY, width: base.width, height: max(70, footerTop - base.minY))
        }

        let contactBottom = settings.showCompanyContact ? zone(.companyContact, settings: settings).maxY : page.height * 0.15
        let startY = max(page.height * 0.185, contactBottom + 12)
        let finalBottom: CGFloat
        if isFinalPage {
            if settings.showPayment {
                finalBottom = zone(.payment, settings: settings).minY - 8
            } else if settings.showTerms {
                finalBottom = zone(.terms, settings: settings).minY - 8
            } else {
                finalBottom = footerTop
            }
        } else {
            finalBottom = footerTop
        }
        return CGRect(x: base.minX, y: startY, width: base.width, height: max(90, finalBottom - startY))
    }

    private func fittingPrefixCount(_ items: [InvoiceLineItem], in rect: CGRect, quotation: Quotation, includeTotals: Bool) -> Int {
        guard rect.height > 40 else { return 0 }
        let headerH: CGFloat = 25
        let summaryH: CGFloat = includeTotals ? (quotation.discountAmount > 0 ? 54 : 36) : 0
        let available = max(0, rect.height - headerH - summaryH)
        let heights = itemRowHeights(items, width: rect.width * 0.53, titleFont: 8.3, secondaryFont: 7.0)
        var used: CGFloat = 0
        var count = 0
        for height in heights {
            if used + height > available + 0.5 { break }
            used += height
            count += 1
        }
        return count
    }

    private func zone(_ zone: PDFEditableZone, settings: InvoicePDFSettings) -> CGRect {
        let n = settings.frame(for: zone)
        return CGRect(x: page.width * n.x, y: page.height * n.y, width: page.width * n.width, height: page.height * n.height)
    }

    private func drawLogo(settings: InvoicePDFSettings, appLogoData: Data?) {
        let data = settings.logoData ?? appLogoData
        let logo = data.flatMap(UIImage.init(data:)) ?? UIImage(named: "AspireLogo")
        guard let logo else { return }
        logo.draw(in: aspectFit(logo.size, in: zone(.logo, settings: settings).insetBy(dx: 3, dy: 3)))
    }

    private func drawCompanyName(company: CompanyProfile, settings: InvoicePDFSettings) {
        let value = settings.companyNameOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? company.fullName : settings.companyNameOverride
        draw(value, zone(.companyName, settings: settings).insetBy(dx: 2, dy: 2), 13.5, .bold, green)
    }

    private func drawCompanyContact(company: CompanyProfile, settings: InvoicePDFSettings) {
        let automatic = [company.address, company.phone, company.email, company.website].filter { !$0.isEmpty }.joined(separator: "  •  ")
        let value = settings.companyContactOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? automatic : settings.companyContactOverride
        draw(value, zone(.companyContact, settings: settings).insetBy(dx: 2, dy: 1), 8.3, .regular, .darkGray, .center)
    }

    private func drawTitle(quotation: Quotation, settings: InvoicePDFSettings) {
        let rect = zone(.invoiceTitle, settings: settings)
        let title = settings.invoiceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "QUOTATION" : settings.invoiceTitle
        draw(title, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.64), 28, .heavy, dark, .right)
        draw(quotation.number, CGRect(x: rect.minX, y: rect.minY + rect.height * 0.67, width: rect.width, height: rect.height * 0.30), 10, .semibold, green, .right)
    }

    private func drawStatus(quotation: Quotation, settings: InvoicePDFSettings) {
        let rect = zone(.paymentStatus, settings: settings).insetBy(dx: 1, dy: 1)
        let text: String
        let color: UIColor
        switch quotation.status {
        case .accepted: text = settings.paidText.isEmpty ? "ACCEPTED" : settings.paidText; color = green
        case .sent: text = settings.partialPaidText.isEmpty ? "SENT" : settings.partialPaidText; color = gold
        case .rejected: text = "REJECTED"; color = .systemRed
        case .expired: text = "EXPIRED"; color = .darkGray
        case .draft: text = settings.unpaidText.isEmpty ? "DRAFT" : settings.unpaidText; color = .darkGray
        }
        color.withAlphaComponent(0.10).setFill(); UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
        draw(text.uppercased(), rect.insetBy(dx: 4, dy: 4), 10.5, .heavy, color, .center)
    }

    private func drawCustomer(customer: Customer, settings: InvoicePDFSettings) {
        let rect = zone(.billTo, settings: settings).insetBy(dx: 2, dy: 2)
        let title = settings.billToTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "QUOTATION TO" : settings.billToTitle
        draw(title, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 18), 12, .bold, green)
        draw(customer.name, CGRect(x: rect.minX, y: rect.minY + 21, width: rect.width, height: 24), 13.5, .bold, dark)
        let details = [customer.address, customer.phone, customer.email].filter { !$0.isEmpty }.joined(separator: "\n")
        draw(details, CGRect(x: rect.minX, y: rect.minY + 47, width: rect.width, height: max(20, rect.height - 47)), 9, .regular, .darkGray)
    }

    private func drawMeta(quotation: Quotation, employeeName: String?, settings: InvoicePDFSettings) {
        let rect = zone(.invoiceMeta, settings: settings).insetBy(dx: 2, dy: 2)
        var labels = ["QUOTE DATE", "VALID UNTIL", "WORK TYPE"]
        var values = [DateFormatter.shortDate.string(from: quotation.issueDate), DateFormatter.shortDate.string(from: quotation.validUntil), quotation.jobType.rawValue]
        if let employeeName, !employeeName.isEmpty { labels.append("PREPARED BY"); values.append(employeeName) }
        draw(labels.joined(separator: "\n"), CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.48, height: rect.height), 8.7, .bold, dark)
        draw(values.joined(separator: "\n"), CGRect(x: rect.minX + rect.width * 0.49, y: rect.minY, width: rect.width * 0.51, height: rect.height), 8.7, .regular, dark, .right)
    }

    private func drawItemsPage(
        items: [InvoiceLineItem],
        quotation: Quotation,
        company: CompanyProfile,
        rect: CGRect,
        includeTotals: Bool
    ) {
        guard rect.height > 55 else { return }
        let headerH: CGFloat = 25
        green.setFill(); UIRectFill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerH))
        draw("DESCRIPTION", CGRect(x: rect.minX + 6, y: rect.minY + 5, width: rect.width * 0.53, height: 16), 8.5, .bold, .white)
        draw("QTY", CGRect(x: rect.minX + rect.width * 0.55, y: rect.minY + 5, width: rect.width * 0.10, height: 16), 8.5, .bold, .white, .center)
        draw("PRICE", CGRect(x: rect.minX + rect.width * 0.66, y: rect.minY + 5, width: rect.width * 0.15, height: 16), 8.5, .bold, .white, .right)
        draw("AMOUNT", CGRect(x: rect.minX + rect.width * 0.82, y: rect.minY + 5, width: rect.width * 0.17 - 5, height: 16), 8.5, .bold, .white, .right)

        let titleFont: CGFloat = 8.3
        let secondaryFont: CGFloat = 7.0
        let descriptionWidth = rect.width * 0.53
        let rowHeights = itemRowHeights(items, width: descriptionWidth, titleFont: titleFont, secondaryFont: secondaryFont)
        let summaryH: CGFloat = includeTotals ? (quotation.discountAmount > 0 ? 54 : 36) : 0
        var y = rect.minY + headerH

        for (offset, item) in items.enumerated() {
            let rowH = rowHeights.indices.contains(offset) ? rowHeights[offset] : 22
            let rowBottomLimit = rect.maxY - summaryH
            guard y + rowH <= rowBottomLimit + 0.5 else { break }

            UIColor(white: 0.965, alpha: 1).setFill()
            UIRectFill(CGRect(x: rect.minX, y: y, width: rect.width, height: max(0, rowH - 1)))

            let descriptionRect = CGRect(x: rect.minX + 6, y: y + 3, width: descriptionWidth, height: max(10, rowH - 5))
            let titleHeight = measuredTextHeight(item.description, width: descriptionRect.width, size: titleFont, weight: .semibold)
            draw(item.description, CGRect(x: descriptionRect.minX, y: descriptionRect.minY, width: descriptionRect.width, height: titleHeight), titleFont, .semibold, dark)

            if item.hasSecondaryText {
                let secondaryY = descriptionRect.minY + titleHeight + 1
                let secondaryHeight = measuredTextHeight(item.secondaryDisplayText, width: descriptionRect.width, size: secondaryFont, weight: .regular)
                draw(item.secondaryDisplayText, CGRect(x: descriptionRect.minX, y: secondaryY, width: descriptionRect.width, height: secondaryHeight), secondaryFont, .regular, .darkGray)
            }

            let valueY = y + max(4, (rowH - 18) / 2)
            draw(String(format: "%.2f", item.quantity), CGRect(x: rect.minX + rect.width * 0.55, y: valueY, width: rect.width * 0.10, height: 18), 8.0, .regular, dark, .center)
            draw(CurrencyFormatter.string(item.unitPrice, code: company.currencyCode), CGRect(x: rect.minX + rect.width * 0.66, y: valueY, width: rect.width * 0.15, height: 18), 7.4, .regular, dark, .right)
            draw(CurrencyFormatter.string(item.amount, code: company.currencyCode), CGRect(x: rect.minX + rect.width * 0.82, y: valueY, width: rect.width * 0.17 - 5, height: 18), 7.4, .semibold, dark, .right)
            y += rowH
        }

        guard includeTotals else { return }
        let baseY = rect.maxY - summaryH
        draw("SUBTOTAL", CGRect(x: rect.minX + rect.width * 0.58, y: baseY + 3, width: rect.width * 0.18, height: 16), 8.8, .bold, dark)
        draw(CurrencyFormatter.string(quotation.subtotal, code: company.currencyCode), CGRect(x: rect.minX + rect.width * 0.76, y: baseY + 3, width: rect.width * 0.23 - 4, height: 16), 8.8, .semibold, dark, .right)
        if quotation.discountAmount > 0 {
            draw("DISCOUNT", CGRect(x: rect.minX + rect.width * 0.58, y: baseY + 20, width: rect.width * 0.18, height: 16), 8.5, .bold, .systemRed)
            draw("-" + CurrencyFormatter.string(quotation.discountAmount, code: company.currencyCode), CGRect(x: rect.minX + rect.width * 0.76, y: baseY + 20, width: rect.width * 0.23 - 4, height: 16), 8.5, .semibold, .systemRed, .right)
        }
        let totalY = rect.maxY - 20
        gold.setFill(); UIRectFill(CGRect(x: rect.minX + rect.width * 0.58, y: totalY, width: rect.width * 0.42, height: 20))
        draw("TOTAL", CGRect(x: rect.minX + rect.width * 0.60, y: totalY + 3, width: rect.width * 0.13, height: 15), 9.5, .heavy, dark)
        draw(CurrencyFormatter.string(quotation.total, code: company.currencyCode), CGRect(x: rect.minX + rect.width * 0.73, y: totalY + 3, width: rect.width * 0.25 - 4, height: 15), 9.5, .heavy, dark, .right)
    }

    private func drawContinuationLabel(pageNumber: Int) {
        draw("CONTINUED • PAGE \(pageNumber)", CGRect(x: page.width * 0.62, y: page.height * 0.135, width: page.width * 0.31, height: 16), 8.5, .semibold, .darkGray, .right)
    }

    private func drawPageNumber(_ number: Int, of total: Int, settings: InvoicePDFSettings) {
        guard total > 1 else { return }
        let footerTop = settings.showFooter ? zone(.footer, settings: settings).minY : page.height - 18
        draw("Page \(number) of \(total)", CGRect(x: page.width * 0.78, y: footerTop - 16, width: page.width * 0.15, height: 12), 7.2, .medium, .darkGray, .right)
    }

    private func itemRowHeights(_ items: [InvoiceLineItem], width: CGFloat, titleFont: CGFloat, secondaryFont: CGFloat) -> [CGFloat] {
        items.map { item in
            let titleHeight = measuredTextHeight(item.description, width: width, size: titleFont, weight: .semibold)
            let secondaryHeight = item.hasSecondaryText ? measuredTextHeight(item.secondaryDisplayText, width: width, size: secondaryFont, weight: .regular) : 0
            return max(22, 7 + titleHeight + (secondaryHeight > 0 ? secondaryHeight + 2 : 0))
        }
    }

    private func measuredTextHeight(_ text: String, width: CGFloat, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
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

    private func drawSummary(quotation: Quotation, company: CompanyProfile, bankAccount: BankAccount?, settings: InvoicePDFSettings) {
        let rect = zone(.payment, settings: settings).insetBy(dx: 2, dy: 2)
        let title = settings.paymentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "SUMMARY / PAYMENT" : settings.paymentTitle
        draw(title, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 20), 11.5, .bold, green)
        var lines = ["Quotation Total: \(CurrencyFormatter.string(quotation.total, code: company.currencyCode))"]
        if let bankAccount {
            if !bankAccount.bankName.isEmpty { lines.append("Bank: \(bankAccount.bankName)") }
            if !bankAccount.iban.isEmpty { lines.append("IBAN: \(bankAccount.iban)") }
        }
        draw(lines.joined(separator: "\n"), CGRect(x: rect.minX, y: rect.minY + 23, width: rect.width, height: max(18, rect.height - 23)), 8.6, .regular, dark)
    }

    private func drawTerms(quotation: Quotation, settings: InvoicePDFSettings) {
        let rect = zone(.terms, settings: settings).insetBy(dx: 2, dy: 2)
        let title = settings.termsTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "TERMS / NOTES" : settings.termsTitle
        draw(title, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 20), 11.5, .bold, green)
        draw(quotation.notes, CGRect(x: rect.minX, y: rect.minY + 22, width: rect.width, height: max(18, rect.height - 22)), 8.7, .regular, dark)
    }

    private func drawFooter(settings: InvoicePDFSettings) {
        let rect = zone(.footer, settings: settings)
        green.setFill(); UIRectFill(rect)
        let text = settings.footerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? InvoicePDFSettings.aspireQuotationDefault.footerText : settings.footerText
        draw(text, rect.insetBy(dx: 3, dy: 3), 7.5, .medium, .white, .center)
    }

    private func drawOverlayImages(_ overlays: [InvoicePDFOverlayImage]) {
        for overlay in overlays.prefix(12) {
            guard let image = UIImage(data: overlay.imageData) else { continue }
            let rect = CGRect(x: page.width * CGFloat(max(0, min(1, overlay.x))), y: page.height * CGFloat(max(0, min(1, overlay.y))), width: page.width * CGFloat(max(0.03, min(1, overlay.width))), height: page.height * CGFloat(max(0.03, min(1, overlay.height))))
            image.draw(in: aspectFit(image.size, in: rect))
        }
    }

    private func draw(_ text: String, _ rect: CGRect, _ size: CGFloat, _ weight: UIFont.Weight, _ color: UIColor, _ alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment; paragraph.lineBreakMode = .byWordWrapping
        text.draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func aspectFit(_ imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}

struct PaymentReceiptPDFService {
    private let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private let green = UIColor(red: 0.10, green: 0.48, blue: 0.29, alpha: 1)
    private let gold = UIColor(red: 0.91, green: 0.63, blue: 0.15, alpha: 1)
    private let dark = UIColor(red: 0.12, green: 0.16, blue: 0.15, alpha: 1)

    func makePDF(
        invoice: Invoice,
        customer: Customer,
        company: CompanyProfile,
        settings: InvoicePDFSettings = .aspireReceiptDefault,
        bankAccount: BankAccount?,
        appLogoData: Data?,
        employeeName: String?
    ) -> Data {
        UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            UIColor.white.setFill(); UIRectFill(page)
            green.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: page.width, height: 12))
            if settings.showLogo, let logo = (settings.logoData ?? appLogoData).flatMap(UIImage.init(data:)) ?? UIImage(named: "AspireLogo") {
                logo.draw(in: aspectFit(logo.size, in: zone(.logo, settings: settings).insetBy(dx: 3, dy: 3)))
            }
            if settings.showCompanyName {
                let value = settings.companyNameOverride.isEmpty ? company.fullName : settings.companyNameOverride
                draw(value, zone(.companyName, settings: settings), 13.5, .bold, green)
            }
            if settings.showCompanyContact {
                let automatic = [company.address, company.phone, company.email, company.website].filter { !$0.isEmpty }.joined(separator: "  •  ")
                draw(settings.companyContactOverride.isEmpty ? automatic : settings.companyContactOverride, zone(.companyContact, settings: settings), 8.2, .regular, .darkGray, .center)
            }
            let titleRect = zone(.invoiceTitle, settings: settings)
            draw(settings.invoiceTitle.isEmpty ? "PAYMENT RECEIPT" : settings.invoiceTitle, CGRect(x: titleRect.minX, y: titleRect.minY, width: titleRect.width, height: titleRect.height * 0.65), 25, .heavy, dark, .right)
            draw("Receipt for \(invoice.number)", CGRect(x: titleRect.minX, y: titleRect.minY + titleRect.height * 0.67, width: titleRect.width, height: titleRect.height * 0.30), 9.2, .semibold, green, .right)

            if settings.showPaymentStatus {
                let rect = zone(.paymentStatus, settings: settings)
                green.withAlphaComponent(0.11).setFill(); UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
                draw(settings.paidText.isEmpty ? "PAID" : settings.paidText, rect.insetBy(dx: 4, dy: 4), 11, .heavy, green, .center)
            }
            if settings.showBillTo {
                let rect = zone(.billTo, settings: settings)
                draw(settings.billToTitle.isEmpty ? "RECEIVED FROM" : settings.billToTitle, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 20), 12, .bold, green)
                draw(customer.name, CGRect(x: rect.minX, y: rect.minY + 22, width: rect.width, height: 24), 14, .bold, dark)
                draw([customer.address, customer.phone, customer.email].filter { !$0.isEmpty }.joined(separator: "\n"), CGRect(x: rect.minX, y: rect.minY + 48, width: rect.width, height: max(20, rect.height - 48)), 9, .regular, .darkGray)
            }
            if settings.showInvoiceMeta {
                let rect = zone(.invoiceMeta, settings: settings)
                let paidDate = invoice.paidAt ?? Date()
                var labels = ["INVOICE", "PAYMENT DATE", "PAYMENT STATUS"]
                var values = [invoice.number, DateFormatter.shortDate.string(from: paidDate), invoice.status.title]
                if let employeeName, !employeeName.isEmpty { labels.append("RECORDED BY"); values.append(employeeName) }
                draw(labels.joined(separator: "\n"), CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.46, height: rect.height), 8.6, .bold, dark)
                draw(values.joined(separator: "\n"), CGRect(x: rect.minX + rect.width * 0.47, y: rect.minY, width: rect.width * 0.53, height: rect.height), 8.6, .regular, dark, .right)
            }
            if settings.showItems {
                let rect = zone(.items, settings: settings)
                green.setFill(); UIRectFill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 28))
                draw("PAYMENT RECEIVED", CGRect(x: rect.minX + 8, y: rect.minY + 6, width: rect.width - 16, height: 18), 10, .bold, .white)
                let paid = invoice.amountPaid > 0 ? invoice.amountPaid : invoice.total
                draw("Amount Received", CGRect(x: rect.minX + 8, y: rect.minY + 45, width: rect.width * 0.48, height: 25), 14, .bold, dark)
                draw(CurrencyFormatter.string(paid, code: company.currencyCode), CGRect(x: rect.minX + rect.width * 0.48, y: rect.minY + 40, width: rect.width * 0.48 - 8, height: 34), 20, .heavy, green, .right)
                draw("Invoice Total", CGRect(x: rect.minX + 8, y: rect.minY + 88, width: rect.width * 0.45, height: 20), 10, .semibold, dark)
                draw(CurrencyFormatter.string(invoice.total, code: company.currencyCode), CGRect(x: rect.minX + rect.width * 0.48, y: rect.minY + 88, width: rect.width * 0.48 - 8, height: 20), 10, .semibold, dark, .right)
                draw("Outstanding", CGRect(x: rect.minX + 8, y: rect.minY + 114, width: rect.width * 0.45, height: 20), 10, .semibold, dark)
                draw(CurrencyFormatter.string(invoice.outstanding, code: company.currencyCode), CGRect(x: rect.minX + rect.width * 0.48, y: rect.minY + 114, width: rect.width * 0.48 - 8, height: 20), 10, .semibold, dark, .right)
            }
            if settings.showPayment {
                let rect = zone(.payment, settings: settings)
                draw(settings.paymentTitle.isEmpty ? "PAYMENT DETAILS" : settings.paymentTitle, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 20), 12, .bold, green)
                var lines = ["Invoice: \(invoice.number)", "Payment Date: \(DateFormatter.shortDate.string(from: invoice.paidAt ?? Date()))"]
                if let bankAccount, !bankAccount.label.isEmpty { lines.append("Account: \(bankAccount.label)") }
                draw(lines.joined(separator: "\n"), CGRect(x: rect.minX, y: rect.minY + 24, width: rect.width, height: max(20, rect.height - 24)), 9, .regular, dark)
            }
            if settings.showTerms {
                let rect = zone(.terms, settings: settings)
                draw(settings.termsTitle.isEmpty ? "REFERENCE / NOTES" : settings.termsTitle, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 20), 11.5, .bold, green)
                draw("Payment received against \(invoice.number). \(invoice.notes)", CGRect(x: rect.minX, y: rect.minY + 22, width: rect.width, height: max(20, rect.height - 22)), 8.8, .regular, dark)
            }
            drawOverlayImages(settings.overlayImages)
            if settings.showFooter {
                let rect = zone(.footer, settings: settings)
                green.setFill(); UIRectFill(rect)
                draw(settings.footerText.isEmpty ? InvoicePDFSettings.aspireReceiptDefault.footerText : settings.footerText, rect.insetBy(dx: 3, dy: 3), 7.5, .medium, .white, .center)
            }
        }
    }

    private func zone(_ zone: PDFEditableZone, settings: InvoicePDFSettings) -> CGRect {
        let n = settings.frame(for: zone)
        return CGRect(x: page.width * n.x, y: page.height * n.y, width: page.width * n.width, height: page.height * n.height)
    }

    private func drawOverlayImages(_ overlays: [InvoicePDFOverlayImage]) {
        for overlay in overlays.prefix(12) {
            guard let image = UIImage(data: overlay.imageData) else { continue }
            let rect = CGRect(x: page.width * CGFloat(max(0, min(1, overlay.x))), y: page.height * CGFloat(max(0, min(1, overlay.y))), width: page.width * CGFloat(max(0.03, min(1, overlay.width))), height: page.height * CGFloat(max(0.03, min(1, overlay.height))))
            image.draw(in: aspectFit(image.size, in: rect))
        }
    }

    private func draw(_ text: String, _ rect: CGRect, _ size: CGFloat, _ weight: UIFont.Weight, _ color: UIColor, _ alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment; paragraph.lineBreakMode = .byWordWrapping
        text.draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func aspectFit(_ imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}
