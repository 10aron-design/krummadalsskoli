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

## 1. Get a free flight-data API key (Skyscanner via RapidAPI)

The app reads **Skyscanner** flight data through the **"Sky-Scrapper"** API on
RapidAPI (free tier — no OAuth, no partner approval).

1. Make a free account at <https://rapidapi.com>.
2. Open the **[Sky-Scrapper](https://rapidapi.com/apiheya/api/sky-scrapper)**
   API page and click **Subscribe to Test** → pick the **Basic (free)** plan.
3. On any endpoint page, copy your **`X-RapidAPI-Key`** (the long string in the
   code snippet / your RapidAPI dashboard).
4. In the app → **Settings → Skyscanner API key** → paste the key. Leave the
   host as `sky-scrapper.p.rapidapi.com`.

> The app resolves your airport codes (KEF, TYO, OSA…) to Skyscanner IDs
> automatically, then searches round-trips across your flexible date window.
>
> Want a different provider? Write another `FlightProvider` conformer (see
> `SkyscannerClient.swift`) — the search + trap logic doesn't care where data
> comes from.

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

### Option W — Windows + Sideloadly (no Mac at all) ⭐ for you

Sideloadly signs & installs an `.ipa`, but it can't *build* Swift code — that
needs a Mac. So let a **cloud Mac on GitHub Actions** build the `.ipa` for you:

1. **Get the IPA from the cloud build**
   - The workflow builds it automatically on every push (or run it manually:
     repo → **Actions** → **"Build unsigned IPA"** → **Run workflow**).
   - **Easiest:** repo → **Releases** → **"Latest sideload IPA"** → download the
     **`FlightDeals.ipa`** asset. This is a *plain* `.ipa` — drag it straight
     into Sideloadly, **no unzip needed**.
   - Alternative: run → **Artifacts** → **`FlightDeals-ipa`**. ⚠️ This downloads
     as a **`.zip`** — you MUST extract it first and use the inner
     `FlightDeals.ipa`. Feeding the zip itself to Sideloadly causes the
     *"Can't listdir a file"* error.

2. **Install Sideloadly on Windows** from <https://sideloadly.io>
   (also install **iTunes** + **iCloud** from Apple's site, not the Microsoft
   Store versions — Sideloadly needs them for device drivers).

3. **Sideload it**
   - Plug in your iPhone, open Sideloadly.
   - Drag **`FlightDeals.ipa`** into Sideloadly.
   - Enter your **Apple ID** (a free one works). Sideloadly signs it for you.
   - Click **Start**. Approve the 2FA / "allow" prompts.

4. **Trust the app on the phone**
   - iPhone → **Settings → General → VPN & Device Management** → tap your
     Apple ID → **Trust**.

5. **Open the app**, paste your RapidAPI (Skyscanner) key in Settings, tap Scan.

> ⏳ Free Apple ID limits: the app signature expires after **7 days** and you
> can have max 3 sideloaded apps. To refresh, just re-run Sideloadly with the
> same `.ipa` before it expires (or rebuild a fresh `.ipa` from Actions).
> A paid Apple Developer account ($99/yr) lasts a year per signing.
>
> 🔔 Background daily scans + notifications work the same on a sideloaded
> build — just keep Background App Refresh and Notifications enabled.

### Option B — AltStore / Sideloadly with your own Mac-built IPA
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
  SkyscannerClient.swift      Skyscanner (RapidAPI) search + JSON mapping
  FlightSearchService.swift   Flexible-date scan + trap detection (the brain)
  NotificationManager.swift   Local notifications
  AppStore.swift              Observable state + persistence (UserDefaults)
  BackgroundScheduler.swift   BGTaskScheduler daily refresh
  ContentView.swift           Deals list + detail UI
  SettingsView.swift          All the knobs
  Info.plist                  Background modes + task identifiers
```

## Notes / limits

- The free RapidAPI tier has a small monthly request cap, and **failed requests
  still count against it**. Use **Settings → "Test API (1 call)"** to confirm
  your key/route works before running a full scan.
- Each scan is capped by **"Max API calls per scan"** (default 12) and samples
  dates evenly to fit that budget, so one scan can't drain your whole month.
  Lower it (e.g. 5) to stretch the free tier further.
- True daily background scanning needs more quota than the free tier provides —
  expect to use a paid RapidAPI plan for hands-off daily runs.
- The "self-transfer" check is a heuristic (more than one distinct carrier on a
  connecting leg). Real codeshares may occasionally trip it — loosen it in
  Settings if needed.
- This is a personal sideload project, not an App Store release.
