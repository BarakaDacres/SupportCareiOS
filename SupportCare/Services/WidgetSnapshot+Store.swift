import Foundation
import SupportCareCore

extension WidgetSnapshot {
    @MainActor
    static func write(from store: DataStore) {
        let week = store.weekSummary
        let next = store.upcomingShifts.first { shift in
            shift.date.date().addingTimeInterval(TimeInterval(shift.endTime.minutes * 60)) > Date()
        }
        let snapshot = WidgetSnapshot(
            weekGross: week.gross, weekHours: week.hours, weeklyGoal: store.resolvedSettings.weeklyGoal,
            nextShift: next.map { s in
                let start = s.date.date().addingTimeInterval(TimeInterval(s.startTime.minutes * 60))
                var endMin = s.endTime.minutes
                if endMin <= s.startTime.minutes { endMin += 1440 }
                return .init(clientName: store.client(s.clientId)?.shownName ?? "Shift", start: start,
                             end: s.date.date().addingTimeInterval(TimeInterval(endMin * 60)), isSleepover: s.isSleepover)
            },
            updatedAt: Date())
        if snapshot != read() { snapshot.save() }
    }
}
