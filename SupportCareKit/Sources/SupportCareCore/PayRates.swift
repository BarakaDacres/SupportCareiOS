import Foundation

/// Effective AUD pay rates. Mirrors `PayRates` in `shiftCalculator.ts`.
public struct PayRates: Hashable, Sendable, Codable {
    public var weekday: Double            // Mon–Fri hourly (daytime)
    public var saturday: Double           // Saturday hourly
    public var sunday: Double             // Sunday hourly
    public var evening: Double            // Evening window hourly (Mon–Fri only)
    public var publicHoliday: Double      // Public holiday hourly
    public var overtime: Double           // Overtime hourly (overrides all)
    public var sleepoverWeekday: Double   // Flat per night Mon–Fri
    public var sleepoverWeekend: Double   // Flat per night Sat/Sun
    public var sleepoverPublicHoliday: Double

    public init(
        weekday: Double, saturday: Double, sunday: Double, evening: Double,
        publicHoliday: Double, overtime: Double,
        sleepoverWeekday: Double, sleepoverWeekend: Double, sleepoverPublicHoliday: Double
    ) {
        self.weekday = weekday
        self.saturday = saturday
        self.sunday = sunday
        self.evening = evening
        self.publicHoliday = publicHoliday
        self.overtime = overtime
        self.sleepoverWeekday = sleepoverWeekday
        self.sleepoverWeekend = sleepoverWeekend
        self.sleepoverPublicHoliday = sleepoverPublicHoliday
    }

    /// `DEFAULT_RATES` from the web app.
    public static let defaults = PayRates(
        weekday: 60, saturday: 75, sunday: 90, evening: 75,
        publicHoliday: 150, overtime: 90,
        sleepoverWeekday: 300, sleepoverWeekend: 350, sleepoverPublicHoliday: 400
    )

    /// Daytime hourly rate for a weekday index (0 = Sun … 6 = Sat).
    public func hourly(weekday dow: Int) -> Double {
        switch dow {
        case 0: sunday
        case 6: saturday
        default: weekday
        }
    }
}

/// Nullable per-field overrides (client custom rates or partially loaded settings).
public struct RateOverrides: Hashable, Sendable {
    public var weekday: Double?
    public var saturday: Double?
    public var sunday: Double?
    public var evening: Double?
    public var publicHoliday: Double?
    public var overtime: Double?
    public var sleepoverWeekday: Double?
    public var sleepoverWeekend: Double?
    public var sleepoverPublicHoliday: Double?

    public init(
        weekday: Double? = nil, saturday: Double? = nil, sunday: Double? = nil, evening: Double? = nil,
        publicHoliday: Double? = nil, overtime: Double? = nil,
        sleepoverWeekday: Double? = nil, sleepoverWeekend: Double? = nil, sleepoverPublicHoliday: Double? = nil
    ) {
        self.weekday = weekday
        self.saturday = saturday
        self.sunday = sunday
        self.evening = evening
        self.publicHoliday = publicHoliday
        self.overtime = overtime
        self.sleepoverWeekday = sleepoverWeekday
        self.sleepoverWeekend = sleepoverWeekend
        self.sleepoverPublicHoliday = sleepoverPublicHoliday
    }

    public func applied(over base: PayRates) -> PayRates {
        PayRates(
            weekday: weekday ?? base.weekday,
            saturday: saturday ?? base.saturday,
            sunday: sunday ?? base.sunday,
            evening: evening ?? base.evening,
            publicHoliday: publicHoliday ?? base.publicHoliday,
            overtime: overtime ?? base.overtime,
            sleepoverWeekday: sleepoverWeekday ?? base.sleepoverWeekday,
            sleepoverWeekend: sleepoverWeekend ?? base.sleepoverWeekend,
            sleepoverPublicHoliday: sleepoverPublicHoliday ?? base.sleepoverPublicHoliday
        )
    }
}

/// Mirrors `getEffectiveRates` in `rateResolver.ts`:
/// client custom rate (if enabled and set) → user settings → `PayRates.defaults`.
public enum RateResolver {
    public static func effectiveRates(
        clientOverrides: RateOverrides?,
        useCustomRates: Bool,
        global: RateOverrides?
    ) -> PayRates {
        let base = (global ?? RateOverrides()).applied(over: .defaults)
        guard useCustomRates, let client = clientOverrides else { return base }
        return client.applied(over: base)
    }
}

/// The time-of-day window that attracts the evening rate on weekdays.
///
/// The web app's comments say 18:00–22:00 but its code defaults to 18:00–24:00 (midnight).
/// Here it's an explicit, user-configurable setting that defaults to the *actual* behaviour, 18:00–24:00.
public struct EveningWindow: Hashable, Sendable, Codable {
    public var startMinutes: Int
    /// Exclusive end in minutes since midnight. 1440 means midnight.
    public var endMinutes: Int

    public init(start: TimeOfDay, end: TimeOfDay) {
        startMinutes = start.minutes
        // "00:00" as an end means midnight (matches getEveningEndMin()).
        endMinutes = end.minutes == 0 ? 1440 : end.minutes
    }

    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes == 0 ? 1440 : endMinutes
    }

    public static let `default` = EveningWindow(startMinutes: 18 * 60, endMinutes: 1440)

    public var start: TimeOfDay { TimeOfDay(minutes: startMinutes) }
    public var end: TimeOfDay { TimeOfDay(minutes: endMinutes) }
}
