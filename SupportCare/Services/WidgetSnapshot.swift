import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Small Codable snapshot written to the App Group for the widget (shared by both targets).
struct WidgetSnapshot: Codable, Equatable {
    struct NextShift: Codable, Equatable {
        var clientName: String
        var start: Date
        var end: Date
        var isSleepover: Bool
    }

    var weekGross: Double
    var weekHours: Double
    var weeklyGoal: Double?
    var nextShift: NextShift?
    var updatedAt: Date

    static let key = "widget.snapshot"

    static var appGroup: String {
        (Bundle.main.object(forInfoDictionaryKey: "APP_GROUP") as? String) ?? "group.com.barakadacres.supportcare"
    }

    static func read() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static let placeholder = WidgetSnapshot(
        weekGross: 1_245, weekHours: 18.5, weeklyGoal: 2_000,
        nextShift: .init(clientName: "Jordan", start: Date().addingTimeInterval(3600 * 3),
                         end: Date().addingTimeInterval(3600 * 9), isSleepover: false),
        updatedAt: Date())
}
