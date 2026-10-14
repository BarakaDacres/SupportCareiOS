import EventKit
import Foundation
import SupportCareCore

/// Adds shifts to the user's calendar with EventKit (write-only access, iOS 17+).
/// Also offers .ics export via `ICS.calendar` for sharing.
@MainActor
enum CalendarSync {
    private static let store = EKEventStore()

    static func add(_ shifts: [Shift], clientName: (Shift) -> String?) async throws -> Int {
        guard try await store.requestWriteOnlyAccessToEvents() else { return 0 }
        var added = 0
        for shift in shifts {
            let event = EKEvent(eventStore: store)
            let e = CalendarEvent(shift: shift, clientName: clientName(shift))
            event.title = e.title
            event.startDate = shift.date.date().addingTimeInterval(TimeInterval(shift.startTime.minutes * 60))
            var endMin = shift.endTime.minutes
            if endMin <= shift.startTime.minutes { endMin += 1440 }
            event.endDate = shift.date.date().addingTimeInterval(TimeInterval(endMin * 60))
            event.notes = shift.notes
            event.calendar = store.defaultCalendarForNewEvents
            try store.save(event, span: .thisEvent, commit: false)
            added += 1
        }
        try store.commit()
        return added
    }

    static func icsFile(_ shifts: [Shift], clientName: (Shift) -> String?) throws -> URL {
        let text = ICS.calendar(shifts.map { CalendarEvent(shift: $0, clientName: clientName($0)) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Support Care shifts.ics")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
