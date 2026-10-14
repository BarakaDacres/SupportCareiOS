import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .placeholder : (WidgetSnapshot.read() ?? .placeholder)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snap = WidgetSnapshot.read() ?? WidgetSnapshot(weekGross: 0, weekHours: 0, weeklyGoal: nil, nextShift: nil, updatedAt: Date())
        // Refresh after the next shift starts (so it rolls to the following one) or in an hour.
        let next = snap.nextShift.map { min($0.start, Date().addingTimeInterval(3600)) } ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [SnapshotEntry(date: Date(), snapshot: snap)], policy: .after(max(next, Date().addingTimeInterval(300)))))
    }
}

struct SupportCareWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(s.weekGross, format: .currency(code: "AUD").precision(.fractionLength(0))).font(.headline)
                if let n = s.nextShift { Text("Next: \(n.clientName) \(n.start, style: .time)").font(.caption) }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label("This week", systemImage: "chart.line.uptrend.xyaxis").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(s.weekGross, format: .currency(code: "AUD").precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .contentTransition(.numericText(value: s.weekGross))
                    .minimumScaleFactor(0.6)
                if let goal = s.weeklyGoal, goal > 0 {
                    ProgressView(value: min(1, s.weekGross / goal)).tint(.green)
                }
                Spacer(minLength: 0)
                if let n = s.nextShift {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n.isSleepover ? "Next sleepover" : "Next shift").font(.caption2).foregroundStyle(.secondary)
                        Text(n.clientName).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(n.start, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.caption2)
                    }
                } else {
                    Text("No upcoming shifts").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

@main
struct SupportCareWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SupportCareWeek", provider: SnapshotProvider()) { entry in
            SupportCareWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("This week")
        .description("Earnings this week and your next shift.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
