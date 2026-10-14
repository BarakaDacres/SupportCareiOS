import Foundation
import SupportCareCore

/// In-memory repository for SwiftUI previews, UI tests and a "demo mode" without a backend.
public actor InMemoryRepository: DataRepository {
    var settings: [UUID: UserSettings] = [:]
    var profiles: [UUID: Profile] = [:]
    var clients: [UUID: Client] = [:]
    var shifts: [UUID: Shift] = [:]
    var templates: [UUID: ShiftTemplate] = [:]
    var invoices: [UUID: Invoice] = [:]
    var items: [UUID: [InvoiceItem]] = [:]

    public init() {}

    /// Seeds a realistic data set for previews.
    public static func sample(userId: UUID) async -> InMemoryRepository {
        let repo = InMemoryRepository()
        await repo.seed(userId: userId)
        return repo
    }

    func seed(userId: UUID) {
        var s = UserSettings(userId: userId)
        s.businessName = "Baraka Support Services"
        s.abn = "12 345 678 901"
        s.onboardingCompleted = true
        s.showTaxEstimate = true
        s.monthlyGoal = 8000
        settings[userId] = s
        var a = Client(userId: userId, name: "Jordan Smith"); a.participantNumber = "430123456"
        var b = Client(userId: userId, name: "Priya Patel"); b.usePlanManager = true; b.organisationName = "Plan Partners"
        clients[a.id] = a; clients[b.id] = b
        let today = CivilDate.today()
        let specs: [(Int, Int, Int, Bool, UUID)] = [
            (0, 9, 15, false, a.id), (-1, 15, 21, false, b.id), (-2, 22, 6, true, a.id),
            (-3, 9, 17, false, b.id), (-5, 10, 14, false, a.id), (2, 9, 13, false, b.id),
        ]
        for (offset, sh, eh, sleep, cid) in specs {
            var shift = Shift(userId: userId, clientId: cid, date: today.adding(days: offset),
                              startTime: TimeOfDay(hour: sh), endTime: TimeOfDay(hour: eh), isSleepover: sleep)
            shift.recalculate(rates: s.rates, evening: s.eveningWindow)
            shifts[shift.id] = shift
        }
        let t = ShiftTemplate(userId: userId, clientId: a.id, name: "Morning support", shiftType: .day,
                              startTime: TimeOfDay(hour: 9), endTime: TimeOfDay(hour: 15))
        templates[t.id] = t
    }

    public func fetchSettings(userId: UUID) async throws -> UserSettings {
        if let s = settings[userId] { return s }
        let s = UserSettings(userId: userId); settings[userId] = s; return s
    }
    public func saveSettings(_ s: UserSettings) async throws -> UserSettings { settings[s.userId] = s; return s }
    public func fetchProfile(userId: UUID) async throws -> Profile? { profiles[userId] }
    public func saveProfile(_ p: Profile) async throws { profiles[p.userId] = p }
    public func uploadAvatar(userId: UUID, jpegData: Data) async throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("avatar.jpg")
    }
    public func fetchClients(userId: UUID) async throws -> [Client] { clients.values.filter { $0.userId == userId }.sorted { $0.name < $1.name } }
    public func saveClient(_ c: Client) async throws -> Client { clients[c.id] = c; return c }
    public func deleteClient(id: UUID) async throws { clients[id] = nil }
    public func fetchShifts(userId: UUID) async throws -> [Shift] {
        shifts.values.filter { $0.userId == userId }.sorted { ($0.date, $0.startTime) > ($1.date, $1.startTime) }
    }
    public func saveShift(_ s: Shift) async throws -> Shift { shifts[s.id] = s; return s }
    public func saveShifts(_ list: [Shift]) async throws { for s in list { shifts[s.id] = s } }
    public func deleteShift(id: UUID) async throws { shifts[id] = nil }
    public func fetchTemplates(userId: UUID) async throws -> [ShiftTemplate] { templates.values.filter { $0.userId == userId }.sorted { $0.name < $1.name } }
    public func saveTemplate(_ t: ShiftTemplate) async throws -> ShiftTemplate { templates[t.id] = t; return t }
    public func deleteTemplate(id: UUID) async throws { templates[id] = nil }
    public func fetchInvoices(userId: UUID) async throws -> [Invoice] { invoices.values.filter { $0.userId == userId }.sorted { $0.periodStart > $1.periodStart } }
    public func fetchInvoiceItems(invoiceId: UUID) async throws -> [InvoiceItem] { items[invoiceId] ?? [] }
    public func saveInvoice(_ inv: Invoice, items newItems: [InvoiceItem]?) async throws -> Invoice {
        invoices[inv.id] = inv
        if let newItems { items[inv.id] = newItems }
        return inv
    }
    public func deleteInvoice(id: UUID) async throws { invoices[id] = nil; items[id] = nil }
}
