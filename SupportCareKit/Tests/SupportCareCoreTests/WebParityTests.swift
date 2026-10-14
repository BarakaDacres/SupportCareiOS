import Foundation
import Testing
@testable import SupportCareCore

/// Fixtures in `web_fixtures.json` are produced by running the web app's own TypeScript
/// (`src/lib/shiftCalculator.ts`, `src/lib/invoiceGrouping.ts`) under Node. See README, "Parity fixtures".
struct WebFixtures: Decodable {
    struct PayCase: Decodable {
        let input: [Value]
        let result: Result
        struct Result: Decodable {
            let hoursWorked: Double
            let grossPay: Double
            let breakdown: [Line]
        }
        struct Line: Decodable { let label: String; let hours: Double?; let rate: Double?; let amount: Double }

        var shift: ShiftInput {
            ShiftInput(date: CivilDate(input[0].string!)!, start: TimeOfDay(input[1].string!)!, end: TimeOfDay(input[2].string!)!,
                       isSleepover: input[3].bool!, isPublicHoliday: input[4].bool!, isOvertime: input[5].bool!)
        }
    }
    enum Value: Decodable {
        case string(String), bool(Bool)
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = .bool(b) } else { self = .string(try c.decode(String.self)) }
        }
        var string: String? { if case .string(let s) = self { s } else { nil } }
        var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    }
    struct InvShift: Decodable {
        let id: UUID; let date: String; let start_time: String; let end_time: String
        let is_sleepover: Bool; let is_public_holiday: Bool; let is_overtime: Bool
        let gross_pay: Double; let hours_worked: Double; let fee_override: Double?
    }
    struct Group: Decodable { let category: String; let quantity: Double; let totalHours: Double; let rate: Double; let subtotal: Double; let shiftCount: Int }

    let pay: [PayCase]
    let payCustomRates: [PayCase]
    let payCustomWindow: [PayCase]
    let invoiceShifts: [InvShift]
    let invoice: [Group]

    static let shared: WebFixtures = {
        let url = Bundle.module.url(forResource: "web_fixtures", withExtension: "json")!
        return try! JSONDecoder().decode(WebFixtures.self, from: Data(contentsOf: url))
    }()
}

let webCustomRates = PayRates(weekday: 65.47, saturday: 92.12, sunday: 118.77, evening: 72.08,
                           publicHoliday: 150, overtime: 90, sleepoverWeekday: 300, sleepoverWeekend: 350,
                           sleepoverPublicHoliday: 400)

@Suite("Pay engine matches web shiftCalculator.ts")
struct PayParityTests {
    func check(_ c: WebFixtures.PayCase, rates: PayRates, evening: EveningWindow) {
        let r = PayEngine.calculate(c.shift, rates: rates, evening: evening)
        #expect(abs(r.grossPay - c.result.grossPay) < 0.001, "\(c.input) gross \(r.grossPay) vs \(c.result.grossPay)")
        #expect(abs(r.hoursWorked - c.result.hoursWorked) < 0.001, "\(c.input) hours")
        #expect(r.breakdown.map(\.label) == c.result.breakdown.map(\.label), "\(c.input) labels")
        #expect(zip(r.breakdown, c.result.breakdown).allSatisfy { abs($0.amount - $1.amount) < 0.001 }, "\(c.input) amounts")
    }

    @Test func defaultRatesDefaultWindow() {
        for c in WebFixtures.shared.pay { check(c, rates: .defaults, evening: .default) }
    }

    @Test func customRates() {
        for c in WebFixtures.shared.payCustomRates { check(c, rates: webCustomRates, evening: .default) }
    }

    @Test func eveningWindow18to22() {
        let w = EveningWindow(start: TimeOfDay(hour: 18), end: TimeOfDay(hour: 22))
        for c in WebFixtures.shared.payCustomWindow { check(c, rates: .defaults, evening: w) }
    }
}

@Suite("Invoice grouping matches web invoiceGrouping.ts")
struct InvoiceParityTests {
    @Test func groupsMatch() {
        let f = WebFixtures.shared
        let shifts = f.invoiceShifts.map {
            Shift(id: $0.id, userId: UUID(), date: CivilDate($0.date)!, startTime: TimeOfDay($0.start_time)!,
                  endTime: TimeOfDay($0.end_time)!, isSleepover: $0.is_sleepover, isPublicHoliday: $0.is_public_holiday,
                  isOvertime: $0.is_overtime, feeOverride: $0.fee_override, hoursWorked: $0.hours_worked, grossPay: $0.gross_pay)
        }
        let groups = InvoiceGrouping.group(shifts, rates: .defaults)
        #expect(groups.map(\.category.rawValue) == f.invoice.map(\.category))
        for (g, w) in zip(groups, f.invoice) {
            #expect(abs(g.quantity - w.quantity) < 0.001, "\(w.category) qty")
            #expect(abs(g.subtotal - w.subtotal) < 0.001, "\(w.category) subtotal \(g.subtotal) vs \(w.subtotal)")
            #expect(g.rate == w.rate)
            #expect(g.shiftIds.count == w.shiftCount)
        }
    }
}
