import Foundation
import Testing
@testable import SupportCareCore

@Suite struct CivilDateTests {
    @Test func weekdayAndArithmetic() {
        #expect(CivilDate("2026-10-14")!.weekday == 3) // Wednesday
        #expect(CivilDate("1970-01-01")!.weekday == 4)
        #expect(CivilDate("2024-02-28")!.adding(days: 1).iso == "2024-02-29")
        #expect(CivilDate("2026-12-31")!.adding(days: 1).iso == "2027-01-01")
        #expect(CivilDate.daysInMonth(year: 2028, month: 2) == 29)
        let d = CivilDate(year: 2026, month: 3, day: 9)
        #expect(CivilDate(daysSinceEpoch: d.daysSinceEpoch) == d)
    }

    @Test func timeParsing() {
        #expect(TimeOfDay("09:30:00")?.minutes == 570)
        #expect(TimeOfDay("21:05")?.twelveHour == "9:05 PM")
        #expect(TimeOfDay("00:00")?.twelveHour == "12:00 AM")
    }

    @Test func codableRoundTrip() throws {
        let json = #"{"d":"2026-10-14","t":"18:00:00"}"#.data(using: .utf8)!
        struct X: Codable { let d: CivilDate; let t: TimeOfDay }
        let x = try JSONDecoder().decode(X.self, from: json)
        #expect(x.d.iso == "2026-10-14" && x.t.minutes == 1080)
        let back = String(decoding: try JSONEncoder().encode(x), as: UTF8.self)
        #expect(back.contains("\"18:00:00\""))
    }
}

@Suite struct RateResolverTests {
    @Test func fieldByFieldFallback() {
        var global = RateOverrides(); global.weekday = 70
        let client = RateOverrides(saturday: 99)
        let r = RateResolver.effectiveRates(clientOverrides: client, useCustomRates: true, global: global)
        #expect(r.weekday == 70 && r.saturday == 99 && r.sunday == 90)
        let off = RateResolver.effectiveRates(clientOverrides: client, useCustomRates: false, global: global)
        #expect(off.saturday == 75)
    }
}

@Suite struct EveningWindowTests {
    @Test func defaultIsSixPmToMidnight() {
        #expect(EveningWindow.default.startMinutes == 1080)
        #expect(EveningWindow.default.endMinutes == 1440)
        // Web: 'pref_evening_end' "00:00" means midnight
        #expect(EveningWindow(start: TimeOfDay(hour: 18), end: TimeOfDay(minutes: 0)).endMinutes == 1440)
        var s = UserSettings(userId: UUID())
        #expect(s.eveningWindow == .default)
        s.eveningWindow = EveningWindow(start: TimeOfDay(hour: 18), end: TimeOfDay(hour: 22))
        #expect(s.eveningEnd?.hhmm == "22:00")
    }

    @Test func weekdayEveningUntilMidnightByDefault() {
        // Wed 20:00–23:00 → all evening at $75.
        let r = PayEngine.calculate(ShiftInput(date: CivilDate("2026-10-14")!, start: TimeOfDay(hour: 20), end: TimeOfDay(hour: 23)))
        #expect(r.grossPay == 225)
        let w = EveningWindow(start: TimeOfDay(hour: 18), end: TimeOfDay(hour: 22))
        let r2 = PayEngine.calculate(ShiftInput(date: CivilDate("2026-10-14")!, start: TimeOfDay(hour: 20), end: TimeOfDay(hour: 23)), evening: w)
        #expect(r2.grossPay == 2 * 75 + 60)
    }
}

@Suite struct InvoiceTests {
    @Test func numbering() {
        #expect(InvoiceNumbering.format(7) == "INV-007")
        #expect(InvoiceNumbering.format(1234) == "INV-1234")
        #expect(InvoiceNumbering.nextAvailable(existing: ["INV-001", "INV-002", "INV-004", "WK-ABC"]) == 3)
        #expect(InvoiceNumbering.nextAvailable(existing: ["inv-1", "INV-2", "INV-3"]) == 4)
        #expect(InvoiceNumbering.nextAvailable(existing: []) == 1)
        #expect(InvoiceNumbering.dueDate(issued: CivilDate("2026-10-28")!, dueDays: 7).iso == "2026-11-04")
    }

    @Test func overtimeIsIncludedOnInvoices() {
        // Web bug: overtime categories were missing from ORDER and dropped. Fixed here.
        let s = Shift(userId: UUID(), date: CivilDate("2026-10-14")!, startTime: TimeOfDay(hour: 9), endTime: TimeOfDay(hour: 12),
                      isOvertime: true, hoursWorked: 3, grossPay: 270)
        let g = InvoiceGrouping.group([s], rates: .defaults)
        #expect(g.map(\.category) == [.overtime])
        #expect(InvoiceGrouping.total(g) == 270)
    }

    @Test func statusOverdue() {
        var inv = Invoice(userId: UUID(), clientId: nil, invoiceNumber: "INV-001", periodStart: CivilDate("2026-10-01")!,
                          periodEnd: CivilDate("2026-10-07")!, totalAmount: 100, status: .sent, dueDate: CivilDate("2026-10-10")!)
        #expect(inv.displayStatus(today: CivilDate("2026-10-14")!) == .overdue)
        inv.status = "paid"
        #expect(inv.displayStatus(today: CivilDate("2026-10-14")!) == .paid)
    }
}

@Suite struct PeriodTests {
    @Test func fortnights2026() {
        let f = Periods.fortnights(year: 2026)
        #expect(f.first?.start.iso == "2025-12-29")
        #expect(f.first?.label == "FN01 · 29 Dec 2025 – 11 Jan 2026")
        #expect(f.allSatisfy { $0.end.daysSinceEpoch - $0.start.daysSinceEpoch == 13 })
        #expect(f.last!.start.year == 2026)
    }

    @Test func weeksOfMonth() {
        let w = Periods.weeks(year: 2026, month: 10)
        #expect(w.first?.start.iso == "2026-09-28")
        #expect(w.first?.label == "28 Sep – 04 Oct")
        #expect(w.count == 5)
        #expect(Periods.weekStart(containing: CivilDate("2026-10-14")!, weekStart: 0).iso == "2026-10-11")
    }

    @Test func financialYear() {
        #expect(Periods.financialYear(containing: CivilDate("2026-10-14")!).label == "FY27")
    }
}

@Suite struct TaxAndAnalyticsTests {
    @Test func tax() {
        let t = TaxEstimate(gross: 1000, ratePercent: 30)
        #expect(t.tax == 300 && t.net == 700)
    }

    @Test func summary() {
        let u = UUID()
        let shifts = [
            Shift(userId: u, date: CivilDate("2026-10-14")!, startTime: TimeOfDay(hour: 9), endTime: TimeOfDay(hour: 17), hoursWorked: 8, grossPay: 480),
            Shift(userId: u, date: CivilDate("2026-10-15")!, startTime: TimeOfDay(hour: 22), endTime: TimeOfDay(hour: 6), isSleepover: true, feeOverride: 320, hoursWorked: 8, grossPay: 300),
        ]
        let s = Analytics.summarize(shifts)
        #expect(s.gross == 800 && s.hours == 16 && s.sleepovers == 1)
        #expect(Analytics.progress(400, goal: 1600) == 0.25)
    }
}

@Suite struct HolidayTests {
    @Test func bundledListLoads() {
        let cal = PublicHolidayCalendar.bundled
        #expect(cal.coveredYears?.contains(2026) == true)
        #expect(cal.isHoliday(CivilDate("2026-12-25")!, state: .nsw))
        #expect(cal.isHoliday(CivilDate("2026-01-26")!, state: .wa))
        #expect(!cal.isHoliday(CivilDate("2026-10-14")!, state: .vic))
        // State-specific: Labour Day 5 Oct 2026 in NSW but not VIC (VIC is in March)
        #expect(cal.isHoliday(CivilDate("2026-10-05")!, state: .nsw))
        #expect(!cal.isHoliday(CivilDate("2026-10-05")!, state: .vic))
        #expect(cal.suggestsPublicHoliday(for: CivilDate("2026-12-25")!, state: .qld, enabled: false) == false)
    }
}
