import Foundation

/// NDIS line categories. Port of `invoiceGrouping.ts`.
public enum InvoiceCategory: String, CaseIterable, Codable, Sendable {
    case daily, evening, saturday, sunday
    case weekdaySleepover = "weekday_sleepover"
    case saturdaySleepover = "saturday_sleepover"
    case sundaySleepover = "sunday_sleepover"
    case publicHoliday = "public_holiday"
    case publicHolidaySleepover = "public_holiday_sleepover"
    case overtime
    case overtimeSleepover = "overtime_sleepover"

    public var label: String {
        switch self {
        case .daily: "Daily Support"
        case .evening: "Evening Support (Mon–Fri)"
        case .saturday: "Saturday Support"
        case .sunday: "Sunday Support"
        case .weekdaySleepover: "Weekday Sleepover"
        case .saturdaySleepover: "Saturday Sleepover"
        case .sundaySleepover: "Sunday Sleepover"
        case .publicHoliday: "Public Holiday Support"
        case .publicHolidaySleepover: "Public Holiday Sleepover"
        case .overtime: "Overtime Support"
        case .overtimeSleepover: "Overtime Sleepover"
        }
    }

    /// `DEFAULT_NDIS_CODES`.
    public var defaultNdisCode: String {
        switch self {
        case .daily, .overtime: "01_011_0107_1_1"
        case .evening: "01_015_0107_1_1"
        case .saturday: "01_013_0107_1_1"
        case .sunday: "01_014_0107_1_1"
        case .publicHoliday: "01_012_0107_1_1"
        case .weekdaySleepover, .saturdaySleepover, .sundaySleepover, .publicHolidaySleepover, .overtimeSleepover:
            "01_019_0107_1_1"
        }
    }

    public var isSleepover: Bool { rawValue.hasSuffix("sleepover") }

    public func rate(_ rates: PayRates) -> Double {
        switch self {
        case .overtime, .overtimeSleepover: rates.overtime
        case .publicHolidaySleepover: rates.sleepoverPublicHoliday
        case .publicHoliday: rates.publicHoliday
        case .saturday: rates.saturday
        case .sunday: rates.sunday
        case .evening: rates.evening
        case .weekdaySleepover: rates.sleepoverWeekday
        case .saturdaySleepover, .sundaySleepover: rates.sleepoverWeekend
        case .daily: rates.weekday
        }
    }

    /// Output order on the invoice.
    ///
    /// The web app's ORDER list leaves out `overtime` and `overtime_sleepover`, so overtime shifts
    /// silently disappear from its invoices. That's a bug. Here they're appended at the end.
    public static let invoiceOrder: [InvoiceCategory] = [
        .daily, .evening, .saturday, .sunday,
        .weekdaySleepover, .saturdaySleepover, .sundaySleepover,
        .publicHoliday, .publicHolidaySleepover,
        .overtime, .overtimeSleepover,
    ]
}

public struct InvoiceLineGroup: Hashable, Sendable, Identifiable {
    public var category: InvoiceCategory
    public var label: String
    public var ndisCode: String
    public var shiftIds: [UUID]
    public var totalHours: Double
    /// Hours for hourly lines, nights for sleepovers.
    public var quantity: Double
    public var rate: Double
    public var subtotal: Double
    public var isSleepover: Bool

    public var id: InvoiceCategory { category }
}

public enum InvoiceGrouping {
    /// Decomposes a non-sleepover shift into categorised hour segments (`segmentShift`).
    public static func segments(_ shift: ShiftInput, evening: EveningWindow) -> [(category: InvoiceCategory, hours: Double)] {
        PayEngine.segments(for: shift, evening: evening).map { seg in
            let isWeekday = (1...5).contains(seg.weekday)
            let category: InvoiceCategory =
                if shift.isOvertime { .overtime }
                else if shift.isPublicHoliday { .publicHoliday }
                else if seg.isEvening && isWeekday { .evening }
                else if seg.weekday == 6 { .saturday }
                else if seg.weekday == 0 { .sunday }
                else { .daily }
            return (category, seg.hours)
        }
    }

    public static func sleepoverCategory(_ shift: ShiftInput) -> InvoiceCategory {
        if shift.isOvertime { return .overtimeSleepover }
        if shift.isPublicHoliday { return .publicHolidaySleepover }
        switch shift.date.weekday {
        case 6: return .saturdaySleepover
        case 0: return .sundaySleepover
        default: return .weekdaySleepover
        }
    }

    private struct Bucket {
        var shiftIds: [UUID] = []
        var hours = 0.0
        var count = 0
        var overrideAdjustment = 0.0

        mutating func add(_ id: UUID) { if !shiftIds.contains(id) { shiftIds.append(id) } }
    }

    /// Port of `groupShiftsForInvoice`. `fee_override` deltas are attributed to the dominant category
    /// so that subtotal = Σ(qty × rate) + adjustments.
    public static func group(
        _ shifts: [Shift],
        rates: PayRates,
        evening: EveningWindow = .default,
        codes: [InvoiceCategory: String] = [:]
    ) -> [InvoiceLineGroup] {
        var buckets: [InvoiceCategory: Bucket] = [:]

        for shift in shifts {
            let input = shift.input
            let hasOverride = (shift.feeOverride ?? 0) > 0

            if shift.isSleepover {
                let cat = sleepoverCategory(input)
                buckets[cat, default: Bucket()].add(shift.id)
                buckets[cat]!.count += 1
                if hasOverride {
                    buckets[cat]!.overrideAdjustment += shift.effectiveGross - cat.rate(rates)
                }
                continue
            }

            let segs = segments(input, evening: evening)
            for seg in segs {
                buckets[seg.category, default: Bucket()].add(shift.id)
                buckets[seg.category]!.hours += seg.hours
            }
            if hasOverride {
                let primary = segs.reduce(segs.first ?? (InvoiceCategory.daily, 0)) { $1.hours > $0.hours ? $1 : $0 }
                let standard = segs.reduce(0.0) { $0 + $1.hours * $1.category.rate(rates) }
                buckets[primary.category, default: Bucket()].overrideAdjustment += shift.effectiveGross - standard
            }
        }

        var groups: [InvoiceLineGroup] = []
        for cat in InvoiceCategory.invoiceOrder {
            guard let b = buckets[cat] else { continue }
            let rate = cat.rate(rates)
            let code = codes[cat] ?? cat.defaultNdisCode
            if cat.isSleepover {
                guard b.count > 0 else { continue }
                groups.append(InvoiceLineGroup(
                    category: cat, label: cat.label, ndisCode: code, shiftIds: b.shiftIds,
                    totalHours: 0, quantity: Double(b.count), rate: rate,
                    subtotal: round2(Double(b.count) * rate + b.overrideAdjustment), isSleepover: true))
            } else {
                guard b.hours != 0 else { continue }
                let qty = round2(b.hours)
                groups.append(InvoiceLineGroup(
                    category: cat, label: cat.label, ndisCode: code, shiftIds: b.shiftIds,
                    totalHours: qty, quantity: qty, rate: rate,
                    subtotal: round2(qty * rate + b.overrideAdjustment), isSleepover: false))
            }
        }
        return groups
    }

    /// Invoice total = sum of line subtotals (NDIS supports are GST-free, so no GST is added).
    public static func total(_ groups: [InvoiceLineGroup]) -> Double {
        round2(groups.reduce(0) { $0 + $1.subtotal })
    }
}

public enum InvoiceNumbering {
    /// `INV-001`.
    public static func format(_ n: Int) -> String { "INV-" + String(format: "%03d", n) }

    /// Lowest free INV-NNN slot (`nextAvailableInvoiceNumber`). Ignores non-matching numbers.
    public static func nextAvailable(existing: [String]) -> Int {
        var used = Set<Int>()
        for s in existing {
            let upper = s.uppercased()
            guard upper.hasPrefix("INV-") else { continue }
            let digits = upper.dropFirst(4)
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let n = Int(digits) else { continue }
            used.insert(n)
        }
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }

    /// Due date = issue date + due days.
    public static func dueDate(issued: CivilDate, dueDays: Int) -> CivilDate { issued.adding(days: dueDays) }
}
