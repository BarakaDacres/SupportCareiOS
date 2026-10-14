import SwiftUI

/// Colour tokens ported from the web app's `index.css` (HSL values converted to SwiftUI).
/// Neutrals use system semantic colours so light and dark mode adapt automatically.
enum Theme {
    // Brand
    static let primary = Color.accentColor                                          // 211 100% 50% / 58% dark
    // Semantic accents (hsl → Color(hue:saturation:brightness:) via HSL helper)
    static let money = Color(hsl: 126, 35, 51)
    static let moneyTint = Color(hsl: 123, 40, 96)
    static let amber = Color(hsl: 35, 65, 52)
    static let red = Color(hsl: 0, 72, 58)
    static let purple = Color(hsl: 262, 85, 76)
    static let evening = Color(hsl: 32, 58, 52)
    static let sleepover = Color(hsl: 248, 58, 68)
    static let weekend = Color(hsl: 265, 55, 65)
    static let publicHoliday = Color(hsl: 0, 72, 58)

    // Layout
    static let radius: CGFloat = 16     // --radius: 1rem
    static let radiusLarge: CGFloat = 24
    static let spacing: CGFloat = 16
}

extension Color {
    /// HSL initialiser so web tokens can be pasted verbatim (h 0–360, s/l 0–100).
    init(hsl h: Double, _ s: Double, _ l: Double, opacity: Double = 1) {
        let s = s / 100, l = l / 100
        let v = l + s * min(l, 1 - l)
        let sv = v == 0 ? 0 : 2 * (1 - l / v)
        self.init(hue: h / 360, saturation: sv, brightness: v, opacity: opacity)
    }
}

/// Colour + SF Symbol for each pay category / shift kind.
enum ShiftStyle {
    case day, evening, weekend, sleepover, publicHoliday, overtime

    var color: Color {
        switch self {
        case .day: Theme.primary
        case .evening: Theme.evening
        case .weekend: Theme.weekend
        case .sleepover: Theme.sleepover
        case .publicHoliday: Theme.publicHoliday
        case .overtime: Theme.amber
        }
    }

    var symbol: String {
        switch self {
        case .day: "sun.max.fill"
        case .evening: "sunset.fill"
        case .weekend: "calendar"
        case .sleepover: "moon.stars.fill"
        case .publicHoliday: "flag.fill"
        case .overtime: "bolt.fill"
        }
    }

    var label: String {
        switch self {
        case .day: "Day"
        case .evening: "Evening"
        case .weekend: "Weekend"
        case .sleepover: "Sleepover"
        case .publicHoliday: "Public holiday"
        case .overtime: "Overtime"
        }
    }
}

/// Appearance override (system / light / dark), stored per device.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
