import SwiftUI

// MARK: - Liquid Glass building blocks (iOS 26)
//
// Rules (from Apple's HIG for Liquid Glass):
//  • Glass is for the navigation/control layer (tab bar, toolbars, floating buttons, pills, sheets),
//    never for content cards. Content uses plain grouped backgrounds.
//  • Group nearby glass elements in a `GlassEffectContainer` so they blend and morph together.
//  • Give morphing elements a `glassEffectID` in a shared namespace.
//  • The system handles Reduce Transparency / Increase Contrast for `.glassEffect`.

/// A floating, interactive glass button with an SF Symbol (e.g. the "Log shift" FAB).
struct GlassIconButton: View {
    let systemImage: String
    var tint: Color? = nil
    var size: CGFloat = 56
    var accessibilityLabel: String
    let action: () -> Void
    @State private var tapCount = 0

    var body: some View {
        Button {
            tapCount += 1
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .symbolEffect(.bounce, value: tapCount)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? .regular.interactive(), in: .circle)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A capsule glass pill showing a label + value, used for floating totals.
struct GlassPill<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular, in: .capsule)
    }
}

/// Segmented control where the selection is a glass capsule that morphs between segments
/// using `glassEffectID`, the Liquid Glass version of the web app's `.segmented-control`.
struct GlassSegmentedControl<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var ns

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(options) { option in
                    let isSelected = option == selection
                    Button {
                        withAnimation(.bouncy(duration: 0.35)) { selection = option }
                    } label: {
                        Text(title(option))
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.clear)
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .glassEffectID("selection", in: ns)
                        }
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Horizontal row of glass filter chips that merge when adjacent.
struct GlassChips<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var ns

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(options) { option in
                        let selected = option == selection
                        Button(title(option)) {
                            withAnimation(.snappy) { selection = option }
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(Theme.primary).interactive() : .regular.interactive(), in: .capsule)
                        .glassEffectID(String(describing: option.id), in: ns)
                    }
                }
                .padding(.horizontal)
            }
        }
        .scrollClipDisabled()
    }
}

extension View {
    /// Glass-backed floating action area pinned to the bottom of a scroll view.
    func floatingGlassAction<Accessory: View>(@ViewBuilder _ accessory: () -> Accessory) -> some View {
        safeAreaInset(edge: .bottom, alignment: .trailing) {
            accessory()
                .padding(.trailing, 20)
                .padding(.bottom, 8)
        }
    }
}
