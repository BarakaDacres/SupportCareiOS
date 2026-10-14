import Foundation

/// iCalendar export (port of `calendarExport.ts`). Events use floating local time.
public struct CalendarEvent: Hashable, Sendable {
    public var uid: String
    public var title: String
    public var date: CivilDate
    public var start: TimeOfDay
    public var end: TimeOfDay
    public var location: String?
    public var notes: String?

    public init(uid: String, title: String, date: CivilDate, start: TimeOfDay, end: TimeOfDay, location: String? = nil, notes: String? = nil) {
        self.uid = uid; self.title = title; self.date = date; self.start = start; self.end = end
        self.location = location; self.notes = notes
    }

    public init(shift: Shift, clientName: String?) {
        self.init(uid: "\(shift.id.uuidString.lowercased())@supportcare",
                  title: shift.isSleepover ? "Sleepover · \(clientName ?? "Shift")" : "Support · \(clientName ?? "Shift")",
                  date: shift.date, start: shift.startTime, end: shift.endTime, notes: shift.notes)
    }
}

public enum ICS {
    static func stamp(_ d: CivilDate, _ t: TimeOfDay) -> String {
        String(format: "%04d%02d%02dT%02d%02d00", d.year, d.month, d.day, t.hour % 24, t.minute)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
    }

    public static func vevent(_ e: CalendarEvent, sequence: Int = 0, now: Date = Date()) -> [String] {
        let endDate = e.end.minutes <= e.start.minutes ? e.date.adding(days: 1) : e.date
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        var lines = [
            "BEGIN:VEVENT",
            "UID:\(e.uid)",
            "SEQUENCE:\(sequence)",
            "DTSTAMP:\(f.string(from: now))",
            "DTSTART:\(stamp(e.date, e.start))",
            "DTEND:\(stamp(endDate, e.end))",
            "SUMMARY:\(escape(e.title))",
        ]
        if let l = e.location, !l.isEmpty { lines.append("LOCATION:\(escape(l))") }
        if let n = e.notes, !n.isEmpty { lines.append("DESCRIPTION:\(escape(n))") }
        lines.append("END:VEVENT")
        return lines
    }

    public static func calendar(_ events: [CalendarEvent], now: Date = Date()) -> String {
        (["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Support Care//iOS//EN", "CALSCALE:GREGORIAN"]
            + events.flatMap { vevent($0, now: now) } + ["END:VCALENDAR"]).joined(separator: "\r\n") + "\r\n"
    }
}
