import Charts
import SwiftUI
import SupportCareCore

/// Last-12-months bar chart (YearlyOverview).
struct YearChart: View {
    @Environment(DataStore.self) private var store
    @State private var selectedMonth: String?

    var body: some View {
        let data = Analytics.monthly(store.shifts, through: store.today)
        Card {
            SectionHeader(title: "Last 12 months", systemImage: "chart.bar.fill")
            Chart(data) { m in
                BarMark(x: .value("Month", String(Periods.month(year: m.year, month: m.month).label.prefix(3))),
                        y: .value("Gross", m.summary.gross))
                    .foregroundStyle(m.id == "\(store.today.year)-\(store.today.month)" ? Theme.primary.gradient : Theme.primary.opacity(0.45).gradient)
                    .cornerRadius(6)
            }
            .chartYAxis { AxisMarks(format: .currency(code: "AUD").precision(.fractionLength(0))) }
            .frame(height: 180)
            .animation(Motion.smooth, value: data.map(\.summary.gross))
        }
    }
}

/// Income insights + tax table (AnalyticsPanel).
struct AnalyticsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case month, quarter, fy
        var id: String { rawValue }
        var title: String { self == .fy ? "Fin. year" : rawValue.capitalized }
    }

    @Environment(DataStore.self) private var store
    @State private var range: Range = .month

    private var dateRange: DateRange {
        let t = store.today
        switch range {
        case .month: return store.currentMonth
        case .quarter: return DateRange(start: t.adding(days: -90), end: t, label: "Last 90 days")
        case .fy: return Periods.financialYear(containing: t)
        }
    }

    var body: some View {
        let shifts = store.shifts.filter { dateRange.contains($0.date) }
        let summary = Analytics.summarize(shifts)
        let byCat = Analytics.byCategory(shifts, rates: { store.rates(for: $0.clientId) }, evening: store.evening)
            .sorted { $0.value > $1.value }
        let byClient = Dictionary(grouping: shifts, by: \.clientId).map { (store.client($0.key)?.shownName ?? "No client", Analytics.summarize($0.value).gross) }
            .sorted { $0.1 > $1.1 }
        let settings = store.resolvedSettings

        VStack(alignment: .leading, spacing: 16) {
            GlassSegmentedControl(options: Range.allCases, selection: $range, title: \.title)
            HStack(spacing: 12) {
                StatTile(title: "Gross", value: summary.gross, tint: Theme.money, symbol: "dollarsign.circle.fill")
                StatTile(title: "Avg / hour", value: summary.effectiveHourly, symbol: "speedometer")
            }
            HStack(spacing: 12) {
                StatTile(title: "Hours", value: summary.hours, kind: .hours, symbol: "clock.fill")
                StatTile(title: "Sleepovers", value: Double(summary.sleepovers), kind: .count, tint: Theme.sleepover, symbol: "moon.stars.fill")
            }
            if !byCat.isEmpty {
                Card {
                    SectionHeader(title: "By rate type", systemImage: "chart.pie.fill")
                    Chart(byCat, id: \.key) { item in
                        SectorMark(angle: .value("Amount", item.value), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .foregroundStyle(by: .value("Type", item.key.label))
                            .cornerRadius(4)
                    }
                    .frame(height: 200)
                }
            }
            if !byClient.isEmpty {
                Card {
                    SectionHeader(title: "By client", systemImage: "person.2.fill")
                    ForEach(byClient, id: \.0) { item in
                        LabeledContent(item.0) { Text(item.1, format: .currency(code: "AUD")).monospacedDigit() }
                    }
                }
            }
            if settings.showTaxEstimate && settings.taxRate > 0 {
                let t = settings.taxEstimate(forGross: summary.gross)
                Card {
                    SectionHeader(title: "Tax estimate (\(settings.taxRate.formatted())%)", systemImage: "building.columns")
                    LabeledContent("Gross") { Text(t.gross, format: .currency(code: "AUD")) }
                    LabeledContent("Estimated tax") { Text("−" + t.tax.formatted(.currency(code: "AUD"))).foregroundStyle(Theme.red) }
                    LabeledContent("Net") { Text(t.net, format: .currency(code: "AUD")).bold() }
                    Text("An estimate only, not tax advice.").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .animation(Motion.smooth, value: range)
    }
}
