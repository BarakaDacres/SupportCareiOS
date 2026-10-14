import Foundation

// Codable mirrors of the Supabase `public` schema (see src/integrations/supabase/types.ts).
// Explicit CodingKeys keep snake_case columns independent of decoder strategy.
// Timestamps are optional so inserts omit them (DB defaults/triggers fill them in).

public struct Profile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var displayName: String?
    public var avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", displayName = "display_name", avatarUrl = "avatar_url"
    }

    public init(id: UUID = UUID(), userId: UUID, displayName: String? = nil, avatarUrl: String? = nil) {
        self.id = id; self.userId = userId; self.displayName = displayName; self.avatarUrl = avatarUrl
    }
}

public struct Client: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var name: String
    public var displayName: String?
    public var organisationName: String?
    public var participantNumber: String?
    public var email: String?
    public var phone: String?
    public var billingContact: String?
    public var billingAddress: String?
    public var serviceAddress: String?
    public var invoiceLabel: String?
    public var invoiceNotes: String?
    public var notes: String?
    public var defaultStartTime: TimeOfDay?
    public var defaultEndTime: TimeOfDay?
    public var defaultIsSleepover: Bool
    public var defaultServiceNote: String?
    public var usePlanManager: Bool
    public var useCustomRates: Bool
    public var rateWeekday: Double?
    public var rateSaturday: Double?
    public var rateSunday: Double?
    public var rateEvening: Double?
    public var ratePublicHoliday: Double?
    public var rateOvertime: Double?
    public var rateSleepoverWeekday: Double?
    public var rateSleepoverWeekend: Double?
    public var rateSleepoverPublicHoliday: Double?
    public var active: Bool
    public var archivedAt: Date?
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", name, displayName = "display_name", organisationName = "organisation_name"
        case participantNumber = "participant_number", email, phone, billingContact = "billing_contact"
        case billingAddress = "billing_address", serviceAddress = "service_address", invoiceLabel = "invoice_label"
        case invoiceNotes = "invoice_notes", notes, defaultStartTime = "default_start_time", defaultEndTime = "default_end_time"
        case defaultIsSleepover = "default_is_sleepover", defaultServiceNote = "default_service_note"
        case usePlanManager = "use_plan_manager", useCustomRates = "use_custom_rates"
        case rateWeekday = "rate_weekday", rateSaturday = "rate_saturday", rateSunday = "rate_sunday"
        case rateEvening = "rate_evening", ratePublicHoliday = "rate_public_holiday", rateOvertime = "rate_overtime"
        case rateSleepoverWeekday = "rate_sleepover_weekday", rateSleepoverWeekend = "rate_sleepover_weekend"
        case rateSleepoverPublicHoliday = "rate_sleepover_public_holiday"
        case active, archivedAt = "archived_at", createdAt = "created_at"
    }

    public init(id: UUID = UUID(), userId: UUID, name: String) {
        self.id = id; self.userId = userId; self.name = name
        defaultIsSleepover = false; usePlanManager = false; useCustomRates = false; active = true
    }

    /// Name shown on invoices and lists.
    public var shownName: String { (displayName?.isEmpty == false ? displayName : nil) ?? name }

    public var rateOverrides: RateOverrides {
        RateOverrides(
            weekday: rateWeekday, saturday: rateSaturday, sunday: rateSunday, evening: rateEvening,
            publicHoliday: ratePublicHoliday, overtime: rateOvertime,
            sleepoverWeekday: rateSleepoverWeekday, sleepoverWeekend: rateSleepoverWeekend,
            sleepoverPublicHoliday: rateSleepoverPublicHoliday
        )
    }
}

public struct Shift: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var clientId: UUID?
    public var date: CivilDate
    public var startTime: TimeOfDay
    public var endTime: TimeOfDay
    public var isSleepover: Bool
    public var isPublicHoliday: Bool
    public var isOvertime: Bool
    public var feeOverride: Double?
    public var notes: String?
    public var hoursWorked: Double
    public var grossPay: Double
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", clientId = "client_id", date, startTime = "start_time", endTime = "end_time"
        case isSleepover = "is_sleepover", isPublicHoliday = "is_public_holiday", isOvertime = "is_overtime"
        case feeOverride = "fee_override", notes, hoursWorked = "hours_worked", grossPay = "gross_pay", createdAt = "created_at"
    }

    public init(
        id: UUID = UUID(), userId: UUID, clientId: UUID? = nil, date: CivilDate, startTime: TimeOfDay, endTime: TimeOfDay,
        isSleepover: Bool = false, isPublicHoliday: Bool = false, isOvertime: Bool = false,
        feeOverride: Double? = nil, notes: String? = nil, hoursWorked: Double = 0, grossPay: Double = 0
    ) {
        self.id = id; self.userId = userId; self.clientId = clientId; self.date = date
        self.startTime = startTime; self.endTime = endTime; self.isSleepover = isSleepover
        self.isPublicHoliday = isPublicHoliday; self.isOvertime = isOvertime; self.feeOverride = feeOverride
        self.notes = notes; self.hoursWorked = hoursWorked; self.grossPay = grossPay
    }

    public var input: ShiftInput {
        ShiftInput(date: date, start: startTime, end: endTime, isSleepover: isSleepover,
                   isPublicHoliday: isPublicHoliday, isOvertime: isOvertime, feeOverride: feeOverride)
    }

    /// `effectiveGrossPay` from useShifts.ts.
    public var effectiveGross: Double {
        if let f = feeOverride, f > 0 { return f }
        return grossPay
    }

    /// Recomputes stored hours/gross from the engine (call before saving).
    public mutating func recalculate(rates: PayRates, evening: EveningWindow) {
        let calc = PayEngine.calculate(input, rates: rates, evening: evening)
        hoursWorked = calc.hoursWorked
        grossPay = calc.grossPay
    }
}

public enum ShiftType: String, Codable, CaseIterable, Sendable {
    case day, evening, sleepover

    public var label: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .day: "sun.max.fill"
        case .evening: "sunset.fill"
        case .sleepover: "moon.stars.fill"
        }
    }

    /// `getSmartNote` from smartNotes.ts.
    public var smartNote: String {
        switch self {
        case .evening: "Evening support including meal preparation, personal care, and routine assistance."
        case .sleepover: "Overnight support (sleepover). Assistance provided as required throughout the night."
        case .day: "Assistance with self-care activities and daily living support."
        }
    }
}

public struct ShiftTemplate: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var clientId: UUID?
    public var name: String
    public var shiftType: String
    public var startTime: TimeOfDay
    public var endTime: TimeOfDay
    public var isSleepover: Bool
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", clientId = "client_id", name, shiftType = "shift_type"
        case startTime = "start_time", endTime = "end_time", isSleepover = "is_sleepover", notes
    }

    public init(id: UUID = UUID(), userId: UUID, clientId: UUID? = nil, name: String, shiftType: ShiftType,
                startTime: TimeOfDay, endTime: TimeOfDay, isSleepover: Bool = false, notes: String? = nil) {
        self.id = id; self.userId = userId; self.clientId = clientId; self.name = name; self.shiftType = shiftType.rawValue
        self.startTime = startTime; self.endTime = endTime; self.isSleepover = isSleepover; self.notes = notes
    }

    public var type: ShiftType { ShiftType(rawValue: shiftType) ?? .day }
}

public enum InvoiceStatus: String, Codable, CaseIterable, Sendable {
    case draft, sent, paid, overdue

    public var label: String { rawValue.capitalized }
}

public struct Invoice: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var clientId: UUID?
    public var invoiceNumber: String
    public var periodStart: CivilDate
    public var periodEnd: CivilDate
    public var year: Int?
    public var fortnightNumber: Int?
    public var totalAmount: Double
    public var status: String
    public var dueDate: CivilDate?
    public var sentAt: Date?
    public var paidAt: Date?
    public var notes: String?
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", clientId = "client_id", invoiceNumber = "invoice_number"
        case periodStart = "period_start", periodEnd = "period_end", year, fortnightNumber = "fortnight_number"
        case totalAmount = "total_amount", status, dueDate = "due_date", sentAt = "sent_at", paidAt = "paid_at"
        case notes, createdAt = "created_at"
    }

    public init(id: UUID = UUID(), userId: UUID, clientId: UUID?, invoiceNumber: String,
                periodStart: CivilDate, periodEnd: CivilDate, totalAmount: Double, status: InvoiceStatus = .draft,
                dueDate: CivilDate? = nil, year: Int? = nil, fortnightNumber: Int? = nil, notes: String? = nil) {
        self.id = id; self.userId = userId; self.clientId = clientId; self.invoiceNumber = invoiceNumber
        self.periodStart = periodStart; self.periodEnd = periodEnd; self.totalAmount = totalAmount
        self.status = status.rawValue; self.dueDate = dueDate; self.year = year
        self.fortnightNumber = fortnightNumber; self.notes = notes
    }

    /// Stored status, promoted to `.overdue` when unpaid past the due date.
    public func displayStatus(today: CivilDate) -> InvoiceStatus {
        let s = InvoiceStatus(rawValue: status) ?? .draft
        if s != .paid, let due = dueDate, due < today { return .overdue }
        return s
    }
}

public struct InvoiceItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var invoiceId: UUID
    public var shiftId: UUID?
    public var description: String
    public var hours: Double?
    public var rate: Double?
    public var amount: Double

    enum CodingKeys: String, CodingKey {
        case id, invoiceId = "invoice_id", shiftId = "shift_id", description, hours, rate, amount
    }

    public init(id: UUID = UUID(), invoiceId: UUID, shiftId: UUID? = nil, description: String,
                hours: Double? = nil, rate: Double? = nil, amount: Double) {
        self.id = id; self.invoiceId = invoiceId; self.shiftId = shiftId; self.description = description
        self.hours = hours; self.rate = rate; self.amount = amount
    }
}
