import SwiftUI
import SupportCareCore

/// Overview (port of OverviewPanel): greeting, week/month stats, goals, tax estimate, upcoming shifts.
struct HomeView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppModel.self) private var app
    @Binding var selection: AppTab
    @State private var editing: ShiftEditorView.Mode?
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greeting
                    if app.isDemo { Banner(kind: .info, text: "Demo mode: sample data only, nothing is saved to the cloud.") }
                    if let e = store.lastError { Banner(kind: .error, text: e).onTapGesture { store.lastError = nil } }
                    weekHero
                    HStack(spacing: 12) {
                        StatTile(title: "This month", value: store.monthSummary.gross, tint: Theme.money, symbol: "calendar")
                        StatTile(title: "Hours this month", value: store.monthSummary.hours, kind: .hours, symbol: "clock.fill")
                    }
                    goals
                    taxCard
                    upcoming
                    YearChart()
                }
                .padding()
            }
            .navigationTitle("Home")
            .toolbarTitleDisplayMode(.inlineLarge)
            .refreshable { await store.loadAll() }
            .sheet(item: $editing) { mode in
                ShiftEditorView(mode: mode).navigationTransition(.zoom(sourceID: mode.shiftId, in: zoom))
            }
        }
    }

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let name = store.profile?.displayName?.split(separator: " ").first.map(String.init)
        return VStack(alignment: .leading, spacing: 2) {
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.subheadline).foregroundStyle(.secondary)
            Text(name.map { "\(part), \($0)" } ?? part).font(.title2.bold())
        }
    }

    private var weekHero: some View {
        let week = store.weekSummary
        let goal = store.resolvedSettings.weeklyGoal
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("This week").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                MoneyText(value: week.gross, font: .system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("\(MoneyFormat.hours(week.hours)) · \(week.shiftCount) shift\(week.shiftCount == 1 ? "" : "s") · \(store.currentWeek.label)")
                    .font(.footnote).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            if let p = Analytics.progress(week.gross, goal: goal) {
                ZStack {
                    ProgressRing(progress: p, tint: .white, lineWidth: 7)
                    Text("\(Int(p * 100))%").font(.caption.bold()).foregroundStyle(.white).contentTransition(.numericText())
                }
                .frame(width: 64, height: 64)
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [Theme.primary, Theme.purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: Theme.radiusLarge))
    }

    @ViewBuilder
    private var goals: some View {
        let s = store.resolvedSettings
        if s.monthlyGoal != nil || s.yearlyGoal != nil {
            Card {
                SectionHeader(title: "Goals", systemImage: "target")
                if let g = s.monthlyGoal { goalRow("Monthly", store.monthSummary.gross, g) }
                if let g = s.yearlyGoal { goalRow("Financial year", store.financialYearSummary.gross, g) }
            }
        }
    }

    private func goalRow(_ title: String, _ value: Double, _ goal: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(value.formatted(.currency(code: "AUD"))) of \(goal.formatted(.currency(code: "AUD").precision(.fractionLength(0))))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: Analytics.progress(value, goal: goal) ?? 0).tint(Theme.money)
                .animation(Motion.gentle, value: value)
        }
    }

    @ViewBuilder
    private var taxCard: some View {
        let s = store.resolvedSettings
        if s.showTaxEstimate && s.taxRate > 0 {
            let t = s.taxEstimate(forGross: store.monthSummary.gross)
            Card {
                SectionHeader(title: "Monthly tax estimate (\(s.taxRate.formatted())%)", systemImage: "building.columns")
                HStack {
                    VStack(alignment: .leading) {
                        Text("Set aside").font(.caption).foregroundStyle(.secondary)
                        MoneyText(value: t.tax, font: .headline).foregroundStyle(Theme.red)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Take home").font(.caption).foregroundStyle(.secondary)
                        MoneyText(value: t.net, font: .headline)
                    }
                }
            }
        }
    }

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Upcoming", systemImage: "calendar.badge.clock")
                Spacer()
                Button("See all") { selection = .shifts }.font(.footnote.weight(.semibold))
            }
            if store.upcomingShifts.isEmpty {
                Card {
                    Text("Nothing scheduled.").foregroundStyle(.secondary)
                    Button("Log a shift", systemImage: "plus") { editing = .create(date: store.today) }.buttonStyle(.glass)
                }
            }
            ForEach(store.upcomingShifts.prefix(4)) { shift in
                Button { editing = .edit(shift) } label: {
                    ShiftRow(shift: shift).matchedTransitionSource(id: shift.id, in: zoom)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
