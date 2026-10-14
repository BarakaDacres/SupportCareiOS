import SwiftUI
import SupportCareCore

/// Three-step first run:
///  1. Your business (name, ABN, state for public holidays)
///  2. Your rates (weekday, Saturday, Sunday, evening, sleepover, public holiday)
///  3. Payments and reminders (bank details, notifications, optional first client)
@MainActor
@Observable
final class OnboardingViewModel {
    var step = 0
    var settings: UserSettings
    var displayName = ""
    var firstClientName = ""
    var enableReminders = true
    var isSaving = false

    init(settings: UserSettings, displayName: String?) {
        self.settings = settings
        self.displayName = displayName ?? ""
        if self.settings.holidayState == nil { self.settings.holidayState = AUState.nsw.rawValue }
    }

    var canContinue: Bool {
        switch step {
        case 0: !(settings.businessName ?? "").trimmingCharacters(in: .whitespaces).isEmpty || !displayName.isEmpty
        case 1: settings.rateWeekday > 0
        default: true
        }
    }

    func finish(store: DataStore) async {
        isSaving = true
        defer { isSaving = false }
        settings.onboardingCompleted = true
        settings.shiftReminders = enableReminders
        settings.invoiceReminders = enableReminders
        let final = settings
        await store.updateSettings { $0 = final }
        if !displayName.isEmpty { await store.saveProfile(displayName: displayName) }
        let name = firstClientName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { await store.save(client: Client(userId: store.userId, name: name)) }
        if enableReminders { _ = await NotificationScheduler.shared.requestAuthorization() }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    let store: DataStore
    @State private var vm: OnboardingViewModel
    @Namespace private var dots

    init(store: DataStore) {
        self.store = store
        _vm = State(initialValue: OnboardingViewModel(settings: store.resolvedSettings, displayName: store.profile?.displayName))
    }

    private let steps: [(title: String, subtitle: String, symbol: String)] = [
        ("Your business", "This appears on your invoices.", "briefcase.fill"),
        ("Your rates", "Shifts are priced automatically from these. You can override them per client.", "dollarsign.circle.fill"),
        ("Get paid", "Bank details for invoices, and reminders so nothing slips.", "banknote.fill"),
    ]

    var body: some View {
        @Bindable var vm = vm
        NavigationStack {
            VStack(spacing: 0) {
                header
                TabView(selection: $vm.step) {
                    businessStep.tag(0)
                    ratesStep.tag(1)
                    paymentStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(Motion.smooth, value: vm.step)
            }
            .safeAreaInset(edge: .bottom) { controls }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { Task { await vm.finish(store: store); app.completeOnboarding() } }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var header: some View {
        let s = steps[vm.step]
        return VStack(spacing: 10) {
            Image(systemName: s.symbol)
                .font(.system(size: 44))
                .foregroundStyle(Theme.primary)
                .symbolEffect(.bounce, value: vm.step)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 84, height: 84)
                .glassEffect(.regular.tint(Theme.primary.opacity(0.2)), in: .circle)
            Text(s.title).font(.title.bold()).contentTransition(.opacity)
            Text(s.subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            // Step dots: the active one stretches into a capsule (matchedGeometryEffect).
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    ZStack {
                        Capsule().fill(.quaternary).frame(width: 8, height: 8)
                        if i == vm.step {
                            Capsule().fill(Theme.primary).frame(width: 24, height: 8)
                                .matchedGeometryEffect(id: "dot", in: dots)
                        }
                    }
                    .frame(width: i == vm.step ? 24 : 8, height: 8)
                }
            }
            .animation(Motion.bouncy, value: vm.step)
            .padding(.top, 6)
            .accessibilityLabel("Step \(vm.step + 1) of 3")
        }
        .padding(.vertical, 12)
    }

    private var businessStep: some View {
        @Bindable var vm = vm
        return Form {
            Section("You") {
                TextField("Your name", text: $vm.displayName).textContentType(.name)
                TextField("Business name", text: $vm.settings.businessName.orEmpty).textContentType(.organizationName)
                TextField("ABN", text: $vm.settings.abn.orEmpty).keyboardType(.numberPad)
            }
            Section {
                Picker("State or territory", selection: Binding(
                    get: { vm.settings.resolvedHolidayState },
                    set: { vm.settings.holidayState = $0.rawValue })) {
                    ForEach(AUState.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Auto-detect public holidays", isOn: Binding(
                    get: { vm.settings.resolvedHolidayAutoDetect },
                    set: { vm.settings.holidayAutoDetect = $0 }))
            } footer: {
                Text("Shifts on a public holiday in your state are flagged automatically. You can still switch the flag off for any shift.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var ratesStep: some View {
        @Bindable var vm = vm
        return Form {
            Section {
                CurrencyField(title: "Weekday (Mon–Fri)", value: $vm.settings.rateWeekday)
                CurrencyField(title: "Weekday evening", value: $vm.settings.rateEvening)
                CurrencyField(title: "Saturday", value: $vm.settings.rateSaturday)
                CurrencyField(title: "Sunday", value: $vm.settings.rateSunday)
                CurrencyField(title: "Public holiday", value: $vm.settings.ratePublicHoliday)
            } header: { Text("Hourly") } footer: {
                Text("Evening rate applies Mon–Fri from \(vm.settings.eveningWindow.start.twelveHour) to \(vm.settings.eveningWindow.end.minutes >= 1440 ? "midnight" : vm.settings.eveningWindow.end.twelveHour). You can change this window in Settings.")
            }
            Section("Sleepover (flat per night)") {
                CurrencyField(title: "Weeknight", value: $vm.settings.rateSleepoverWeekday)
                CurrencyField(title: "Weekend", value: $vm.settings.rateSleepoverWeekend)
                CurrencyField(title: "Public holiday", value: $vm.settings.rateSleepoverPublicHoliday)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var paymentStep: some View {
        @Bindable var vm = vm
        return Form {
            Section("Bank details") {
                TextField("Account name", text: $vm.settings.accountName.orEmpty)
                TextField("BSB", text: $vm.settings.bsb.orEmpty).keyboardType(.numberPad)
                TextField("Account number", text: $vm.settings.accountNumber.orEmpty).keyboardType(.numberPad)
            }
            Section {
                Stepper("Invoices due in \(vm.settings.invoiceDueDays) days", value: $vm.settings.invoiceDueDays, in: 0...60)
                Toggle("Shift & overdue invoice reminders", isOn: $vm.enableReminders)
            }
            Section {
                TextField("First client's name (optional)", text: $vm.firstClientName)
            } footer: { Text("You can add more clients and their NDIS details later.") }
        }
        .scrollContentBackground(.hidden)
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if vm.step > 0 {
                    Button {
                        withAnimation(Motion.smooth) { vm.step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left").frame(width: 50, height: 50)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Back")
                }
                Button {
                    if vm.step < 2 {
                        withAnimation(Motion.smooth) { vm.step += 1 }
                    } else {
                        Task { await vm.finish(store: store); app.completeOnboarding() }
                    }
                } label: {
                    Group {
                        if vm.isSaving { ProgressView() } else { Text(vm.step < 2 ? "Continue" : "Get started") }
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .disabled(!vm.canContinue || vm.isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .animation(Motion.bouncy, value: vm.step)
        }
    }
}

extension Binding where Value == String? {
    /// Binds an optional String to a TextField, storing empty strings as nil.
    var orEmpty: Binding<String> {
        Binding<String>(get: { wrappedValue ?? "" }, set: { wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
