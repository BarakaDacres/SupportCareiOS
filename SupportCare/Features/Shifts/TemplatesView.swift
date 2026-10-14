import SwiftUI
import SupportCareCore

/// Shift templates manager + picker (ShiftTemplatesManager / TemplatePicker).
struct TemplatesView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ShiftTemplate?
    @State private var applying: ShiftTemplate?
    @State private var applyDate = Date()
    @State private var createdFrom: ShiftEditorView.Mode?

    var body: some View {
        NavigationStack {
            List {
                if store.templates.isEmpty {
                    EmptyStateView(title: "No templates", message: "Save your regular shifts as templates to log them in two taps.",
                                   systemImage: "square.stack.3d.up")
                }
                ForEach(store.templates) { t in
                    HStack(spacing: 12) {
                        Image(systemName: t.type.symbol).foregroundStyle(Theme.primary).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(t.name).font(.body.weight(.semibold))
                            Text("\(store.client(t.clientId)?.shownName ?? "Any client") · \(t.startTime.twelveHour) – \(t.endTime.twelveHour)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Use") { applying = t }.buttonStyle(.glass)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { Task { await store.delete(template: t) } }
                        Button("Edit", systemImage: "pencil") { editing = t }
                    }
                }
            }
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("New", systemImage: "plus") {
                        editing = ShiftTemplate(userId: store.userId, clientId: store.activeClients.first?.id, name: "",
                                                shiftType: .day, startTime: TimeOfDay(hour: 9), endTime: TimeOfDay(hour: 15))
                    }
                }
            }
            .sheet(item: $editing) { TemplateEditor(template: $0) }
            .sheet(item: $applying) { t in
                NavigationStack {
                    Form { DatePicker("Date", selection: $applyDate, displayedComponents: .date).datePickerStyle(.graphical) }
                        .navigationTitle(t.name)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add shift") {
                                    let shift = store.makeShift(from: t, on: CivilDate(applyDate))
                                    applying = nil
                                    Task { await store.save(shift: shift); dismiss() }
                                }
                                .buttonStyle(.glassProminent)
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

private struct TemplateEditor: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var template: ShiftTemplate

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $template.name)
                Picker("Type", selection: Binding(get: { template.type }, set: { t in
                    template.shiftType = t.rawValue
                    template.isSleepover = t == .sleepover
                    if (template.notes ?? "").isEmpty { template.notes = t.smartNote }
                })) {
                    ForEach(ShiftType.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Client", selection: $template.clientId) {
                    Text("Any client").tag(UUID?.none)
                    ForEach(store.activeClients) { Text($0.shownName).tag(Optional($0.id)) }
                }
                DatePicker("Start", selection: timeBinding(\.startTime), displayedComponents: .hourAndMinute)
                DatePicker("End", selection: timeBinding(\.endTime), displayedComponents: .hourAndMinute)
                TextField("Notes", text: $template.notes.orEmpty, axis: .vertical)
            }
            .navigationTitle(template.name.isEmpty ? "New template" : template.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await store.save(template: template); dismiss() } }
                        .disabled(template.name.isEmpty)
                }
            }
        }
    }

    private func timeBinding(_ kp: WritableKeyPath<ShiftTemplate, TimeOfDay>) -> Binding<Date> {
        Binding(get: { ShiftEditorViewModel.time(template[keyPath: kp]) },
                set: { template[keyPath: kp] = ShiftEditorViewModel.tod($0) })
    }
}

