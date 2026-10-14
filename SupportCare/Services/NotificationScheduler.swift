import Foundation
@preconcurrency import UserNotifications
import SupportCareCore

/// Local notifications: a reminder 1 hour before each upcoming shift (next 14 days) and
/// a 9am alert on the day an unpaid invoice becomes overdue. Ports `notifications.ts`,
/// moved from browser notifications to UNUserNotificationCenter.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func refresh(store: DataStore) {
        let settings = store.resolvedSettings
        var requests: [UNNotificationRequest] = []
        let now = Date()

        if settings.resolvedShiftReminders {
            let horizon = store.today.adding(days: 14)
            for shift in store.upcomingShifts where shift.date <= horizon {
                let start = shift.date.date().addingTimeInterval(TimeInterval(shift.startTime.minutes * 60))
                let fire = start.addingTimeInterval(-3600)
                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = shift.isSleepover ? "Sleepover in 1 hour" : "Shift in 1 hour"
                content.body = "\(store.client(shift.clientId)?.shownName ?? "Shift") · \(shift.startTime.twelveHour) – \(shift.endTime.twelveHour)"
                content.sound = .default
                requests.append(request("shift-\(shift.id.uuidString)", content, at: fire))
            }
        }

        if settings.resolvedInvoiceReminders {
            for inv in store.invoices where inv.status != InvoiceStatus.paid.rawValue {
                guard let due = inv.dueDate else { continue }
                var comps = DateComponents(year: due.year, month: due.month, day: due.day + 1, hour: 9)
                comps.calendar = .current
                guard let fire = comps.date, fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Invoice overdue"
                content.body = "Invoice \(inv.invoiceNumber) is past due"
                content.sound = .default
                requests.append(request("overdue-\(inv.invoiceNumber)", content, at: fire))
            }
        }

        let center = self.center
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier)
                .filter { $0.hasPrefix("shift-") || $0.hasPrefix("overdue-") }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            for r in requests.prefix(60) { try? await center.add(r) } // iOS caps pending at 64
        }
    }

    private func request(_ id: String, _ content: UNNotificationContent, at date: Date) -> UNNotificationRequest {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(identifier: id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }
}
