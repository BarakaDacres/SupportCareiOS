import SwiftUI
import SupportCareCore

/// Content card (not glass: content stays on solid grouped surfaces).
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: Theme.radius))
    }
}

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
    }
}

struct StatTile: View {
    let title: String
    enum Kind { case currency, hours, count }
    let value: Double
    var kind: Kind = .currency
    var tint: Color = Theme.primary
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            switch kind {
            case .currency:
                MoneyText(value: value, font: .title3.weight(.bold))
            case .hours, .count:
                Text(kind == .hours ? MoneyFormat.hours(value) : "\(Int(value))")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                    .animation(Motion.snappy, value: value)
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: Theme.radius))
    }
}

struct ProgressRing: View {
    let progress: Double
    var tint: Color = Theme.money
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.gentle, value: progress)
        }
    }
}

struct Badge: View {
    let text: String
    var color: Color
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: .capsule)
    }
}

/// Empty state with a gently breathing symbol.
struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .symbolEffect(.breathe, options: .repeating)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.glassProminent)
            }
        }
    }
}

/// Inline error / success banner.
struct Banner: View {
    enum Kind { case error, success, info }
    let kind: Kind
    let text: String

    var body: some View {
        Label(text, systemImage: kind == .error ? "exclamationmark.triangle.fill" : kind == .success ? "checkmark.circle.fill" : "info.circle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(kind == .error ? Theme.red : kind == .success ? Theme.money : Theme.primary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((kind == .error ? Theme.red : kind == .success ? Theme.money : Theme.primary).opacity(0.1),
                        in: .rect(cornerRadius: 12))
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Decimal currency input field.
struct CurrencyField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        LabeledContent(title) {
            TextField(title, value: $value, format: .currency(code: "AUD"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}

/// Optional currency input (nil = inherit).
struct OptionalCurrencyField: View {
    let title: String
    @Binding var value: Double?
    var placeholder: String = "Default"

    var body: some View {
        LabeledContent(title) {
            TextField(placeholder, value: $value, format: .currency(code: "AUD"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}

extension ShiftStyle {
    static func of(_ shift: Shift, evening: EveningWindow) -> ShiftStyle {
        if shift.isOvertime { return .overtime }
        if shift.isPublicHoliday { return .publicHoliday }
        if shift.isSleepover { return .sleepover }
        if shift.date.isWeekend { return .weekend }
        if PayEngine.hasEveningHours(shift.input, evening: evening) { return .evening }
        return .day
    }
}
