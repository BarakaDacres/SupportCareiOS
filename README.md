# Support Care for iOS

A native SwiftUI rebuild of [Support Care](https://supportcare.lovable.app), the shift tracking and NDIS
invoicing app for independent support workers. It targets **iOS 26** and uses **Liquid Glass**. It shares the
Supabase backend with the web app, so the same account and data work on both.

| | |
|---|---|
| UI | SwiftUI, iOS 26: glass tab bar and toolbars, `glassEffect`, `GlassEffectContainer`, glass button styles, zoom transitions |
| Architecture | MVVM with `@Observable`, plus a `DataStore` backed by repository protocols |
| Backend | [supabase-swift](https://github.com/supabase/supabase-swift) 2.x (Auth, PostgREST, Storage) |
| Logic | `SupportCareKit`, a pure Swift package that is unit-tested against the web app's own TypeScript output |
| Project | Generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml` |

## Repository layout

```
project.yml                      XcodeGen spec (app, widget, unit + UI tests)
Config/
  Base.xcconfig                  committed defaults; includes Config.xcconfig
  Config.example.xcconfig        template → copy to Config.xcconfig (gitignored)
SupportCare/
  App/                           @main, AppModel (session state machine), DataStore, RootView, tabs
  DesignSystem/                  Theme tokens (from web index.css), Glass components, Motion, shared views
  Features/
    Auth/                        email / Apple / Google sign-in, new-password screen
    Onboarding/                  3-step first run
    Home/  Shifts/  Clients/  Invoices/  Analytics/  Settings/
  Services/                      notifications, widget snapshot, EventKit calendar
SupportCareWidget/               WidgetKit extension (this week's earnings + next shift)
SupportCareKit/                  Swift package
  Sources/SupportCareCore/       models, PayEngine, RateResolver, InvoiceGrouping, numbering,
                                 periods, public holidays, analytics, ZIP writer, ICS, invoice document
  Sources/SupportCareServices/   Supabase config/client, AuthService, repositories, in-memory demo repo
  Tests/SupportCareCoreTests/    Swift Testing; includes web-parity fixtures
SupportCareTests/ SupportCareUITests/
supabase/migrations/             new migration for the iOS app (see below)
scripts/                         holiday list + parity fixture generators
```

## Setup on a Mac

Requirements: macOS with **Xcode 26** or later, and [Homebrew](https://brew.sh).

```bash
brew install xcodegen
git clone <this repo> SupportCareiOS && cd SupportCareiOS
cp Config/Config.example.xcconfig Config/Config.xcconfig   # then edit it (see below)
xcodegen generate
open SupportCare.xcodeproj
```

In Xcode, open **SupportCare target → Signing & Capabilities** and pick your team for both the
**SupportCare** and **SupportCareWidget** targets. If `com.barakadacres.supportcare` is taken, change the
bundle IDs and the App Group (`APP_GROUP` in `project.yml`). Then run on a simulator or an iPhone.

> Without a `Config.xcconfig` the app still launches and offers **demo mode**, which uses sample data held in
> memory. That's useful for trying the UI.

Run `xcodegen generate` again whenever you add or remove files, or change `project.yml`.

### 1. Supabase URL and key

Open the Supabase dashboard and go to **Project Settings → API**. Copy the project URL and the **publishable /
anon** key into `Config/Config.xcconfig`:

```
SUPABASE_URL = https:/$()/mptemtxjhgshnfwvvnyg.supabase.co
SUPABASE_PUBLISHABLE_KEY = <publishable key>
```

`xcconfig` treats `//` as a comment, which is why the URL is written with `$()` between the slashes. The same
values are in the web repo's `.env` file (`VITE_SUPABASE_URL` / `VITE_SUPABASE_PUBLISHABLE_KEY`). **Never** use
the `service_role` key in the app.

### 2. Run the database migration

Run `supabase/migrations/20261014120000_sync_device_prefs.sql` once. Either paste it into the Supabase SQL
editor, or copy it into the web repo's `supabase/migrations/` and deploy it the way Lovable deploys
migrations. It adds these columns to `user_settings`:

`evening_start`, `evening_end`, `sleepover_start`, `sleepover_end`, `week_start_day`, `auto_timezone`,
`haptics`, `shift_reminders`, `invoice_reminders`, `holiday_auto_detect`, `holiday_state`, `onboarding_completed`

The web app currently keeps these in `localStorage`. The migration is additive and its defaults match what
the web app does today. Existing users are marked as onboarded. Until it's run, the iOS app still works, but
those preferences won't save. Consider updating the web app to read these columns too, so both stay in sync.

### 3. Auth redirect URLs

Open **Supabase → Authentication → URL Configuration → Redirect URLs** and add:

```
supportcare://auth-callback
supportcare://reset-password
```

The password-reset email then opens the app on the **new password** screen (PKCE code exchange through
`auth.session(from:)`), and sign-up confirmation emails return to the app. If you change the scheme, update
`AUTH_REDIRECT_SCHEME` in `Config.xcconfig`.

### 4. Sign in with Apple (native)

The app uses `ASAuthorizationAppleIDProvider` and sends the identity token plus the raw nonce to
`supabase.auth.signInWithIdToken(provider: .apple)`. There's no web redirect.

1. In the **Apple Developer portal → Identifiers**, open your App ID (`com.barakadacres.supportcare`) and
   enable **Sign in with Apple**. The entitlement is already in `SupportCare.entitlements`.
2. Open **Supabase → Authentication → Sign In / Providers → Apple** and enable it. Add your app's bundle ID
   (`com.barakadacres.supportcare`) to **Client IDs**. For native sign-in, the bundle ID is the only client ID
   you need. If the web app also uses Apple through OAuth, keep its Services ID listed as well, separated by
   a comma.
3. Apple only shares the user's name on the first sign-in. The app saves it to `full_name` in the user's
   metadata.

The web prototype signs in through Lovable's managed OAuth broker (`@lovable.dev/cloud-auth-js`). That
broker can't be used from a native app, so the providers must be enabled directly in Supabase as described
above. Because Supabase links identities by verified email, the same person ends up in the same account on
web and iOS.

### 5. Google Sign-In (native)

The app uses the GoogleSignIn-iOS SDK and then calls `signInWithIdToken(provider: .google, accessToken:)`.

1. In **Google Cloud Console → APIs & Services → Credentials**, create:
   * an **iOS** OAuth client ID with bundle ID `com.barakadacres.supportcare`
   * a **Web** OAuth client ID. You may already have one for Supabase.
2. Fill these into `Config.xcconfig`:
   ```
   GOOGLE_IOS_CLIENT_ID = <ios client id>.apps.googleusercontent.com
   GOOGLE_WEB_CLIENT_ID = <web client id>.apps.googleusercontent.com
   GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.<ios client id prefix>
   ```
3. Open **Supabase → Authentication → Providers → Google** and enable it. Set the Web client ID and secret,
   then add the **iOS client ID** to **Authorized Client IDs**, comma-separated after the web one. Turn on
   **Skip nonce check**, because the GoogleSignIn SDK doesn't let you set the nonce.

If `GOOGLE_IOS_CLIENT_ID` is empty, the Google button is hidden.

### 6. Widget and notifications

* The widget reads a small snapshot from the App Group `group.com.barakadacres.supportcare`. Register that
  group in the developer portal, or let Xcode create it when you select your team.
* Shift reminders fire 1 hour before each shift, covering the next 14 days. Overdue invoice alerts fire at
  9 am the day after the due date. Both are scheduled locally once the user allows notifications.

## Business logic (SupportCareKit)

Everything in `SupportCareCore` is plain Foundation, so it builds and tests on Linux and macOS:

```bash
swift test --package-path SupportCareKit
```

* **PayEngine**, a port of `shiftCalculator.ts`:
  * Shifts that end at or before their start time cross midnight.
  * Hours are split per calendar day, then by the evening window.
  * Precedence: overtime, then public holiday, then evening (Mon–Fri only), then the day's rate (Sun, Sat or weekday).
  * Sleepovers are flat fees: public holiday, then weekend (night starting Sat/Sun), then weekday. An overtime sleepover is paid as hours × overtime rate.
  * `fee_override` > 0 replaces the calculated gross.
* **Evening window.** The web app's comments say 18:00–22:00, but its code defaults to **18:00–24:00**.
  That's now an explicit setting (`user_settings.evening_start/evening_end`). It defaults to 18:00–24:00 so
  nobody's pay changes. Changing it re-prices the stored shifts.
* **RateResolver** checks each rate in turn: client custom rate (when `use_custom_rates` is on), then the
  user's settings, then the defaults.
* **InvoiceGrouping** puts lines into 11 NDIS categories, each with a support item code (`01_011_0107_1_1`,
  etc.). Fee-override deltas are attributed to the category with the most hours. **Fix:** the web app drops
  overtime lines from invoices because they're missing from its ORDER list. iOS includes them.
* **InvoiceNumbering** produces `INV-NNN` using the lowest free number. `invoice_counter` is kept as a
  high-water mark. The due date is the issue date plus `invoice_due_days`. No GST is added, because NDIS
  supports are GST-free.
* **Periods** covers weeks with a configurable start day, fortnights anchored on the Monday on or before
  1 Jan and labelled `FN01 · …`, months, and the Australian financial year.
* **Public holidays** are optional and come from a bundled list of national and state holidays keyed by
  `AUState`, covering 2025–2030 (`Resources/au_public_holidays.json`). When auto-detect is on, new shifts on a
  holiday get the PH flag. The manual toggle always wins. Regenerate the list or extend the years with
  `python3 scripts/generate_holidays.py 2025 2035`. It's built from `python-holidays`, so check part-day and
  regional holidays such as Melbourne Cup and the Christmas Eve / NYE evenings.
* **Export:** each invoice is a vector PDF (`UIGraphicsPDFRenderer`). Selecting several invoices downloads
  them as a ZIP with one PDF each (a small built-in ZIP writer), so each record can still be shared on its
  own. Shifts can be exported as `.ics` or added through EventKit.

### Parity fixtures

`Tests/SupportCareCoreTests/web_fixtures.json` comes from running the web app's own `shiftCalculator.ts`
and `invoiceGrouping.ts` under Node. The Swift tests check that the results match exactly: gross, hours,
breakdown labels and amounts, invoice categories, quantities and subtotals. They cover the default and
custom rates and the 18–22 evening window. Regenerate the fixtures after changing web logic:

```bash
scripts/generate_parity_fixtures.sh /path/to/supportcare   # the web repo
```

## Design notes

* **Liquid Glass sits on the control layer only.** That means the system tab bar (minimises on scroll, with a
  "this week / Log shift" bottom accessory), toolbars (grouped with `ToolbarSpacer`), floating buttons and
  pills, segmented controls whose selection morphs with `glassEffectID`, and filter chips inside a
  `GlassEffectContainer`. Content cards use solid grouped backgrounds.
* **Motion:**
  * zoom navigation transitions from shift, client and invoice rows (`matchedTransitionSource`)
  * `matchedGeometryEffect` on the onboarding step dots
  * spring animations throughout (`Motion.swift`)
  * `contentTransition(.numericText)` on money
  * SF Symbol effects (`bounce`, `breathe`, `pulse`, `replace`)
  * `scrollTransition` on list rows
  * `sensoryFeedback` haptics, which respect the user's haptics setting
* **Theme:** colours come from the web app's `index.css` (iOS blue primary, money green, evening orange,
  sleepover indigo, weekend violet). Neutrals are system colours, so light and dark mode adapt. Appearance
  can be set to System, Light or Dark.

## Status

Implemented: everything in phases 0–8 (see the commit history). Not yet done:

* Realtime sync between devices. Data refreshes on launch and on pull-to-refresh.
* Offline write queue. Writes are optimistic and rolled back on failure.
* Editable NDIS item codes per user. The defaults are used.
* Weekly receipt-style document. Standard invoices are supported.
* iPad-specific layouts. The app runs on iPad with the iPhone layout scaled up.
* An app icon. The current one is a placeholder.
