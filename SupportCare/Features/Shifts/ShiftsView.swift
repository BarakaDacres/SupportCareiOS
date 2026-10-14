import SwiftUI
import UIKit
import SupportCareCore

enum ShiftFilter: String, CaseIterable, Identifiable {
    case upcoming, week, month, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .upcoming: "Upcoming"
        case .week: "This week"
        case .month: "This month"
        case .all: "All"
        }
    }
}

/// Shift list grouped by day (port of ShiftList / EntryTable).
struct ShiftsView: View {
    @Environment(DataStore.self) private var store
    @State private var filter: ShiftFilter = .week
    @State private var clientFilter: UUID?
    @State private var search = ""
    @State private var editing: ShiftEditorView.Mode?
    @State private var showTemplates = false
    @State private var exportURL: URL?
    @State private var calendarMessage: String?
    @Namespace private var zoom

    private var filtered: [Shift] {
        let base: [Shift]
        switch filter {
        case .upcoming: base = store.upcomingShifts
        case .week: base = store.shifts.filter { store.currentWeek.contains($0.date) }
        case .month: base = store.shifts.filter { store.currentMonth.contains($0.date) }
        case .all: base = store.shifts
        }
        return base.filter { s in
            (clientFilter == nil || s.clientId == clientFilter) &&
            (search.isEmpty || (store.client(s.clientId)?.shownName ?? "").localizedCaseInsensitiveContains(search)
                || (s.notes ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    private var grouped: [(date: CivilDate, shifts: [Shift])] {
        let dict = Dictionary(grouping: filtered, by: \.date)
        let keys = filter == .upcoming ? dict.keys.sorted() : dict.keys.sorted(by: >)
        return keys.map { ($0, dict[$0]!.sorted { $0.startTime < $1.startTime }) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                    GlassChips(options: ShiftFilter.allCases, selection: $filter, title: \.title)
                        .padding(.horizontal, -16)
                    summary
                    if grouped.isEmpty {
                        EmptyStateView(title: "No shifts", message: "Log a shift or apply a template to get started.",
                                       systemImage: "calendar.badge.plus", actionTitle: "Log shift") {
                            editing = .create(date: store.today)
                        }
                        .padding(.top, 40)
                    }
                    ForEach(grouped, id: \.date) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            DayHeader(date: day.date, holiday: store.detectedHoliday(on: day.date), total: day.shifts.reduce(0) { $0 + $1.effectiveGross })
                            ForEach(day.shifts) { shift in
                                Button { editing = .edit(shift) } label: {
                                    ShiftRow(shift: shift)
                                        .matchedTransitionSource(id: shift.id, in: zoom)
                                }
                                .buttonStyle(.plain)
                                .scrollEntrance()
                                .contextMenu { contextMenu(for: shift) }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .animation(Motion.smooth, value: filtered.map(\.id))
            }
            .navigationTitle("Shifts")
            .searchable(text: $search, prompt: "Client or notes")
            .refreshable { await store.loadAll() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { clientMenu }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Templates", systemImage: "square.stack.3d.up") { showTemplates = true }
                    Menu("Export", systemImage: "square.and.arrow.up") {
                        Button("Add to Calendar", systemImage: "calendar.badge.plus") { Task { await addToCalendar() } }
                        Button("Export .ics", systemImage: "doc") {
                            exportURL = try? CalendarSync.icsFile(filtered) { store.client($0.clientId)?.shownName }
                        }
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log shift", systemImage: "plus") { editing = .create(date: store.today) }
                        .buttonStyle(.glassProminent)
                }
            }
            .sheet(item: $editing) { mode in
                ShiftEditorView(mode: mode)
                    .navigationTransition(.zoom(sourceID: mode.shiftId, in: zoom))
            }
            .sheet(isPresented: $showTemplates) { TemplatesView() }
            .sheet(item: $exportURL) { url in ShareSheet(items: [url]).presentationDetents([.medium]) }
            .alert("Calendar", isPresented: Binding(get: { calendarMessage != nil }, set: { if !$0 { calendarMessage = nil } })) {
                Button("OK") {}
            } message: { Text(calendarMessage ?? "") }
        }
    }

    private var summary: some View {
        let s = Analytics.summarize(filtered)
        return HStack(spacing: 12) {
            StatTile(title: "Earned", value: s.gross, tint: Theme.money, symbol: "dollarsign.circle.fill")
            StatTile(title: "Hours", value: s.hours, kind: .hours, symbol: "clock.fill")
            StatTile(title: "Shifts", value: Double(s.shiftCount), kind: .count, tint: Theme.purple, symbol: "list.bullet")
        }
    }

    private var clientMenu: some View {
        Menu {
            Picker("Client", selection: $clientFilter) {
                Text("All clients").tag(UUID?.none)
                ForEach(store.activeClients) { Text($0.shownName).tag(Optional($0.id)) }
            }
        } label: {
            Label(store.client(clientFilter)?.shownName ?? "All clients", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    @ViewBuilder
    private func contextMenu(for shift: Shift) -> some View {
        Button("Edit", systemImage: "pencil") { editing = .edit(shift) }
        Button("Duplicate to next week", systemImage: "plus.square.on.square") {
            Task { await store.duplicate(shift: shift, to: shift.date.adding(days: 7)) }
        }
        Button("Duplicate to tomorrow", systemImage: "arrow.right.square") {
            Task { await store.duplicate(shift: shift, to: shift.date.adding(days: 1)) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { Task { await store.delete(shift: shift) } }
    }

    private func addToCalendar() async {
        do {
            let n = try await CalendarSync.add(filtered) { store.client($0.clientId)?.shownName }
            calendarMessage = n == 0 ? "Calendar access wasn't granted." : "Added \(n) shift\(n == 1 ? "" : "s") to your calendar."
        } catch { calendarMessage = error.localizedDescription }
    }
}

struct DayHeader: View {
    let date: CivilDate
    var holiday: PublicHoliday?
    var total: Double

    var body: some View {
        let isToday = date == .today()
        HStack(alignment: .firstTextBaseline) {
            Text(date.date(), format: .dateTime.weekday(.wide).day().month(.abbreviated))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isToday ? Theme.primary : .primary)
            if isToday { Badge(text: "Today", color: Theme.primary) }
            if let holiday { Badge(text: holiday.name, color: Theme.publicHoliday, symbol: "flag.fill") }
            Spacer()
            Text(total, format: .currency(code: "AUD")).font(.footnote.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.top, 4)
    }
}

struct ShiftRow: View {
    @Environment(DataStore.self) private var store
    let shift: Shift

    var body: some View {
        let style = ShiftStyle.of(shift, evening: store.evening)
        HStack(spacing: 14) {
            Image(systemName: style.symbol)
                .font(.title3)
                .foregroundStyle(style.color)
                .frame(width: 44, height: 44)
                .background(style.color.opacity(0.14), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(store.client(shift.clientId)?.shownName ?? "No client").font(.body.weight(.semibold))
                Text("\(shift.startTime.twelveHour) – \(shift.endTime.twelveHour) · \(MoneyFormat.hours(shift.hoursWorked))")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    if shift.isPublicHoliday { Badge(text: "PH", color: Theme.publicHoliday) }
                    if shift.isOvertime { Badge(text: "OT", color: Theme.amber) }
                    if (shift.feeOverride ?? 0) > 0 { Badge(text: "Custom fee", color: Theme.purple) }
                }
            }
            Spacer()
            Text(shift.effectiveGross, format: .currency(code: "AUD"))
                .font(.body.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Theme.money)
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: Theme.radius))
        .contentShape(.rect(cornerRadius: Theme.radius))
        .accessibilityElement(children: .combine)
    }
}

/// UIKit share sheet wrapper (ShareLink can't take a late-created file URL from a menu action).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
