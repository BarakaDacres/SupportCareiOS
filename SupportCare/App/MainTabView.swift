import SwiftUI
import SupportCareCore

enum AppTab: Hashable {
    case home, shifts, clients, invoices, profile
}

/// Five tabs matching the web BottomTabBar (Home, Shifts, Clients, Invoices, Profile).
/// On iOS 26 the system `TabView` renders a Liquid Glass tab bar that shrinks on scroll.
struct MainTabView: View {
    @Environment(DataStore.self) private var store
    @State private var selection: AppTab = .home
    @State private var showingNewShift = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView(selection: $selection)
            }
            Tab("Shifts", systemImage: "calendar.badge.clock", value: AppTab.shifts) {
                ShiftsView()
            }
            Tab("Clients", systemImage: "person.2.fill", value: AppTab.clients) {
                ClientsView()
            }
            Tab("Invoices", systemImage: "doc.text.fill", value: AppTab.invoices) {
                InvoicesView()
            }
            .badge(store.overdueInvoiceCount)
            Tab("Profile", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            // Glass accessory above the tab bar: this week's earnings + quick "Log shift".
            WeekAccessory(onLog: { showingNewShift = true })
        }
        .sheet(isPresented: $showingNewShift) {
            ShiftEditorView(mode: .create(date: .today()))
        }
    }
}

private struct WeekAccessory: View {
    @Environment(DataStore.self) private var store
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(Theme.money)
            if placement != .inline {
                Text("This week").font(.footnote).foregroundStyle(.secondary)
            }
            MoneyText(value: store.weekSummary.gross, font: .subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Button("Log shift", systemImage: "plus", action: onLog)
                .labelStyle(.iconOnly)
                .font(.headline)
                .accessibilityLabel("Log shift")
        }
        .padding(.horizontal, 16)
    }
}
