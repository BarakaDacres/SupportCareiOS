import PhotosUI
import SwiftUI
import UIKit
import SupportCareCore

/// Profile tab with the web app's four sub-tabs (Prefs · Rates · Analytics · Account),
/// switched with a morphing glass segmented control.
struct ProfileView: View {
    enum ProfileSection: String, CaseIterable, Identifiable {
        case preferences, rates, analytics, account
        var id: String { rawValue }
        var title: String {
            switch self {
            case .preferences: "Prefs"
            case .rates: "Rates"
            case .analytics: "Analytics"
            case .account: "Account"
            }
        }
    }

    @State private var section: ProfileSection = .preferences

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ProfileHeader()
                    GlassSegmentedControl(options: ProfileSection.allCases, selection: $section, title: \.title)
                    Group {
                        switch section {
                        case .preferences: PreferencesView()
                        case .rates: RatesView()
                        case .analytics: AnalyticsView()
                        case .account: AccountView()
                        }
                    }
                    .transition(.blurReplace)
                }
                .padding()
                .animation(Motion.smooth, value: section)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ProfileHeader: View {
    @Environment(DataStore.self) private var store
    @Environment(AppModel.self) private var app
    @State private var photo: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $photo, matching: .images) {
                AsyncImage(url: store.profile?.avatarUrl.flatMap(URL.init(string:))) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                }
                .frame(width: 64, height: 64)
                .clipShape(.circle)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill").font(.caption2).padding(5).glassEffect(.regular, in: .circle)
                }
            }
            .onChange(of: photo) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let jpeg = image.preparingThumbnail(of: CGSize(width: 512, height: 512))?.jpegData(compressionQuality: 0.85)
                    else { return }
                    await store.uploadAvatar(jpeg)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store.profile?.displayName ?? store.resolvedSettings.businessName ?? "Support worker").font(.headline)
                Text(app.email ?? "").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @Environment(DataStore.self) private var store
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @State private var permissionDenied = false

    var body: some View {
        let s = store.resolvedSettings
        VStack(spacing: 16) {
            Card {
                SectionHeader(title: "Appearance", systemImage: "circle.lefthalf.filled")
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Card {
                SectionHeader(title: "Pay windows", systemImage: "clock.badge")
                TimeSettingRow(title: "Evening starts", value: s.eveningWindow.start) { t in
                    await store.updateSettings { $0.eveningStart = t }; await store.repriceAllShifts()
                }
                TimeSettingRow(title: "Evening ends", value: s.eveningWindow.endMinutes >= 1440 ? TimeOfDay(minutes: 0) : s.eveningWindow.end) { t in
                    await store.updateSettings { $0.eveningEnd = t }; await store.repriceAllShifts()
                }
                Text("Mon–Fri hours inside this window get the evening rate. 12:00 AM as the end means midnight. The default, 6 PM to midnight, matches the web app.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                TimeSettingRow(title: "Sleepover default start", value: s.resolvedSleepoverStart) { t in await store.updateSettings { $0.sleepoverStart = t } }
                TimeSettingRow(title: "Sleepover default end", value: s.resolvedSleepoverEnd) { t in await store.updateSettings { $0.sleepoverEnd = t } }
            }

            Card {
                SectionHeader(title: "Public holidays", systemImage: "flag.fill")
                Toggle("Auto-detect", isOn: binding(\.resolvedHolidayAutoDetect) { $0.holidayAutoDetect = $1 })
                Picker("State", selection: Binding(get: { s.resolvedHolidayState },
                                                    set: { v in Task { await store.updateSettings { $0.holidayState = v.rawValue } } })) {
                    ForEach(AUState.allCases) { Text($0.rawValue).tag($0) }
                }
                if s.resolvedHolidayAutoDetect {
                    let upcoming = store.holidays.holidays(in: DateRange(start: store.today, end: store.today.adding(days: 120), label: ""),
                                                           state: s.resolvedHolidayState)
                    ForEach(upcoming.prefix(3), id: \.date) { h in
                        LabeledContent(h.name) { Text(h.date.date(), format: .dateTime.day().month()) }.font(.footnote)
                    }
                }
                Text("New shifts on a public holiday in your state get the PH flag. You can still turn it off for any shift.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Card {
                SectionHeader(title: "Calendar & reminders", systemImage: "bell.badge")
                Picker("Week starts on", selection: Binding(get: { s.resolvedWeekStartDay },
                                                           set: { v in Task { await store.updateSettings { $0.weekStartDay = v } } })) {
                    Text("Monday").tag(1); Text("Sunday").tag(0); Text("Saturday").tag(6)
                }
                Toggle("Shift reminders", isOn: reminderBinding(\.resolvedShiftReminders) { $0.shiftReminders = $1 })
                Toggle("Overdue invoice alerts", isOn: reminderBinding(\.resolvedInvoiceReminders) { $0.invoiceReminders = $1 })
                Toggle("Haptics", isOn: binding(\.resolvedHaptics) { $0.haptics = $1 })
                if permissionDenied {
                    Text("Notifications are off for Support Care. Turn them on in Settings.").font(.caption).foregroundStyle(Theme.red)
                }
            }

            Card {
                SectionHeader(title: "Tax & goals", systemImage: "target")
                Toggle("Show tax estimate", isOn: binding(\.showTaxEstimate) { $0.showTaxEstimate = $1 })
                if s.showTaxEstimate {
                    Stepper("Tax rate \(s.taxRate.formatted())%", value: Binding(get: { s.taxRate },
                                                                               set: { v in Task { await store.updateSettings { $0.taxRate = v } } }),
                            in: 0...60, step: 1)
                }
                GoalField(title: "Weekly goal", value: s.weeklyGoal) { v in await store.updateSettings { $0.weeklyGoal = v } }
                GoalField(title: "Monthly goal", value: s.monthlyGoal) { v in await store.updateSettings { $0.monthlyGoal = v } }
                GoalField(title: "Yearly goal", value: s.yearlyGoal) { v in await store.updateSettings { $0.yearlyGoal = v } }
            }
        }
    }

    private func binding(_ get: KeyPath<UserSettings, Bool>, _ set: @escaping (inout UserSettings, Bool) -> Void) -> Binding<Bool> {
        Binding(get: { store.resolvedSettings[keyPath: get] },
                set: { v in Task { await store.updateSettings { set(&$0, v) } } })
    }

    private func reminderBinding(_ get: KeyPath<UserSettings, Bool>, _ set: @escaping (inout UserSettings, Bool) -> Void) -> Binding<Bool> {
        Binding(get: { store.resolvedSettings[keyPath: get] },
                set: { v in
                    Task {
                        if v { permissionDenied = !(await NotificationScheduler.shared.requestAuthorization()) }
                        await store.updateSettings { set(&$0, v) }
                    }
                })
    }
}

private struct TimeSettingRow: View {
    let title: String
    let value: TimeOfDay
    let onChange: (TimeOfDay) async -> Void
    @State private var date = Date()

    var body: some View {
        DatePicker(title, selection: $date, displayedComponents: .hourAndMinute)
            .onAppear { date = ShiftEditorViewModel.time(value) }
            .onChange(of: date) { _, d in
                let t = ShiftEditorViewModel.tod(d)
                if t != value { Task { await onChange(t) } }
            }
    }
}

private struct GoalField: View {
    let title: String
    let value: Double?
    let onCommit: (Double?) async -> Void
    @State private var draft: Double?

    var body: some View {
        OptionalCurrencyField(title: title, value: $draft, placeholder: "None")
            .onAppear { draft = value }
            .onSubmit { Task { await onCommit(draft) } }
            .onChange(of: draft) { _, v in
                guard v != value else { return }
                Task { try? await Task.sleep(for: .milliseconds(600)); if draft == v { await onCommit(v) } }
            }
    }
}

// MARK: - Rates

struct RatesView: View {
    @Environment(DataStore.self) private var store
    @State private var draft: PayRates = .defaults
    @State private var loaded = false
    @State private var saved = 0

    var body: some View {
        VStack(spacing: 16) {
            Card {
                SectionHeader(title: "Hourly", systemImage: "clock")
                CurrencyField(title: "Weekday (Mon–Fri)", value: $draft.weekday)
                CurrencyField(title: "Weekday evening", value: $draft.evening)
                CurrencyField(title: "Saturday", value: $draft.saturday)
                CurrencyField(title: "Sunday", value: $draft.sunday)
                CurrencyField(title: "Public holiday", value: $draft.publicHoliday)
                CurrencyField(title: "Overtime", value: $draft.overtime)
            }
            Card {
                SectionHeader(title: "Sleepover (flat per night)", systemImage: "moon.stars")
                CurrencyField(title: "Weeknight", value: $draft.sleepoverWeekday)
                CurrencyField(title: "Weekend (Sat/Sun)", value: $draft.sleepoverWeekend)
                CurrencyField(title: "Public holiday", value: $draft.sleepoverPublicHoliday)
            }
            Card {
                SectionHeader(title: "Example: 9 AM – 5 PM weekday", systemImage: "function")
                let calc = PayEngine.calculate(ShiftInput(date: Periods.weekStart(containing: store.today).adding(days: 2),
                                                          start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 17)),
                                               rates: draft, evening: store.evening)
                MoneyText(value: calc.grossPay, font: .title2.bold())
            }
            Button {
                Task {
                    await store.updateSettings { $0.rates = draft }
                    await store.repriceAllShifts()
                    saved += 1
                }
            } label: {
                Label("Save rates", systemImage: "checkmark.circle.fill")
                    .symbolEffect(.bounce, value: saved)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(draft == store.resolvedSettings.rates)
            Text("Saving re-prices every shift with the new rates. Clients with custom rates keep their overrides.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { if !loaded { draft = store.resolvedSettings.rates; loaded = true } }
        .sensoryFeedback(.success, trigger: saved)
    }
}

// MARK: - Account

struct AccountView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppModel.self) private var app
    @State private var draft = UserSettings(userId: UUID())
    @State private var displayName = ""
    @State private var loaded = false
    @State private var saved = 0
    @State private var confirmSignOut = false

    var body: some View {
        VStack(spacing: 16) {
            Card {
                SectionHeader(title: "Business", systemImage: "briefcase")
                TextField("Your name", text: $displayName)
                TextField("Business name", text: $draft.businessName.orEmpty)
                TextField("ABN", text: $draft.abn.orEmpty).keyboardType(.numberPad)
                TextField("Address", text: $draft.address.orEmpty, axis: .vertical)
                TextField("Email", text: $draft.email.orEmpty).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("Phone", text: $draft.phone.orEmpty).keyboardType(.phonePad)
            }
            Card {
                SectionHeader(title: "Bank", systemImage: "building.columns")
                TextField("Bank name", text: $draft.bankName.orEmpty)
                TextField("Account name", text: $draft.accountName.orEmpty)
                TextField("BSB", text: $draft.bsb.orEmpty).keyboardType(.numberPad)
                TextField("Account number", text: $draft.accountNumber.orEmpty).keyboardType(.numberPad)
            }
            Card {
                SectionHeader(title: "Invoices", systemImage: "doc.text")
                Stepper("Due in \(draft.invoiceDueDays) days", value: $draft.invoiceDueDays, in: 0...90)
                Toggle("Use default notes", isOn: $draft.useDefaultInvoiceNotes)
                TextField("Default invoice notes", text: $draft.invoiceNotes.orEmpty, axis: .vertical).lineLimit(2...6)
            }
            Button {
                Task {
                    let d = draft
                    await store.updateSettings { s in
                        s.businessName = d.businessName; s.abn = d.abn; s.address = d.address; s.email = d.email; s.phone = d.phone
                        s.bankName = d.bankName; s.accountName = d.accountName; s.bsb = d.bsb; s.accountNumber = d.accountNumber
                        s.invoiceDueDays = d.invoiceDueDays; s.useDefaultInvoiceNotes = d.useDefaultInvoiceNotes; s.invoiceNotes = d.invoiceNotes
                    }
                    await store.saveProfile(displayName: displayName.isEmpty ? nil : displayName)
                    saved += 1
                }
            } label: {
                Label("Save", systemImage: "checkmark.circle.fill").symbolEffect(.bounce, value: saved)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)

            Button("Sign out", role: .destructive) { confirmSignOut = true }
                .buttonStyle(.glass)
                .confirmationDialog("Sign out of Support Care?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                    Button("Sign out", role: .destructive) { Task { await app.signOut() } }
                }
            Text("Support Care \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .onAppear {
            guard !loaded else { return }
            draft = store.resolvedSettings
            displayName = store.profile?.displayName ?? ""
            loaded = true
        }
        .sensoryFeedback(.success, trigger: saved)
    }
}
