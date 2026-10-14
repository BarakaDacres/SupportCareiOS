import SwiftUI

/// Motion tokens. The web app used `--ease-spring: cubic-bezier(.34,1.56,.64,1)`;
/// SwiftUI springs are the native equivalent.
enum Motion {
    static let snappy: Animation = .snappy(duration: 0.3)
    static let bouncy: Animation = .bouncy(duration: 0.45, extraBounce: 0.05)
    static let smooth: Animation = .smooth(duration: 0.35)
    static let gentle: Animation = .spring(response: 0.5, dampingFraction: 0.82)
}

extension View {
    /// Fades, scales and slightly blurs list rows as they scroll in and out.
    func scrollEntrance() -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.6)
                .scaleEffect(phase.isIdentity ? 1 : 0.96)
                .blur(radius: phase.isIdentity ? 0 : 1.5)
        }
    }

    /// Haptic that respects the user's haptics preference.
    func appHaptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T, enabled: Bool) -> some View {
        sensoryFeedback(trigger: trigger) { _, _ in enabled ? feedback : nil }
    }
}

/// Animated currency text that rolls digits (`.numericText`).
struct MoneyText: View {
    let value: Double
    var font: Font = .title.weight(.bold)

    var body: some View {
        Text(value, format: .currency(code: "AUD"))
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(Motion.snappy, value: value)
    }
}
