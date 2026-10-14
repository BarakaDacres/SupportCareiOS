import UIKit
import SupportCareCore

/// Renders an `InvoiceDocument` to a vector A4 PDF with UIGraphicsPDFRenderer. Text stays
/// selectable and searchable. Port of printWeeklyReceipt.ts / jsPDF output. "Paid" is shown
/// as understated text near the total, not a stamp (see roadmap.md).
enum InvoicePDFRenderer {
    static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 @ 72dpi
    static let margin: CGFloat = 48

    static func render(_ doc: InvoiceDocument) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Invoice \(doc.number)",
            kCGPDFContextCreator as String: "Support Care",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        return renderer.pdfData { ctx in
            var y: CGFloat = margin
            ctx.beginPage()
            let width = page.width - margin * 2
            let accent = UIColor(red: 0, green: 0.478, blue: 1, alpha: 1)

            func newPageIfNeeded(_ needed: CGFloat) {
                if y + needed > page.height - margin { ctx.beginPage(); y = margin }
            }

            @discardableResult
            func text(_ s: String, _ font: UIFont, color: UIColor = .black, x: CGFloat = margin, w: CGFloat? = nil,
                      align: NSTextAlignment = .left, at yPos: CGFloat? = nil) -> CGFloat {
                let p = NSMutableParagraphStyle(); p.alignment = align
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
                let rectW = w ?? width
                let h = (s as NSString).boundingRect(with: CGSize(width: rectW, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin], attributes: attrs, context: nil).height
                (s as NSString).draw(in: CGRect(x: x, y: yPos ?? y, width: rectW, height: h), withAttributes: attrs)
                return ceil(h)
            }

            func rule(_ color: UIColor = UIColor(white: 0.85, alpha: 1)) {
                color.setFill(); UIRectFill(CGRect(x: margin, y: y, width: width, height: 0.75))
            }

            let money: (Double) -> String = MoneyFormat.aud
            let bold = { (s: CGFloat) in UIFont.systemFont(ofSize: s, weight: .bold) }
            let reg = { (s: CGFloat) in UIFont.systemFont(ofSize: s) }
            let grey = UIColor(white: 0.4, alpha: 1)

            // Header
            text("INVOICE", bold(26), color: accent)
            text(doc.number, bold(13), x: margin, w: width, align: .right, at: y + 4)
            y += 36
            text("Issued \(Periods.mediumDate(doc.issueDate))   ·   Due \(Periods.mediumDate(doc.dueDate))", reg(10), color: grey)
            y += 16
            text("Service period: \(Periods.mediumDate(doc.period.start)) – \(Periods.mediumDate(doc.period.end))", reg(10), color: grey)
            y += 28

            // Parties
            let colW = (width - 24) / 2
            let startY = y
            var leftY = startY, rightY = startY
            leftY += text("FROM", bold(9), color: grey, x: margin, w: colW, at: leftY) + 4
            leftY += text(doc.from.name, bold(12), x: margin, w: colW, at: leftY) + 2
            for l in doc.from.lines { leftY += text(l, reg(10), x: margin, w: colW, at: leftY) }
            rightY += text("BILL TO", bold(9), color: grey, x: margin + colW + 24, w: colW, at: rightY) + 4
            rightY += text(doc.billTo.name, bold(12), x: margin + colW + 24, w: colW, at: rightY) + 2
            for l in doc.billTo.lines { rightY += text(l, reg(10), x: margin + colW + 24, w: colW, at: rightY) }
            if let p = doc.participantName, p != doc.billTo.name {
                rightY += text("Participant: \(p)", reg(10), x: margin + colW + 24, w: colW, at: rightY)
            }
            if let n = doc.participantNumber, !n.isEmpty {
                rightY += text("NDIS no. \(n)", reg(10), x: margin + colW + 24, w: colW, at: rightY)
            }
            y = max(leftY, rightY) + 24

            // Line items table
            let cols: [(String, CGFloat, NSTextAlignment)] = [("Support item", 0.42, .left), ("NDIS code", 0.2, .left),
                                                               ("Qty", 0.1, .right), ("Rate", 0.13, .right), ("Amount", 0.15, .right)]
            func row(_ values: [String], font: UIFont, color: UIColor = .black) {
                var x = margin
                var h: CGFloat = 0
                for (i, c) in cols.enumerated() {
                    let w = width * c.1
                    h = max(h, text(values[i], font, color: color, x: x, w: w - 6, align: c.2, at: y))
                    x += w
                }
                y += h + 8
            }
            row(cols.map(\.0), font: bold(9), color: grey)
            rule(); y += 8
            for g in doc.groups {
                newPageIfNeeded(30)
                let qty = g.isSleepover ? "\(Int(g.quantity)) night\(g.quantity == 1 ? "" : "s")" : String(format: "%.2fh", g.quantity)
                row([g.label, g.ndisCode, qty, money(g.rate), money(g.subtotal)], font: reg(10))
            }
            rule(); y += 12

            // Total
            newPageIfNeeded(60)
            text("TOTAL", bold(11), color: grey, x: margin + width * 0.55, w: width * 0.2, align: .left)
            text(money(doc.total), bold(18), x: margin + width * 0.55, w: width * 0.45, align: .right, at: y - 4)
            y += 26
            if doc.isPaid {
                text("Paid, thank you", reg(10), color: UIColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1),
                     x: margin + width * 0.55, w: width * 0.45, align: .right)
                y += 16
            }
            text("GST-free NDIS supports. No GST is payable.", reg(8.5), color: grey, x: margin + width * 0.4, w: width * 0.6, align: .right)
            y += 28

            // Payment + notes
            if !doc.payment.isEmpty {
                newPageIfNeeded(80)
                y += text("PAYMENT DETAILS", bold(9), color: grey) + 4
                for l in doc.payment { y += text(l, reg(10)) }
                y += 4
                y += text("Reference: \(doc.number)", reg(10))
                y += 16
            }
            if let notes = doc.notes, !notes.isEmpty {
                newPageIfNeeded(60)
                y += text("NOTES", bold(9), color: grey) + 4
                y += text(notes, reg(10)) + 16
            }

            // Shift log
            if !doc.shiftLines.isEmpty {
                newPageIfNeeded(60)
                y += text("SHIFT LOG", bold(9), color: grey) + 6
                for s in doc.shiftLines {
                    newPageIfNeeded(30)
                    let line = "\(Periods.mediumDate(s.date))   \(s.start.twelveHour) – \(s.end.twelveHour)\(s.isSleepover ? "  (sleepover)" : "")"
                    text(line, reg(9.5), x: margin, w: width * 0.7)
                    text(s.isSleepover ? "" : MoneyFormat.hours(s.hours), reg(9.5), color: grey, x: margin + width * 0.7, w: width * 0.3, align: .right)
                    y += 14
                    if let n = s.notes, !n.isEmpty { y += text(n, reg(8.5), color: grey, x: margin + 12, w: width - 12) + 4 }
                }
            }
        }
    }

    /// Writes the PDF to a temp file and returns its URL.
    static func file(for doc: InvoiceDocument) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(doc.fileName)
        try render(doc).write(to: url)
        return url
    }

    /// One PDF per invoice, zipped (AGENTS.md: individually shareable records).
    static func zip(_ docs: [InvoiceDocument]) throws -> URL {
        let entries = docs.map { ZipWriter.Entry(name: $0.fileName, data: render($0)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Invoices \(CivilDate.today().iso).zip")
        try ZipWriter.archive(entries).write(to: url)
        return url
    }
}
