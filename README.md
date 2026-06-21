# ✈️ Flight Deals — Iceland → Japan

A small native iOS app (SwiftUI) that hunts cheap round-trip flights from
Iceland to Japan across a **flexible range of months**, scans **automatically
once a day** in the background, and sends you a **notification when it finds a
genuinely good deal** — not a trap.

## What it does

- **Flexible dates** — pick an *earliest month* and a *latest month*, plus a
  trip-length band (e.g. 10–18 nights). The app samples many departure dates
  across that whole window and several trip lengths.
- **Daily auto-scan** — uses iOS `BGTaskScheduler` to wake up ~once a day and
  re-scan. If it finds a good deal you get a push notification.
- **Trap detection** 🪤 — a cheap price means nothing if the journey is awful.
  Deals are flagged and *excluded from notifications* if they have:
  - a painfully long layover (default > 6h),
  - a marathon total travel time (default > 30h — bye-bye 52-hour "deals"),
  - too many stops,
  - **unconnected / mixed airlines** (self-transfer risk — you re-check bags,
    a missed connection is *your* problem),
  - an overnight airport sleepover.
  - All thresholds are adjustable in **Settings**.
- **Manual scan** — tap the refresh button any time.

## Screens

- **Deals** tab: good deals up top, trap deals shown separately (so you can see
  *why* they were skipped). Tap any deal for a full breakdown + a Google Flights
  link to book.
- **Settings** tab: API key, route, flexible date window, price threshold, and
  all the trap-filter rules.

## 1. Get a free flight-data API key (Amadeus)

The app uses the **Amadeus Self-Service API** (free tier).

1. Go to <https://developers.amadeus.com> and create an account.
2. Create a **Self-Service app** to get a **Client ID** and **Client Secret**.
3. In the app → **Settings** → paste both keys.
4. Leave *"Use production prices"* **off** while testing (the test environment
   has limited/cached data). Turn it **on** for real live fares — production
   keys are still free up to a monthly quota.

> Want a different provider (Kiwi/Tequila, Travelpayouts, etc.)? Swap the
> implementation in `AmadeusClient.swift` — the rest of the app talks to it
> through `FlightSearchService` and doesn't care where the data comes from.

## 2. Build & sideload onto your iPhone

You need a Mac with **Xcode**.

### Option A — straight from Xcode (simplest, free Apple ID)
1. `open FlightDeals.xcodeproj`
2. Select the **FlightDeals** target → **Signing & Capabilities**:
   - Check **Automatically manage signing**.
   - Pick your **Team** (a free personal Apple ID works).
   - Change the **Bundle Identifier** to something unique, e.g.
     `com.yourname.flightdeals`.
3. Plug in your iPhone, select it as the run destination, press **▶ Run**.
4. On the phone: **Settings → General → VPN & Device Management** → trust your
   developer certificate.

> Free Apple IDs: the app signature expires after **7 days** — just re-run from
> Xcode to refresh it. A paid Apple Developer account ($99/yr) lasts a year.

### Option B — AltStore / Sideloadly (no keeping a Mac plugged in)
1. In Xcode: **Product → Archive**, then export an **.ipa**
   (Distribution → *Ad Hoc* or *Development*), **or** build with the
   command below and zip the `.app` into an `.ipa`.
2. Install **[AltStore](https://altstore.io)** or
   **[Sideloadly](https://sideloadly.io)** and use it to install the `.ipa`
   with your Apple ID. AltStore can auto-refresh the 7-day signature for you.

### Command-line build (optional)
```bash
xcodebuild -project FlightDeals.xcodeproj -scheme FlightDeals \
  -configuration Release -sdk iphoneos \
  -allowProvisioningUpdates build
```

## 3. Turn on background scanning

- Allow **Notifications** when prompted (first launch).
- Keep **Background App Refresh** enabled for the app
  (Settings → General → Background App Refresh).
- iOS decides exactly *when* the daily task runs (usually when charging / on
  Wi-Fi). To test it immediately, use the **"Run scan now"** button, or trigger
  the background task from Xcode's debugger console:
  ```
  e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.flightdeals.dailyScan"]
  ```

## Project layout

```
FlightDeals/
  FlightDealsApp.swift        App entry, registers background task
  Models.swift                SearchConfig, FlightDeal, TrapReason
  AmadeusClient.swift         OAuth + Flight Offers Search networking
  FlightSearchService.swift   Flexible-date scan + trap detection (the brain)
  NotificationManager.swift   Local notifications
  AppStore.swift              Observable state + persistence (UserDefaults)
  BackgroundScheduler.swift   BGTaskScheduler daily refresh
  ContentView.swift           Deals list + detail UI
  SettingsView.swift          All the knobs
  Info.plist                  Background modes + task identifiers
```

## Notes / limits

- Test-mode Amadeus data is limited; if you see few or no results, add your
  **production** keys and toggle production on.
- The "self-transfer" check is a heuristic (more than one distinct carrier on a
  connecting leg). Real codeshares may occasionally trip it — loosen it in
  Settings if needed.
- This is a personal sideload project, not an App Store release.
