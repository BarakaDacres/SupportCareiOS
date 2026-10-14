import Foundation
import Observation
import SupportCareCore
import SupportCareServices

/// Holds the signed-in user's data and does the CRUD. Feature view models read from it
/// and call its intents. Writes are optimistic: the local state updates first, then the
/// change is persisted, and rolled back if that fails.
@MainActor
@Observable
final class DataStore {
    let userId: UUID
    private let repository: DataRepository

    var settings: UserSettings?
    var profile: Profile?
    var clients: [Client] = []
    var shifts: [Shift] = []
    var templates: [ShiftTemplate] = []
    var invoices: [Invoice] = []
    var isLoading = false
    var lastError: String?

    let holidays = PublicHolidayCalendar.bundled

    init(userId: UUID, repository: DataRepository) {
        self.userId = userId
        self.repository = repository
    }

    // MARK: Loading

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let s = repository.fetchSettings(userId: userId)
            async let p = repository.fetchProfile(userId: userId)
            async let c = repository.fetchClients(userId: userId)
            async let sh = repository.fetchShifts(userId: userId)
            async let t = repository.fetchTemplates(userId: userId)
            async let i = repository.fetchInvoices(userId: userId)
            let loaded = try await (s, p, c, sh, t, i)
            settings = loaded.0
            profile = loaded.1
            clients = loaded.2
            shifts = loaded.3
            templates = loaded.4
            invoices = loaded.5
            WidgetSnapshot.write(from: self)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Derived

    var resolvedSettings: UserSettings { settings ?? UserSettings(userId: userId) }
    var evening: EveningWindow { resolvedSettings.eveningWindow }
    var activeClients: [Client] { clients.filter { $0.active && $0.archivedAt == nil } }

    func client(_ id: UUID?) -> Client? {
        guard let id else { return nil }
        return clients.first { $0.id == id }
    }

    func rates(for clientId: UUID?) -> PayRates {
        let c = client(clientId)
        return RateResolver.effectiveRates(clientOverrides: c?.rateOverrides, useCustomRates: c?.useCustomRates ?? false,
                                           global: resolvedSettings.rateOverrides)
    }

    func calculation(for input: ShiftInput, clientId: UUID?) -> ShiftCalculation {
        PayEngine.calculate(input, rates: rates(for: clientId), evening: evening)
    }

    var today: CivilDate { .today() }
    var currentWeek: DateRange { Periods.week(containing: today, weekStart: resolvedSettings.resolvedWeekStartDay) }
    var currentMonth: DateRange { Periods.month(year: today.year, month: today.month) }
    var weekSummary: EarningsSummary { Analytics.summarize(shifts, in: currentWeek) }
    var monthSummary: EarningsSummary { Analytics.summarize(shifts, in: currentMonth) }
    var financialYearSummary: EarningsSummary { Analytics.summarize(shifts, in: Periods.financialYear(containing: today)) }

    var upcomingShifts: [Shift] {
        shifts.filter { $0.date >= today }.sorted { ($0.date, $0.startTime) < ($1.date, $1.startTime) }
    }

    var overdueInvoiceCount: Int { invoices.filter { $0.displayStatus(today: today) == .overdue }.count }

    /// Holiday name for a date, if auto-detect is on.
    func detectedHoliday(on date: CivilDate) -> PublicHoliday? {
        guard resolvedSettings.resolvedHolidayAutoDetect else { return nil }
        return holidays.holiday(on: date, state: resolvedSettings.resolvedHolidayState)
    }

    // MARK: Settings & profile

    func updateSettings(_ change: (inout UserSettings) -> Void) async {
        var s = resolvedSettings
        change(&s)
        let previous = settings
        settings = s
        do { settings = try await repository.saveSettings(s) } catch { settings = previous; lastError = error.localizedDescription }
        NotificationScheduler.shared.refresh(store: self)
    }

    /// Re-prices every shift after a rate or evening-window change (gross is stored per shift).
    func repriceAllShifts() async {
        var changed: [Shift] = []
        for var s in shifts {
            let before = (s.hoursWorked, s.grossPay)
            s.recalculate(rates: rates(for: s.clientId), evening: evening)
            if before != (s.hoursWorked, s.grossPay) { changed.append(s) }
        }
        guard !changed.isEmpty else { return }
        for s in changed { if let i = shifts.firstIndex(where: { $0.id == s.id }) { shifts[i] = s } }
        do { try await repository.saveShifts(changed) } catch { lastError = error.localizedDescription }
    }

    func saveProfile(displayName: String?) async {
        var p = profile ?? Profile(userId: userId)
        p.displayName = displayName
        profile = p
        try? await repository.saveProfile(p)
    }

    func uploadAvatar(_ jpeg: Data) async {
        do {
            let url = try await repository.uploadAvatar(userId: userId, jpegData: jpeg)
            var p = profile ?? Profile(userId: userId)
            p.avatarUrl = url.absoluteString
            profile = p
            try await repository.saveProfile(p)
        } catch { lastError = error.localizedDescription }
    }

    // MARK: Clients

    @discardableResult
    func save(client: Client) async -> Client? {
        let previous = clients
        upsertLocal(&clients, client)
        clients.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        do {
            let saved = try await repository.saveClient(client)
            upsertLocal(&clients, saved)
            return saved
        } catch { clients = previous; lastError = error.localizedDescription; return nil }
    }

    func archive(client: Client, archived: Bool) async {
        var c = client
        c.active = !archived
        c.archivedAt = archived ? Date() : nil
        await save(client: c)
    }

    func delete(client: Client) async {
        let previous = clients
        clients.removeAll { $0.id == client.id }
        do { try await repository.deleteClient(id: client.id) } catch { clients = previous; lastError = error.localizedDescription }
    }

    // MARK: Shifts

    @discardableResult
    func save(shift input: Shift) async -> Bool {
        var shift = input
        shift.recalculate(rates: rates(for: shift.clientId), evening: evening)
        let previous = shifts
        upsertLocal(&shifts, shift)
        shifts.sort { ($0.date, $0.startTime) > ($1.date, $1.startTime) }
        do {
            _ = try await repository.saveShift(shift)
            afterShiftsChanged()
            return true
        } catch { shifts = previous; lastError = error.localizedDescription; return false }
    }

    func delete(shift: Shift) async {
        let previous = shifts
        shifts.removeAll { $0.id == shift.id }
        do { try await repository.deleteShift(id: shift.id); afterShiftsChanged() }
        catch { shifts = previous; lastError = error.localizedDescription }
    }

    func duplicate(shift: Shift, to date: CivilDate) async {
        var copy = shift
        copy.id = UUID()
        copy.date = date
        copy.isPublicHoliday = detectedHoliday(on: date) != nil || (shift.isPublicHoliday && date == shift.date)
        await save(shift: copy)
    }

    func makeShift(from template: ShiftTemplate, on date: CivilDate) -> Shift {
        Shift(userId: userId, clientId: template.clientId, date: date, startTime: template.startTime, endTime: template.endTime,
              isSleepover: template.isSleepover, isPublicHoliday: detectedHoliday(on: date) != nil,
              notes: template.notes ?? template.type.smartNote)
    }

    private func afterShiftsChanged() {
        WidgetSnapshot.write(from: self)
        NotificationScheduler.shared.refresh(store: self)
    }

    // MARK: Templates

    func save(template: ShiftTemplate) async {
        upsertLocal(&templates, template)
        do { _ = try await repository.saveTemplate(template) } catch { lastError = error.localizedDescription }
    }

    func delete(template: ShiftTemplate) async {
        templates.removeAll { $0.id == template.id }
        try? await repository.deleteTemplate(id: template.id)
    }

    // MARK: Invoices

    func nextInvoiceNumber() -> String {
        InvoiceNumbering.format(InvoiceNumbering.nextAvailable(existing: invoices.map(\.invoiceNumber)))
    }

    func shifts(for clientId: UUID?, in range: DateRange) -> [Shift] {
        shifts.filter { range.contains($0.date) && (clientId == nil || $0.clientId == clientId) }
    }

    func document(for invoice: Invoice) -> InvoiceDocument {
        InvoiceDocument.build(
            number: invoice.invoiceNumber,
            issueDate: invoice.createdAt.map { CivilDate($0) } ?? today,
            period: DateRange(start: invoice.periodStart, end: invoice.periodEnd,
                              label: "\(Periods.mediumDate(invoice.periodStart)) – \(Periods.mediumDate(invoice.periodEnd))"),
            settings: resolvedSettings, client: client(invoice.clientId),
            shifts: shifts(for: invoice.clientId, in: DateRange(start: invoice.periodStart, end: invoice.periodEnd, label: "")),
            isPaid: invoice.status == InvoiceStatus.paid.rawValue)
    }

    /// Creates and saves an invoice for the client and period.
    func createInvoice(clientId: UUID?, period: DateRange, notes: String?) async -> Invoice? {
        let number = nextInvoiceNumber()
        let issue = today
        let doc = InvoiceDocument.build(number: number, issueDate: issue, period: period, settings: resolvedSettings,
                                        client: client(clientId), shifts: shifts(for: clientId, in: period))
        var invoice = Invoice(userId: userId, clientId: clientId, invoiceNumber: number, periodStart: period.start,
                              periodEnd: period.end, totalAmount: doc.total, status: .draft, dueDate: doc.dueDate,
                              year: period.start.year, fortnightNumber: period.number, notes: notes)
        invoice.createdAt = Date()
        do {
            let saved = try await repository.saveInvoice(invoice, items: doc.items(invoiceId: invoice.id))
            upsertLocal(&invoices, saved)
            invoices.sort { $0.periodStart > $1.periodStart }
            // Counter is a high-water mark (InvoicePanel behaviour).
            let n = InvoiceNumbering.nextAvailable(existing: invoices.map(\.invoiceNumber)) - 1
            if n > resolvedSettings.invoiceCounter { await updateSettings { $0.invoiceCounter = n } }
            NotificationScheduler.shared.refresh(store: self)
            return saved
        } catch { lastError = error.localizedDescription; return nil }
    }

    func setStatus(_ status: InvoiceStatus, for invoice: Invoice) async {
        var inv = invoice
        inv.status = status.rawValue
        switch status {
        case .sent: inv.sentAt = inv.sentAt ?? Date()
        case .paid: inv.paidAt = Date()
        case .draft: inv.sentAt = nil; inv.paidAt = nil
        case .overdue: break
        }
        let previous = invoices
        upsertLocal(&invoices, inv)
        do { _ = try await repository.saveInvoice(inv, items: nil) } catch { invoices = previous; lastError = error.localizedDescription }
        NotificationScheduler.shared.refresh(store: self)
    }

    func delete(invoice: Invoice) async {
        let previous = invoices
        invoices.removeAll { $0.id == invoice.id }
        do { try await repository.deleteInvoice(id: invoice.id) } catch { invoices = previous; lastError = error.localizedDescription }
    }

    // MARK: Helpers

    private func upsertLocal<T: Identifiable>(_ array: inout [T], _ item: T) {
        if let i = array.firstIndex(where: { $0.id == item.id }) { array[i] = item } else { array.append(item) }
    }
}
