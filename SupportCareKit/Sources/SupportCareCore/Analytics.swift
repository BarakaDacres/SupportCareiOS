import Foundation

public struct EarningsSummary: Hashable, Sendable {
    public var gross: Double
    public var hours: Double
    public var shiftCount: Int
    public var sleepovers: Int

    public static let zero = EarningsSummary(gross: 0, hours: 0, shiftCount: 0, sleepovers: 0)

    public var averagePerShift: Double { shiftCount == 0 ? 0 : gross / Double(shiftCount) }
    public var effectiveHourly: Double { hours == 0 ? 0 : gross / hours }
}

public struct MonthlyEarnings: Hashable, Sendable, Identifiable {
    public var year: Int
    public var month: Int
    public var summary: EarningsSummary
    public var id: String { "\(year)-\(month)" }
}

public enum Analytics {
    public static func summarize<S: Sequence>(_ shifts: S) -> EarningsSummary where S.Element == Shift {
        var s = EarningsSummary.zero
        for sh in shifts {
            s.gross += sh.effectiveGross
            s.hours += sh.hoursWorked
            s.shiftCount += 1
            if sh.isSleepover { s.sleepovers += 1 }
        }
        s.gross = round2(s.gross)
        s.hours = round2(s.hours)
        return s
    }

    public static func summarize(_ shifts: [Shift], in range: DateRange) -> EarningsSummary {
        summarize(shifts.lazy.filter { range.contains($0.date) })
    }

    /// Twelve months ending with the month containing `through`.
    public static func monthly(_ shifts: [Shift], through: CivilDate, count: Int = 12) -> [MonthlyEarnings] {
        var out: [MonthlyEarnings] = []
        var y = through.year, m = through.month
        for _ in 0..<count {
            out.append(MonthlyEarnings(year: y, month: m, summary: summarize(shifts, in: Periods.month(year: y, month: m))))
            m -= 1
            if m == 0 { m = 12; y -= 1 }
        }
        return out.reversed()
    }

    /// Gross by category across shifts (for the breakdown chart).
    public static func byCategory(_ shifts: [Shift], rates: (Shift) -> PayRates, evening: EveningWindow) -> [InvoiceCategory: Double] {
        var out: [InvoiceCategory: Double] = [:]
        for sh in shifts {
            for g in InvoiceGrouping.group([sh], rates: rates(sh), evening: evening) {
                out[g.category, default: 0] += g.subtotal
            }
        }
        return out
    }

    /// Progress toward a goal in 0...1 (nil goal → nil).
    public static func progress(_ value: Double, goal: Double?) -> Double? {
        guard let goal, goal > 0 else { return nil }
        return min(1, max(0, value / goal))
    }
}
