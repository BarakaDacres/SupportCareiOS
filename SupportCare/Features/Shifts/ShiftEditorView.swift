import SwiftUI
import SupportCareCore

@MainActor
@Observable
final class ShiftEditorViewModel {
    var shift: Shift
    let isNew: Bool
    var date: Date
    var start: Date
    var end: Date
    var useFeeOverride: Bool
    /// True once the user changes the PH toggle, so auto-detect stops overriding it.
    var phTouched = false
    var detectedHoliday: PublicHoliday?

    init(shift: Shift, isNew: Bool) {
        self.shift = shift
        self.isNew = isNew
        date = shift.date.date()
        start = Self.time(shift.startTime)
        end = Self.time(shift.endTime)
        useFeeOverride = (shift.feeOverride ?? 0) > 0
    }

    static func time(_ t: TimeOfDay) -> Date {
        Calendar.current.date(bySettingHour: t.hour % 24, minute: t.minute, second: 0, of: Date()) ?? Date()
    }

    static func tod(_ d: Date) -> TimeOfDay {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    /// Pushes picker values into the model and applies holiday auto-detect.
    func sync(store: DataStore) {
        shift.date = CivilDate(date)
        shift.startTime = Self.tod(start)
        shift.endTime = Self.tod(end)
        if !useFeeOverride { shift.feeOverride = nil }
        detectedHoliday = store.detectedHoliday(on: shift.date)
        if !phTouched, store.resolvedSettings.resolvedHolidayAutoDetect {
            shift.isPublicHoliday = detectedHoliday != nil
        }
    }

    func applySleepoverDefaults(store: DataStore) {
        guard shift.isSleepover else { return }
        start = Self.time(store.resolvedSettings.resolvedSleepoverStart == TimeOfDay(hour: 0) ? TimeOfDay(hour: 22) : store.resolvedSettings.resolvedSleepoverStart)
        end = Self.time(store.resolvedSettings.resolvedSleepoverEnd)
    }

    func applyClientDefaults(_ client: Client?) {
        guard isNew, let client else { return }
        if let s = client.defaultStartTime { start = Self.time(s) }
        if let e = client.defaultEndTime { end = Self.time(e) }
        shift.isSleepover = client.defaultIsSleepover
        if (shift.notes ?? "").isEmpty, let note = client.defaultServiceNote { shift.notes = note }
    }
}

/// Create / edit a shift with a live pay breakdown (port of ShiftForm.tsx).
struct ShiftEditorView: View {
    enum Mode: Identifiable, Hashable {
        case create(date: CivilDate)
        case edit(Shift)
        case fromTemplate(Shift)

        var id: String {
            switch self {
            case .create(let d): "new-\(d.iso)"
            case .edit(let s): s.id.uuidString
            case .fromTemplate(let s): "tpl-\(s.id.uuidString)"
            }
        }
        var shiftId: AnyHashable {
            switch self {
            case .edit(let s): s.id
            default: "new"
            }
        }
    }

    let mode: Mode
    var body: some View { ShiftEditorContent(mode: mode) }
}

private struct ShiftEditorContent: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mode: ShiftEditorView.Mode
    @State private var vm: ShiftEditorViewModel?
    @State private var saved = 0
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            if let vm {
                form(vm)
            } else {
                ProgressView().onAppear(perform: setup)
            }
        }
        .presentationDetents([.large])
    }

    private func setup() {
        let m: ShiftEditorViewModel
        switch mode {
        case .create(let date):
            let lastClient = store.shifts.first?.clientId ?? store.activeClients.first?.id
            var s = Shift(userId: store.userId, clientId: lastClient, date: date, startTime: TimeOfDay(hour: 9), endTime: TimeOfDay(hour: 15))
            s.notes = nil
            m = ShiftEditorViewModel(shift: s, isNew: true)
            m.applyClientDefaults(store.client(lastClient))
        case .edit(let s):
            m = ShiftEditorViewModel(shift: s, isNew: false)
            m.phTouched = true
        case .fromTemplate(let s):
            m = ShiftEditorViewModel(shift: s, isNew: true)
        }
        m.sync(store: store)
        vm = m
    }

    @ViewBuilder
    private func form(_ vm: ShiftEditorViewModel) -> some View {
        @Bindable var vm = vm
        let calc = store.calculation(for: vm.shift.input, clientId: vm.shift.clientId)
        let shown = calc.effectiveGross(feeOverride: vm.shift.feeOverride)

        Form {
            Section {
                VStack(spacing: 4) {
                    MoneyText(value: shown, font: .system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.money)
                    Text(MoneyFormat.hours(calc.hoursWorked)).font(.subheadline).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                Picker("Client", selection: $vm.shift.clientId) {
                    Text("No client").tag(UUID?.none)
                    ForEach(store.activeClients) { Text($0.shownName).tag(Optional($0.id)) }
                }
                .onChange(of: vm.shift.clientId) { _, id in vm.applyClientDefaults(store.client(id)); vm.sync(store: store) }
                DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                DatePicker("Start", selection: $vm.start, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $vm.end, displayedComponents: .hourAndMinute)
                if vm.shift.endTime <= vm.shift.startTime {
                    Label("Ends the next day", systemImage: "moon.zzz.fill").font(.footnote).foregroundStyle(Theme.sleepover)
                }
            }
            .onChange(of: vm.date) { vm.sync(store: store) }
            .onChange(of: vm.start) { vm.sync(store: store) }
            .onChange(of: vm.end) { vm.sync(store: store) }

            Section {
                Toggle(isOn: $vm.shift.isSleepover.animation(Motion.snappy)) {
                    Label("Sleepover", systemImage: "moon.stars.fill")
                }
                .onChange(of: vm.shift.isSleepover) { vm.applySleepoverDefaults(store: store); vm.sync(store: store) }
                Toggle(isOn: Binding(get: { vm.shift.isPublicHoliday }, set: { vm.shift.isPublicHoliday = $0; vm.phTouched = true })) {
                    VStack(alignment: .leading) {
                        Label("Public holiday", systemImage: "flag.fill")
                        if let h = vm.detectedHoliday {
                            Text("Detected: \(h.name)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(isOn: $vm.shift.isOvertime) { Label("Overtime", systemImage: "bolt.fill") }
                Toggle(isOn: $vm.useFeeOverride.animation(Motion.snappy)) { Label("Custom fee", systemImage: "pencil.and.list.clipboard") }
                    .onChange(of: vm.useFeeOverride) { vm.sync(store: store) }
                if vm.useFeeOverride {
                    OptionalCurrencyField(title: "Fee", value: $vm.shift.feeOverride, placeholder: calc.grossPay.formatted(.currency(code: "AUD")))
                }
            }

            Section("Breakdown") {
                ForEach(Array(calc.breakdown.enumerated()), id: \.offset) { _, line in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(line.label).font(.subheadline)
                            if let h = line.hours, let r = line.rate {
                                Text("\(MoneyFormat.hours(h)) × \(r.formatted(.currency(code: "AUD")))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(line.amount, format: .currency(code: "AUD")).monospacedDigit()
                    }
                    .transition(.push(from: .trailing))
                }
            }
            .animation(Motion.smooth, value: calc)

            Section("Notes") {
                TextField("Service notes", text: $vm.shift.notes.orEmpty, axis: .vertical).lineLimit(3...8)
                Menu("Insert smart note") {
                    ForEach(ShiftType.allCases, id: \.self) { t in
                        Button(t.label, systemImage: t.symbol) { vm.shift.notes = t.smartNote }
                    }
                }
            }

            if !vm.isNew {
                Section {
                    Button("Delete shift", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(vm.isNew ? "New shift" : "Edit shift")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") {
                    vm.sync(store: store)
                    Task {
                        if await store.save(shift: vm.shift) { saved += 1; dismiss() }
                    }
                }
                .buttonStyle(.glassProminent)
            }
        }
        .confirmationDialog("Delete this shift?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await store.delete(shift: vm.shift); dismiss() } }
        }
        .appHaptic(.success, trigger: saved, enabled: store.resolvedSettings.resolvedHaptics)
    }
}
