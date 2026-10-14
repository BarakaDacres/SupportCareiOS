import Foundation
import Supabase
import SupportCareCore

/// Data access for the signed-in user. All tables are protected by RLS (`auth.uid() = user_id`).
public protocol DataRepository: Sendable {
    // Settings & profile
    func fetchSettings(userId: UUID) async throws -> UserSettings
    func saveSettings(_ settings: UserSettings) async throws -> UserSettings
    func fetchProfile(userId: UUID) async throws -> Profile?
    func saveProfile(_ profile: Profile) async throws
    func uploadAvatar(userId: UUID, jpegData: Data) async throws -> URL

    // Clients
    func fetchClients(userId: UUID) async throws -> [Client]
    func saveClient(_ client: Client) async throws -> Client
    func deleteClient(id: UUID) async throws

    // Shifts
    func fetchShifts(userId: UUID) async throws -> [Shift]
    func saveShift(_ shift: Shift) async throws -> Shift
    func saveShifts(_ shifts: [Shift]) async throws
    func deleteShift(id: UUID) async throws

    // Templates
    func fetchTemplates(userId: UUID) async throws -> [ShiftTemplate]
    func saveTemplate(_ template: ShiftTemplate) async throws -> ShiftTemplate
    func deleteTemplate(id: UUID) async throws

    // Invoices
    func fetchInvoices(userId: UUID) async throws -> [Invoice]
    func fetchInvoiceItems(invoiceId: UUID) async throws -> [InvoiceItem]
    func saveInvoice(_ invoice: Invoice, items: [InvoiceItem]?) async throws -> Invoice
    func deleteInvoice(id: UUID) async throws
}

public final class SupabaseRepository: DataRepository {
    private let client: SupabaseClient

    public init(client: SupabaseClient) { self.client = client }

    // MARK: Settings

    public func fetchSettings(userId: UUID) async throws -> UserSettings {
        let rows: [UserSettings] = try await client.from("user_settings")
            .select().eq("user_id", value: userId).limit(1).execute().value
        if let row = rows.first { return row }
        // First run: create defaults (mirrors useUserSettings.ts)
        return try await saveSettings(UserSettings(userId: userId))
    }

    public func saveSettings(_ settings: UserSettings) async throws -> UserSettings {
        try await client.from("user_settings")
            .upsert(settings, onConflict: "user_id").select().single().execute().value
    }

    // MARK: Profile

    public func fetchProfile(userId: UUID) async throws -> Profile? {
        let rows: [Profile] = try await client.from("profiles").select().eq("user_id", value: userId).limit(1).execute().value
        return rows.first
    }

    public func saveProfile(_ profile: Profile) async throws {
        try await client.from("profiles").upsert(profile, onConflict: "user_id").execute()
    }

    public func uploadAvatar(userId: UUID, jpegData: Data) async throws -> URL {
        let path = "\(userId.uuidString.lowercased())/avatar-\(Int(Date().timeIntervalSince1970)).jpg"
        _ = try await client.storage.from("avatars")
            .upload(path, data: jpegData, options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true))
        return try client.storage.from("avatars").getPublicURL(path: path)
    }

    // MARK: Clients

    public func fetchClients(userId: UUID) async throws -> [Client] {
        try await client.from("clients").select().eq("user_id", value: userId).order("name").execute().value
    }

    public func saveClient(_ c: Client) async throws -> Client {
        try await client.from("clients").upsert(c).select().single().execute().value
    }

    public func deleteClient(id: UUID) async throws {
        try await client.from("clients").delete().eq("id", value: id).execute()
    }

    // MARK: Shifts

    public func fetchShifts(userId: UUID) async throws -> [Shift] {
        try await client.from("shifts").select().eq("user_id", value: userId)
            .order("date", ascending: false).order("start_time", ascending: false).execute().value
    }

    public func saveShift(_ s: Shift) async throws -> Shift {
        try await client.from("shifts").upsert(s).select().single().execute().value
    }

    public func saveShifts(_ shifts: [Shift]) async throws {
        guard !shifts.isEmpty else { return }
        try await client.from("shifts").upsert(shifts).execute()
    }

    public func deleteShift(id: UUID) async throws {
        try await client.from("shifts").delete().eq("id", value: id).execute()
    }

    // MARK: Templates

    public func fetchTemplates(userId: UUID) async throws -> [ShiftTemplate] {
        try await client.from("shift_templates").select().eq("user_id", value: userId).order("name").execute().value
    }

    public func saveTemplate(_ t: ShiftTemplate) async throws -> ShiftTemplate {
        try await client.from("shift_templates").upsert(t).select().single().execute().value
    }

    public func deleteTemplate(id: UUID) async throws {
        try await client.from("shift_templates").delete().eq("id", value: id).execute()
    }

    // MARK: Invoices

    public func fetchInvoices(userId: UUID) async throws -> [Invoice] {
        try await client.from("invoices").select().eq("user_id", value: userId)
            .order("period_start", ascending: false).execute().value
    }

    public func fetchInvoiceItems(invoiceId: UUID) async throws -> [InvoiceItem] {
        try await client.from("invoice_items").select().eq("invoice_id", value: invoiceId).execute().value
    }

    /// Upserts the invoice. If `items` is non-nil, replaces its line items.
    public func saveInvoice(_ invoice: Invoice, items: [InvoiceItem]?) async throws -> Invoice {
        let saved: Invoice = try await client.from("invoices").upsert(invoice).select().single().execute().value
        if let items {
            try await client.from("invoice_items").delete().eq("invoice_id", value: saved.id).execute()
            if !items.isEmpty { try await client.from("invoice_items").insert(items).execute() }
        }
        return saved
    }

    public func deleteInvoice(id: UUID) async throws {
        try await client.from("invoices").delete().eq("id", value: id).execute()
    }
}
