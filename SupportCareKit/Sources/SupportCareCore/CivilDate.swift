import Foundation

/// A timezone-free calendar date (matches Postgres `DATE` and the web app's "YYYY-MM-DD" strings).
public struct CivilDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "YYYY-MM-DD".
    public init?(_ string: String) {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso }

    // MARK: Day arithmetic (Howard Hinnant's days-from-civil, proleptic Gregorian)

    /// Days since 1970-01-01.
    public var daysSinceEpoch: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public init(daysSinceEpoch z0: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yoe + era * 400 + (m <= 2 ? 1 : 0), month: m, day: d)
    }

    public func adding(days: Int) -> CivilDate { CivilDate(daysSinceEpoch: daysSinceEpoch + days) }

    /// 0 = Sunday … 6 = Saturday (same as JS `Date.getDay()`).
    public var weekday: Int {
        let w = (daysSinceEpoch + 4) % 7 // 1970-01-01 was a Thursday
        return w < 0 ? w + 7 : w
    }

    public var isWeekend: Bool { weekday == 0 || weekday == 6 }

    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool { lhs.daysSinceEpoch < rhs.daysSinceEpoch }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        let next = month == 12 ? CivilDate(year: year + 1, month: 1, day: 1) : CivilDate(year: year, month: month + 1, day: 1)
        return next.daysSinceEpoch - CivilDate(year: year, month: month, day: 1).daysSinceEpoch
    }

    // MARK: Foundation bridging

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    public static func today(calendar: Calendar = .current) -> CivilDate { CivilDate(Date(), calendar: calendar) }

    // MARK: Codable as "YYYY-MM-DD"

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = CivilDate(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }
}

/// A wall-clock time (matches Postgres `TIME`, e.g. "09:30" or "09:30:00").
public struct TimeOfDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// Minutes since midnight, 0..<1440. 1440 is allowed to represent "end of day" (24:00).
    public let minutes: Int

    public init(minutes: Int) { self.minutes = max(0, min(minutes, 1440)) }
    public init(hour: Int, minute: Int = 0) { self.init(minutes: hour * 60 + minute) }

    public init?(_ string: String) {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...24).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        self.init(minutes: parts[0] * 60 + parts[1])
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    /// "HH:MM" (24h). 1440 encodes as "24:00".
    public var hhmm: String { String(format: "%02d:%02d", hour, minute) }
    public var description: String { hhmm }

    /// "9:00 AM" style, matching `formatTime12h`.
    public var twelveHour: String {
        let h = hour % 24
        let period = h >= 12 ? "PM" : "AM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):\(String(format: "%02d", minute)) \(period)"
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let t = TimeOfDay(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad time \(s)"))
        }
        self = t
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(minutes >= 1440 ? "23:59:59" : hhmm + ":00")
    }
}
