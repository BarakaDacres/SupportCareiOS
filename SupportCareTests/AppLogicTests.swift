import Testing
@testable import SupportCare
import SupportCareCore
import SupportCareServices

/// App-level tests against the in-memory repository (no network).
@MainActor
struct DataStoreTests {
    let userId = UUID()

    func makeStore() async -> DataStore {
        let store = DataStore(userId: userId, repository: InMemoryRepository())
        await store.loadAll()
        return store
    }

    @Test func savingAShiftPricesIt() async {
        let store = await makeStore()
        let shift = Shift(userId: userId, date: CivilDate("2026-10-14")!, startTime: TimeOfDay(hour: 15), endTime: TimeOfDay(hour: 21))
        #expect(await store.save(shift: shift))
        #expect(store.shifts.first?.grossPay == 405) // 3h × $60 + 3h × $75 (matches web)
    }

    @Test func clientCustomRatesApply() async {
        let store = await makeStore()
        var client = Client(userId: userId, name: "Jo")
        client.useCustomRates = true
        client.rateWeekday = 70
        await store.save(client: client)
        let shift = Shift(userId: userId, clientId: client.id, date: CivilDate("2026-10-14")!, startTime: TimeOfDay(hour: 9), endTime: TimeOfDay(hour: 17))
        await store.save(shift: shift)
        #expect(store.shifts.first?.grossPay == 560)
    }

    @Test func invoiceNumbersFillGaps() async {
        let store = await makeStore()
        let period = Periods.week(containing: CivilDate("2026-10-14")!)
        let a = await store.createInvoice(clientId: nil, period: period, notes: nil)
        let b = await store.createInvoice(clientId: nil, period: period, notes: nil)
        #expect(a?.invoiceNumber == "INV-001")
        #expect(b?.invoiceNumber == "INV-002")
        if let a { await store.delete(invoice: a) }
        #expect(store.nextInvoiceNumber() == "INV-001")
    }

    @Test func holidayAutoDetectOnlyWhenEnabled() async {
        let store = await makeStore()
        let xmas = CivilDate("2026-12-25")!
        #expect(store.detectedHoliday(on: xmas) == nil)
        await store.updateSettings { $0.holidayAutoDetect = true; $0.holidayState = "VIC" }
        #expect(store.detectedHoliday(on: xmas)?.name == "Christmas Day")
    }

    @Test func eveningWindowChangeReprices() async {
        let store = await makeStore()
        await store.save(shift: Shift(userId: userId, date: CivilDate("2026-10-14")!, startTime: TimeOfDay(hour: 20), endTime: TimeOfDay(hour: 23)))
        #expect(store.shifts.first?.grossPay == 225)
        await store.updateSettings { $0.eveningEnd = TimeOfDay(hour: 22) }
        await store.repriceAllShifts()
        #expect(store.shifts.first?.grossPay == 210)
    }
}
