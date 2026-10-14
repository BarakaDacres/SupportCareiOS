import SwiftUI
import SupportCareCore

/// Pick client + period (week / fortnight / month / custom), preview lines, create.
struct InvoiceBuilderView: View {
    enum PeriodKind: String, CaseIterable, Identifiable {
        case week, fortnight, month, custom
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var clientId: UUID?
    @State private var kind: PeriodKind = .week
    @State private var anchor = Date()
    @State private var fortnightIndex = 0
    @State private var customStart = Date().addingTimeInterval(-6 * 86400)
    @State private var customEnd = Date()
    @State private var notes = ""
    @State private var creating = false
    @State private var created: Invoice?

    private var fortnights: [DateRange] { Periods.fortnights(year: CivilDate(anchor).year) }

    private var period: DateRange {
        switch kind {
        case .week: return Periods.week(containing: CivilDate(anchor), weekStart: store.resolvedSettings.resolvedWeekStartDay)
        case .fortnight: return fortnights[min(fortnightIndex, fortnights.count - 1)]
        case .month: let d = CivilDate(anchor); return Periods.month(year: d.year, month: d.month)
        case .custom:
            let s = CivilDate(customStart), e = CivilDate(customEnd)
            return DateRange(start: min(s, e), end: max(s, e), label: "\(Periods.mediumDate(min(s, e))) – \(Periods.mediumDate(max(s, e)))")
        }
    }

    var body: some View {
        let shifts = store.shifts(for: clientId, in: period)
        let doc = InvoiceDocument.build(number: store.nextInvoiceNumber(), issueDate: store.today, period: period,
                                        settings: store.resolvedSettings, client: store.client(clientId), shifts: shifts)
        NavigationStack {
            Form {
                Section {
                    Picker("Client", selection: $clientId) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(store.activeClients) { Text($0.shownName).tag(Optional($0.id)) }
                    }
                }
                Section("Period") {
                    Picker("Period", selection: $kind.animation(Motion.snappy)) {
                        ForEach(PeriodKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch kind {
                    case .week, .month:
                        DatePicker(kind == .week ? "Week containing" : "Month containing", selection: $anchor, displayedComponents: .date)
                    case .fortnight:
                        Picker("Fortnight", selection: $fortnightIndex) {
                            ForEach(Array(fortnights.enumerated()), id: \.offset) { i, f in Text(f.label).tag(i) }
                        }
                    case .custom:
                        DatePicker("From", selection: $customStart, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd, displayedComponents: .date)
                    }
                    Text(period.label).font(.footnote).foregroundStyle(.secondary).contentTransition(.opacity)
                }
                Section {
                    if doc.groups.isEmpty {
                        Text(clientId == nil ? "Choose a client to see their shifts." : "No shifts for this client in this period.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(doc.groups) { g in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(g.label).font(.subheadline)
                                Text("\(g.ndisCode) · \(g.isSleepover ? "\(Int(g.quantity)) night(s)" : MoneyFormat.hours(g.quantity)) × \(g.rate.formatted(.currency(code: "AUD")))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(g.subtotal, format: .currency(code: "AUD")).monospacedDigit()
                        }
                    }
                    HStack {
                        Text("Total").font(.headline)
                        Spacer()
                        MoneyText(value: doc.total, font: .headline)
                    }
                } header: { Text("\(doc.number) · \(shifts.count) shift\(shifts.count == 1 ? "" : "s")") }
                Section("Notes") { TextField("Optional notes", text: $notes, axis: .vertical) }
            }
            .animation(Motion.smooth, value: doc.groups.map(\.category))
            .navigationTitle("New invoice")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                clientId = clientId ?? store.activeClients.first?.id
                fortnightIndex = Periods.currentFortnightIndex(fortnights, today: store.today)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        creating = true
                        Task {
                            created = await store.createInvoice(clientId: clientId, period: period, notes: notes.isEmpty ? nil : notes)
                            creating = false
                            if created != nil { dismiss() }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(doc.groups.isEmpty || creating)
                }
            }
            .sensoryFeedback(.success, trigger: created)
        }
    }
}
