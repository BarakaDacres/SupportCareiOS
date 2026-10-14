import Foundation

public struct DateRange: Hashable, Sendable, Identifiable {
    public var start: CivilDate
    public var end: CivilDate // inclusive
    public var label: String
    public var number: Int?

    public init(start: CivilDate, end: CivilDate, label: String, number: Int? = nil) {
        self.start = start; self.end = end; self.label = label; self.number = number
    }

    public var id: String { start.iso + "_" + end.iso }
    public func contains(_ d: CivilDate) -> Bool { d >= start && d <= end }
    public var days: [CivilDate] { (0...(end.daysSinceEpoch - start.daysSinceEpoch)).map { start.adding(days: $0) } }
}

public enum Periods {
    static let monthShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    public static func shortDate(_ d: CivilDate) -> String { String(format: "%02d ", d.day) + monthShort[d.month - 1] }
    public static func mediumDate(_ d: CivilDate) -> String { "\(d.day) \(monthShort[d.month - 1]) \(d.year)" }

    /// Start of the week containing `date`. `weekStart`: 0 = Sun … 6 = Sat (default Monday).
    public static func weekStart(containing date: CivilDate, weekStart: Int = 1) -> CivilDate {
        let diff = (date.weekday - weekStart + 7) % 7
        return date.adding(days: -diff)
    }

    public static func week(containing date: CivilDate, weekStart ws: Int = 1) -> DateRange {
        let s = weekStart(containing: date, weekStart: ws)
        let e = s.adding(days: 6)
        return DateRange(start: s, end: e, label: "\(shortDate(s)) – \(shortDate(e))")
    }

    /// `getWeekRangesForMonth` (generalised to any week start; web uses Monday).
    public static func weeks(year: Int, month: Int, weekStart ws: Int = 1) -> [DateRange] {
        let first = CivilDate(year: year, month: month, day: 1)
        let last = CivilDate(year: year, month: month, day: CivilDate.daysInMonth(year: year, month: month))
        var cursor = weekStart(containing: first, weekStart: ws)
        var out: [DateRange] = []
        while cursor <= last {
            let e = cursor.adding(days: 6)
            out.append(DateRange(start: cursor, end: e, label: "\(shortDate(cursor)) – \(shortDate(e))"))
            cursor = cursor.adding(days: 7)
        }
        return out
    }

    /// `getFortnightPeriodsForYear` from InvoicePanel: anchored on the Monday on/before 1 Jan,
    /// labelled "FN01 · 29 Dec 2025 – 11 Jan 2026".
    public static func fortnights(year: Int) -> [DateRange] {
        let jan1 = CivilDate(year: year, month: 1, day: 1)
        let daysToMon = jan1.weekday == 0 ? 6 : jan1.weekday - 1
        var cursor = jan1.adding(days: -daysToMon)
        var out: [DateRange] = []
        var fn = 1
        while true {
            if cursor.year > year { break }
            let end = cursor.adding(days: 13)
            out.append(DateRange(start: cursor, end: end,
                                 label: "FN" + String(format: "%02d", fn) + " · \(mediumDate(cursor)) – \(mediumDate(end))",
                                 number: fn))
            fn += 1
            cursor = cursor.adding(days: 14)
            if cursor.year > year { break }
        }
        return out
    }

    public static func currentFortnightIndex(_ periods: [DateRange], today: CivilDate) -> Int {
        periods.firstIndex { $0.contains(today) } ?? max(0, periods.count - 1)
    }

    public static func month(year: Int, month: Int) -> DateRange {
        DateRange(start: CivilDate(year: year, month: month, day: 1),
                  end: CivilDate(year: year, month: month, day: CivilDate.daysInMonth(year: year, month: month)),
                  label: monthShort[month - 1] + " \(year)")
    }

    /// Australian financial year (1 Jul – 30 Jun) containing `date`.
    public static func financialYear(containing date: CivilDate) -> DateRange {
        let startYear = date.month >= 7 ? date.year : date.year - 1
        return DateRange(start: CivilDate(year: startYear, month: 7, day: 1),
                         end: CivilDate(year: startYear + 1, month: 6, day: 30),
                         label: "FY\(String(startYear + 1).suffix(2))")
    }
}
