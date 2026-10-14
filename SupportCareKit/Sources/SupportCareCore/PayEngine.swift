import Foundation

/// Input describing one shift for pay purposes.
public struct ShiftInput: Hashable, Sendable {
    public var date: CivilDate
    public var start: TimeOfDay
    public var end: TimeOfDay
    public var isSleepover: Bool
    public var isPublicHoliday: Bool
    public var isOvertime: Bool
    /// When > 0 replaces the calculated gross (`effectiveGrossPay`).
    public var feeOverride: Double?

    public init(
        date: CivilDate, start: TimeOfDay, end: TimeOfDay,
        isSleepover: Bool = false, isPublicHoliday: Bool = false, isOvertime: Bool = false,
        feeOverride: Double? = nil
    ) {
        self.date = date
        self.start = start
        self.end = end
        self.isSleepover = isSleepover
        self.isPublicHoliday = isPublicHoliday
        self.isOvertime = isOvertime
        self.feeOverride = feeOverride
    }

    /// Start/end in minutes from the start date's midnight; end ≤ start crosses midnight.
    public var spanMinutes: (start: Int, end: Int) {
        let s = start.minutes
        var e = end.minutes
        if e <= s { e += 1440 }
        return (s, e)
    }

    public var totalHours: Double { Double(spanMinutes.end - spanMinutes.start) / 60 }
}

public struct PayLine: Hashable, Sendable {
    public var label: String
    public var hours: Double?
    public var rate: Double?
    public var amount: Double
}

public struct ShiftCalculation: Hashable, Sendable {
    public var hoursWorked: Double
    public var grossPay: Double
    public var breakdown: [PayLine]

    /// `fee_override` applied if present (mirrors `effectiveGrossPay`).
    public func effectiveGross(feeOverride: Double?) -> Double {
        if let f = feeOverride, f > 0 { return f }
        return grossPay
    }
}

/// One contiguous piece of a shift that falls on a single calendar day and a single rate zone.
public struct ShiftSegment: Hashable, Sendable {
    public var date: CivilDate
    public var weekday: Int
    public var hours: Double
    public var isEvening: Bool
}

/// Port of `shiftCalculator.ts`.
public enum PayEngine {
    static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// Splits a shift into per-day, per-zone segments (handles midnight crossing + evening split).
    public static func segments(for shift: ShiftInput, evening: EveningWindow) -> [ShiftSegment] {
        let (startMin, endMin) = shift.spanMinutes
        var result: [ShiftSegment] = []
        var cursor = startMin
        while cursor < endMin {
            let dayOffset = cursor / 1440
            let dayStart = dayOffset * 1440
            let segEnd = min(endMin, dayStart + 1440)
            let localStart = cursor - dayStart
            let localEnd = segEnd - dayStart
            let date = shift.date.adding(days: dayOffset)

            let cuts = [evening.startMinutes, evening.endMinutes].filter { $0 > localStart && $0 < localEnd }
            let points = Array(Set([localStart, localEnd] + cuts)).sorted()
            for i in 0..<(points.count - 1) {
                let s = points[i], e = points[i + 1]
                guard e > s else { continue }
                let isEvening = s >= evening.startMinutes && e <= evening.endMinutes
                result.append(ShiftSegment(date: date, weekday: date.weekday, hours: Double(e - s) / 60, isEvening: isEvening))
            }
            cursor = segEnd
        }
        return result
    }

    /// Whether any part of the shift overlaps the evening window (`hasEveningHours`).
    public static func hasEveningHours(_ shift: ShiftInput, evening: EveningWindow) -> Bool {
        segments(for: shift, evening: evening).contains { $0.isEvening }
    }

    /// Sat/Sun start night (`isWeekendSleeperNight`).
    public static func isWeekendSleeperNight(_ weekday: Int) -> Bool { weekday == 0 || weekday == 6 }

    /// Port of `calculateShiftPay`.
    ///
    /// Precedence for hourly shifts: overtime > public holiday > evening (Mon–Fri only) > day rate.
    /// Sleepovers are a flat rate (PH > weekend > weekday) unless overtime, which pays hours × overtime.
    public static func calculate(_ shift: ShiftInput, rates: PayRates = .defaults, evening: EveningWindow = .default) -> ShiftCalculation {
        let totalHours = shift.totalHours

        if shift.isSleepover {
            if shift.isOvertime {
                let amount = round2(totalHours * rates.overtime)
                return ShiftCalculation(
                    hoursWorked: round2(totalHours), grossPay: amount,
                    breakdown: [PayLine(label: "Overtime Sleepover", hours: round2(totalHours), rate: rates.overtime, amount: amount)]
                )
            }
            let rate: Double
            let label: String
            if shift.isPublicHoliday {
                rate = rates.sleepoverPublicHoliday; label = "Public Holiday Sleepover"
            } else if isWeekendSleeperNight(shift.date.weekday) {
                rate = rates.sleepoverWeekend; label = "Weekend Sleepover"
            } else {
                rate = rates.sleepoverWeekday; label = "Weekday Sleepover"
            }
            // Note: web returns unrounded hoursWorked here; values are always whole minutes so this is equivalent.
            return ShiftCalculation(hoursWorked: totalHours, grossPay: rate, breakdown: [PayLine(label: label, hours: nil, rate: nil, amount: rate)])
        }

        var gross = 0.0
        var lines: [PayLine] = []
        for seg in segments(for: shift, evening: evening) {
            let dayName = dayNames[seg.weekday]
            let isWeekday = (1...5).contains(seg.weekday)
            let rate: Double
            let label: String
            if shift.isOvertime {
                rate = rates.overtime; label = "Overtime \(seg.date.iso)"
            } else if shift.isPublicHoliday {
                rate = rates.publicHoliday; label = "Public Holiday \(seg.date.iso)"
            } else if seg.isEvening && isWeekday {
                rate = rates.evening; label = "\(dayName) \(seg.date.iso) (Evening)"
            } else {
                rate = rates.hourly(weekday: seg.weekday)
                label = seg.isEvening ? "\(dayName) \(seg.date.iso) (Evening)" : "\(dayName) \(seg.date.iso)"
            }
            let amount = seg.hours * rate
            gross += amount
            lines.append(PayLine(label: label, hours: round2(seg.hours), rate: rate, amount: round2(amount)))
        }
        return ShiftCalculation(hoursWorked: round2(totalHours), grossPay: round2(gross), breakdown: lines)
    }
}
