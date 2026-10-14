import Foundation

/// Everything needed to render an invoice (preview and PDF), built from settings, client and shifts.
public struct InvoiceDocument: Hashable, Sendable {
    public struct Party: Hashable, Sendable {
        public var name: String
        public var lines: [String]
    }
    public struct ShiftLine: Hashable, Sendable {
        public var date: CivilDate
        public var start: TimeOfDay
        public var end: TimeOfDay
        public var hours: Double
        public var amount: Double
        public var isSleepover: Bool
        public var notes: String?
    }

    public var number: String
    public var issueDate: CivilDate
    public var dueDate: CivilDate
    public var period: DateRange
    public var from: Party
    public var billTo: Party
    public var participantName: String?
    public var participantNumber: String?
    public var groups: [InvoiceLineGroup]
    public var shiftLines: [ShiftLine]
    public var total: Double
    public var notes: String?
    public var payment: [String]
    public var isPaid: Bool

    /// Builds the document. `shifts` should already be filtered to the client and period.
    public static func build(
        number: String,
        issueDate: CivilDate,
        period: DateRange,
        settings: UserSettings,
        client: Client?,
        shifts: [Shift],
        isPaid: Bool = false
    ) -> InvoiceDocument {
        let rates = RateResolver.effectiveRates(clientOverrides: client?.rateOverrides,
                                                useCustomRates: client?.useCustomRates ?? false,
                                                global: settings.rateOverrides)
        let sorted = shifts.sorted { ($0.date, $0.startTime) < ($1.date, $1.startTime) }
        let groups = InvoiceGrouping.group(sorted, rates: rates, evening: settings.eveningWindow)

        var fromLines: [String] = []
        if let abn = settings.abn, !abn.isEmpty { fromLines.append("ABN \(abn)") }
        for v in [settings.address, settings.email, settings.phone] { if let v, !v.isEmpty { fromLines.append(v) } }

        var billName = client?.shownName ?? "Client"
        var billLines: [String] = []
        if let c = client {
            if c.usePlanManager, let org = c.organisationName, !org.isEmpty { billName = org }
            for v in [c.billingContact, c.billingAddress, c.email] { if let v, !v.isEmpty { billLines.append(v) } }
        }

        var payment: [String] = []
        if let v = settings.accountName, !v.isEmpty { payment.append("Account name: \(v)") }
        if let v = settings.bankName, !v.isEmpty { payment.append("Bank: \(v)") }
        if let v = settings.bsb, !v.isEmpty { payment.append("BSB: \(v)") }
        if let v = settings.accountNumber, !v.isEmpty { payment.append("Account: \(v)") }

        let clientNotes = client?.invoiceNotes?.isEmpty == false ? client?.invoiceNotes : nil
        let notes = clientNotes ?? (settings.useDefaultInvoiceNotes ? settings.invoiceNotes : nil)

        return InvoiceDocument(
            number: number, issueDate: issueDate,
            dueDate: InvoiceNumbering.dueDate(issued: issueDate, dueDays: settings.invoiceDueDays),
            period: period,
            from: Party(name: settings.businessName?.isEmpty == false ? settings.businessName! : "Support Worker", lines: fromLines),
            billTo: Party(name: billName, lines: billLines),
            participantName: client?.shownName,
            participantNumber: client?.participantNumber,
            groups: groups,
            shiftLines: sorted.map { ShiftLine(date: $0.date, start: $0.startTime, end: $0.endTime, hours: $0.hoursWorked,
                                                amount: $0.effectiveGross, isSleepover: $0.isSleepover, notes: $0.notes) },
            total: InvoiceGrouping.total(groups),
            notes: notes, payment: payment, isPaid: isPaid
        )
    }

    /// Line items to persist in `invoice_items`.
    public func items(invoiceId: UUID) -> [InvoiceItem] {
        groups.map {
            InvoiceItem(invoiceId: invoiceId, description: "\($0.label) (\($0.ndisCode))",
                        hours: $0.isSleepover ? nil : $0.quantity, rate: $0.rate, amount: $0.subtotal)
        }
    }

    /// Safe filename: "INV-007 Jordan Smith 2026-10-12.pdf".
    public var fileName: String {
        let raw = "\(number) \(participantName ?? billTo.name) \(period.start.iso).pdf"
        return raw.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
    }
}
