import Foundation

/// Rounds like JS `+(x).toFixed(2)` for the values this app handles (half away from zero).
@inlinable
public func round2(_ value: Double) -> Double {
    (value * 100).rounded(.toNearestOrAwayFromZero) / 100
}

public enum MoneyFormat {
    /// "$1,234.56" in AUD.
    public static func aud(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "AUD"
        f.currencySymbol = "$"
        f.locale = Locale(identifier: "en_AU")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    public static func hours(_ value: Double) -> String {
        let r = round2(value)
        return r == r.rounded() ? String(format: "%.0fh", r) : String(format: "%.2fh", r)
    }
}
