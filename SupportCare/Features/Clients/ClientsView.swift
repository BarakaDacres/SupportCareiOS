import SwiftUI
import SupportCareCore

struct ClientsView: View {
    @Environment(DataStore.self) private var store
    @State private var showArchived = false
    @State private var search = ""
    @State private var creating: Client?
    @Namespace private var zoom

    private var list: [Client] {
        store.clients
            .filter { showArchived ? !$0.active : $0.active }
            .filter { search.isEmpty || $0.shownName.localizedCaseInsensitiveContains(search) || ($0.participantNumber ?? "").contains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if list.isEmpty {
                    EmptyStateView(title: showArchived ? "No archived clients" : "No clients yet",
                                   message: "Add the participants you support, with their NDIS number, billing details and custom rates.",
                                   systemImage: "person.2.badge.plus",
                                   actionTitle: showArchived ? nil : "Add client") { creating = Client(userId: store.userId, name: "") }
                        .listRowBackground(Color.clear)
                }
                ForEach(list) { client in
                    NavigationLink(value: client.id) {
                        ClientRow(client: client)
                            .matchedTransitionSource(id: client.id, in: zoom)
                    }
                    .swipeActions {
                        Button(client.active ? "Archive" : "Restore", systemImage: client.active ? "archivebox" : "arrow.uturn.backward") {
                            Task { await store.archive(client: client, archived: client.active) }
                        }
                        .tint(Theme.amber)
                    }
                }
            }
            .animation(Motion.smooth, value: list.map(\.id))
            .navigationTitle("Clients")
            .searchable(text: $search, prompt: "Name or NDIS number")
            .navigationDestination(for: UUID.self) { id in
                ClientDetailView(clientId: id)
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $showArchived.animation(Motion.smooth)) {
                        Label("Archived", systemImage: "archivebox")
                    }
                    .toggleStyle(.button)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add client", systemImage: "plus") { creating = Client(userId: store.userId, name: "") }
                        .buttonStyle(.glassProminent)
                }
            }
            .sheet(item: $creating) { ClientEditorView(client: $0, isNew: true) }
        }
    }
}

struct ClientRow: View {
    @Environment(DataStore.self) private var store
    let client: Client

    var body: some View {
        let month = Analytics.summarize(store.shifts.filter { $0.clientId == client.id }, in: store.currentMonth)
        HStack(spacing: 12) {
            Text(initials)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(color.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(client.shownName).font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    if let n = client.participantNumber, !n.isEmpty { Text("NDIS \(n)") }
                    if client.usePlanManager { Badge(text: "Plan managed", color: Theme.purple) }
                    if client.useCustomRates { Badge(text: "Custom rates", color: Theme.amber) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(month.gross, format: .currency(code: "AUD")).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text("this month").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var initials: String {
        client.shownName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
    private var color: Color {
        let palette = [Theme.primary, Theme.purple, Theme.evening, Theme.money, Theme.sleepover, Theme.weekend]
        return palette[Int(client.id.uuid.0) % palette.count]
    }
}

struct ClientDetailView: View {
    @Environment(DataStore.self) private var store
    let clientId: UUID
    @State private var editing = false
    @State private var newShift: ShiftEditorView.Mode?

    var body: some View {
        if let client = store.client(clientId) {
            let shifts = store.shifts.filter { $0.clientId == clientId }
            let rates = store.rates(for: clientId)
            List {
                Section {
                    HStack(spacing: 12) {
                        StatTile(title: "This month", value: Analytics.summarize(shifts, in: store.currentMonth).gross, tint: Theme.money, symbol: "calendar")
                        StatTile(title: "Financial year", value: Analytics.summarize(shifts, in: Periods.financialYear(containing: store.today)).gross, symbol: "chart.bar.fill")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section("Details") {
                    row("NDIS number", client.participantNumber)
                    row("Organisation", client.organisationName)
                    row("Email", client.email)
                    row("Phone", client.phone)
                    row("Billing contact", client.billingContact)
                    row("Billing address", client.billingAddress)
                    row("Service address", client.serviceAddress)
                }
                Section(client.useCustomRates ? "Custom rates" : "Rates (your defaults)") {
                    rateRow("Weekday", rates.weekday); rateRow("Evening", rates.evening)
                    rateRow("Saturday", rates.saturday); rateRow("Sunday", rates.sunday)
                    rateRow("Public holiday", rates.publicHoliday)
                    rateRow("Sleepover (weeknight)", rates.sleepoverWeekday); rateRow("Sleepover (weekend)", rates.sleepoverWeekend)
                }
                Section("Recent shifts") {
                    if shifts.isEmpty { Text("No shifts yet").foregroundStyle(.secondary) }
                    ForEach(shifts.prefix(20)) { s in
                        Button { newShift = .edit(s) } label: {
                            HStack {
                                Text(s.date.date(), format: .dateTime.day().month().year())
                                Text("\(s.startTime.twelveHour)–\(s.endTime.twelveHour)").foregroundStyle(.secondary).font(.caption)
                                Spacer()
                                Text(s.effectiveGross, format: .currency(code: "AUD")).monospacedDigit()
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle(client.shownName)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
                ToolbarItem(placement: .bottomBar) {
                    Button("Log shift", systemImage: "plus") {
                        newShift = .fromTemplate(Shift(userId: store.userId, clientId: clientId, date: store.today,
                                                       startTime: client.defaultStartTime ?? TimeOfDay(hour: 9),
                                                       endTime: client.defaultEndTime ?? TimeOfDay(hour: 15),
                                                       isSleepover: client.defaultIsSleepover, notes: client.defaultServiceNote))
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .sheet(isPresented: $editing) { ClientEditorView(client: client, isNew: false) }
            .sheet(item: $newShift) { ShiftEditorView(mode: $0) }
        } else {
            ContentUnavailableView("Client not found", systemImage: "person.fill.questionmark")
        }
    }

    @ViewBuilder private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty { LabeledContent(title, value: value).textSelection(.enabled) }
    }

    private func rateRow(_ title: String, _ value: Double) -> some View {
        LabeledContent(title) { Text(value, format: .currency(code: "AUD")).monospacedDigit() }
    }
}

struct ClientEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var client: Client
    let isNew: Bool
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Participant") {
                    TextField("Name", text: $client.name).textContentType(.name)
                    TextField("Display name on invoices", text: $client.displayName.orEmpty)
                    TextField("NDIS participant number", text: $client.participantNumber.orEmpty).keyboardType(.numberPad)
                    TextField("Invoice label", text: $client.invoiceLabel.orEmpty)
                }
                Section("Billing") {
                    Toggle("Plan managed", isOn: $client.usePlanManager.animation())
                    if client.usePlanManager { TextField("Plan manager organisation", text: $client.organisationName.orEmpty) }
                    TextField("Billing contact", text: $client.billingContact.orEmpty)
                    TextField("Billing email", text: $client.email.orEmpty).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Phone", text: $client.phone.orEmpty).keyboardType(.phonePad)
                    TextField("Billing address", text: $client.billingAddress.orEmpty, axis: .vertical)
                    TextField("Service address", text: $client.serviceAddress.orEmpty, axis: .vertical)
                    TextField("Invoice notes", text: $client.invoiceNotes.orEmpty, axis: .vertical)
                }
                Section("Shift defaults") {
                    Toggle("Usually a sleepover", isOn: $client.defaultIsSleepover)
                    OptionalTimeRow(title: "Default start", value: $client.defaultStartTime)
                    OptionalTimeRow(title: "Default end", value: $client.defaultEndTime)
                    TextField("Default service note", text: $client.defaultServiceNote.orEmpty, axis: .vertical)
                }
                Section {
                    Toggle("Custom rates", isOn: $client.useCustomRates.animation(Motion.snappy))
                    if client.useCustomRates {
                        OptionalCurrencyField(title: "Weekday", value: $client.rateWeekday)
                        OptionalCurrencyField(title: "Evening", value: $client.rateEvening)
                        OptionalCurrencyField(title: "Saturday", value: $client.rateSaturday)
                        OptionalCurrencyField(title: "Sunday", value: $client.rateSunday)
                        OptionalCurrencyField(title: "Public holiday", value: $client.ratePublicHoliday)
                        OptionalCurrencyField(title: "Overtime", value: $client.rateOvertime)
                        OptionalCurrencyField(title: "Sleepover weeknight", value: $client.rateSleepoverWeekday)
                        OptionalCurrencyField(title: "Sleepover weekend", value: $client.rateSleepoverWeekend)
                        OptionalCurrencyField(title: "Sleepover public holiday", value: $client.rateSleepoverPublicHoliday)
                    }
                } footer: { Text("Blank fields use your default rates.") }
                Section("Private notes") { TextField("Notes", text: $client.notes.orEmpty, axis: .vertical) }
                if !isNew {
                    Section { Button("Delete client", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(isNew ? "New client" : "Edit client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await store.save(client: client)
                            if client.useCustomRates || !isNew { await store.repriceAllShifts() }
                            dismiss()
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(client.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(client.shownName)? Their shifts are kept but unassigned.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await store.delete(client: client); dismiss() } }
            }
        }
    }
}

struct OptionalTimeRow: View {
    let title: String
    @Binding var value: TimeOfDay?

    var body: some View {
        if let v = value {
            HStack {
                DatePicker(title, selection: Binding(get: { ShiftEditorViewModel.time(v) }, set: { value = ShiftEditorViewModel.tod($0) }),
                           displayedComponents: .hourAndMinute)
                Button("Clear", systemImage: "xmark.circle.fill") { value = nil }.labelStyle(.iconOnly).foregroundStyle(.secondary)
            }
        } else {
            Button("Set \(title.lowercased())") { value = TimeOfDay(hour: 9) }
        }
    }
}
