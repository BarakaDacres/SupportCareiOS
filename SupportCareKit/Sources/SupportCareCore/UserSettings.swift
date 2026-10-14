import Foundation

/// `public.user_settings` (one row per user).
///
/// The "pref" columns are new in migration `20261014120000_sync_device_prefs.sql`. They used to live
/// only in browser localStorage. They're optional so older databases still decode;
/// use the computed accessors, which apply the web app's defaults.
public struct UserSettings: Codable, Hashable, Sendable {
    public var id: UUID
    public var userId: UUID

    // Business / account
    public var businessName: String?
    public var abn: String?
    public var address: String?
    public var email: String?
    public var phone: String?
    public var bankName: String?
    public var bsb: String?
    public var accountName: String?
    public var accountNumber: String?

    // Invoicing
    public var invoiceNotes: String?
    public var useDefaultInvoiceNotes: Bool
    public var invoiceDueDays: Int
    public var invoiceCounter: Int

    // Tax & goals
    public var taxRate: Double
    public var showTaxEstimate: Bool
    public var weeklyGoal: Double?
    public var monthlyGoal: Double?
    public var yearlyGoal: Double?

    // Rates
    public var rateWeekday: Double
    public var rateSaturday: Double
    public var rateSunday: Double
    public var rateEvening: Double
    public var ratePublicHoliday: Double
    public var rateOvertime: Double
    public var rateSleepoverWeekday: Double
    public var rateSleepoverWeekend: Double
    public var rateSleepoverPublicHoliday: Double

    // Synced preferences (new columns)
    public var eveningStart: TimeOfDay?
    public var eveningEnd: TimeOfDay?
    public var sleepoverStart: TimeOfDay?
    public var sleepoverEnd: TimeOfDay?
    public var weekStartDay: Int?
    public var autoTimezone: Bool?
    public var haptics: Bool?
    public var shiftReminders: Bool?
    public var invoiceReminders: Bool?
    public var holidayAutoDetect: Bool?
    public var holidayState: String?
    public var onboardingCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", businessName = "business_name", abn, address, email, phone
        case bankName = "bank_name", bsb, accountName = "account_name", accountNumber = "account_number"
        case invoiceNotes = "invoice_notes", useDefaultInvoiceNotes = "use_default_invoice_notes"
        case invoiceDueDays = "invoice_due_days", invoiceCounter = "invoice_counter"
        case taxRate = "tax_rate", showTaxEstimate = "show_tax_estimate"
        case weeklyGoal = "weekly_goal", monthlyGoal = "monthly_goal", yearlyGoal = "yearly_goal"
        case rateWeekday = "rate_weekday", rateSaturday = "rate_saturday", rateSunday = "rate_sunday"
        case rateEvening = "rate_evening", ratePublicHoliday = "rate_public_holiday", rateOvertime = "rate_overtime"
        case rateSleepoverWeekday = "rate_sleepover_weekday", rateSleepoverWeekend = "rate_sleepover_weekend"
        case rateSleepoverPublicHoliday = "rate_sleepover_public_holiday"
        case eveningStart = "evening_start", eveningEnd = "evening_end"
        case sleepoverStart = "sleepover_start", sleepoverEnd = "sleepover_end"
        case weekStartDay = "week_start_day", autoTimezone = "auto_timezone", haptics
        case shiftReminders = "shift_reminders", invoiceReminders = "invoice_reminders"
        case holidayAutoDetect = "holiday_auto_detect", holidayState = "holiday_state"
        case onboardingCompleted = "onboarding_completed"
    }

    /// Defaults matching `useUserSettings.ts`.
    public init(id: UUID = UUID(), userId: UUID) {
        self.id = id
        self.userId = userId
        useDefaultInvoiceNotes = true
        invoiceDueDays = 7
        invoiceCounter = 0
        taxRate = 30
        showTaxEstimate = false
        let d = PayRates.defaults
        rateWeekday = d.weekday; rateSaturday = d.saturday; rateSunday = d.sunday
        rateEvening = d.evening; ratePublicHoliday = d.publicHoliday; rateOvertime = d.overtime
        rateSleepoverWeekday = d.sleepoverWeekday; rateSleepoverWeekend = d.sleepoverWeekend
        rateSleepoverPublicHoliday = d.sleepoverPublicHoliday
    }

    // MARK: Derived

    public var rates: PayRates {
        get {
            PayRates(weekday: rateWeekday, saturday: rateSaturday, sunday: rateSunday, evening: rateEvening,
                     publicHoliday: ratePublicHoliday, overtime: rateOvertime,
                     sleepoverWeekday: rateSleepoverWeekday, sleepoverWeekend: rateSleepoverWeekend,
                     sleepoverPublicHoliday: rateSleepoverPublicHoliday)
        }
        set {
            rateWeekday = newValue.weekday; rateSaturday = newValue.saturday; rateSunday = newValue.sunday
            rateEvening = newValue.evening; ratePublicHoliday = newValue.publicHoliday; rateOvertime = newValue.overtime
            rateSleepoverWeekday = newValue.sleepoverWeekday; rateSleepoverWeekend = newValue.sleepoverWeekend
            rateSleepoverPublicHoliday = newValue.sleepoverPublicHoliday
        }
    }

    public var rateOverrides: RateOverrides {
        let r = rates
        return RateOverrides(weekday: r.weekday, saturday: r.saturday, sunday: r.sunday, evening: r.evening,
                             publicHoliday: r.publicHoliday, overtime: r.overtime,
                             sleepoverWeekday: r.sleepoverWeekday, sleepoverWeekend: r.sleepoverWeekend,
                             sleepoverPublicHoliday: r.sleepoverPublicHoliday)
    }

    /// Default 18:00–24:00, the web app's real behaviour.
    public var eveningWindow: EveningWindow {
        get {
            EveningWindow(start: eveningStart ?? TimeOfDay(hour: 18), end: eveningEnd ?? TimeOfDay(minutes: 0))
        }
        set {
            eveningStart = newValue.start
            eveningEnd = newValue.endMinutes >= 1440 ? TimeOfDay(minutes: 0) : newValue.end
        }
    }

    /// Default sleepover times used to prefill the form: 00:00 → 06:00 (RatesPanel defaults).
    public var resolvedSleepoverStart: TimeOfDay { sleepoverStart ?? TimeOfDay(hour: 0) }
    public var resolvedSleepoverEnd: TimeOfDay { sleepoverEnd ?? TimeOfDay(hour: 6) }
    /// 0 = Sunday … 6 = Saturday; default Monday.
    public var resolvedWeekStartDay: Int { weekStartDay ?? 1 }
    public var resolvedHaptics: Bool { haptics ?? true }
    public var resolvedShiftReminders: Bool { shiftReminders ?? false }
    public var resolvedInvoiceReminders: Bool { invoiceReminders ?? false }
    public var resolvedHolidayAutoDetect: Bool { holidayAutoDetect ?? false }
    public var resolvedHolidayState: AUState { AUState(rawValue: holidayState ?? "") ?? .nsw }
    public var hasCompletedOnboarding: Bool { onboardingCompleted ?? false }

    /// Monthly/period tax estimate (see AnalyticsPanel/OverviewPanel).
    public func taxEstimate(forGross gross: Double) -> TaxEstimate {
        TaxEstimate(gross: gross, ratePercent: taxRate)
    }
}

public struct TaxEstimate: Hashable, Sendable {
    public var gross: Double
    public var ratePercent: Double

    public init(gross: Double, ratePercent: Double) {
        self.gross = gross
        self.ratePercent = ratePercent
    }

    public var tax: Double { gross * ratePercent / 100 }
    public var net: Double { gross * (1 - ratePercent / 100) }
}
