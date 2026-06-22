# The Private Ledger — iOS app

The single-file economics academy (`economics-academy.html`) wrapped as a native
iOS app with [Capacitor](https://capacitorjs.com). Same UI, its own logo, and
mobile/notch support. The web UI is untouched in look — only iOS shell behaviour
(safe-area insets, status bar, touch tuning) was added.

```
www/                     the app UI (mobile-tuned copy of the HTML) + apple-touch-icon
assets/                  logo sources (SVG) the icon/splash set is generated from
resources/make_logo.py   regenerates the "kr" seal logo
ios/                     the real native Xcode project (Capacitor)
scripts/build-ipa.sh     one command -> unsigned .ipa (run on macOS)
.github/workflows/       CI that builds the .ipa on a cloud Mac (no Mac needed)
capacitor.config.json    app id, name, splash/status-bar config
```

- **App id:** `com.privateledger.app`  **Name:** Private Ledger

## Why there's no `.ipa` committed here

A runnable iOS `.ipa` is a compiled **ARM64 Mach-O binary** produced by Apple's
toolchain (Xcode), which only runs on **macOS**. This project was assembled on
Windows, so the final compile happens in one of two ways below. Everything *up to*
that compile — native project, logo, icons, splash, mobile shell — is done.

## Get the `.ipa`

### Option A — cloud Mac, no Mac required (recommended)
1. Push this folder to a GitHub repo.
2. GitHub Actions runs `.github/workflows/build-ios.yml` on a `macos-14` runner.
3. Download the **`PrivateLedger-unsigned-ipa`** artifact from the run.

### Option B — on a Mac with Xcode
```bash
./scripts/build-ipa.sh        # -> dist/PrivateLedger-unsigned.ipa
```
Or open it in Xcode and press Run / Product ▸ Archive:
```bash
npx cap open ios
```

## Installing the unsigned `.ipa` on a device

The CI/script output is **unsigned** (no Apple account needed to build). To run it
on a real iPhone, re-sign with your own free Apple ID using any of:
- **Sideloadly** or **AltStore** (point it at the `.ipa`, sign with your Apple ID), or
- **Xcode** ▸ run the `App` scheme on your connected device (auto-signs), or
- a paid Apple Developer account for ad-hoc / App Store distribution.

On the iOS Simulator no signing is needed at all.

## Rebuild after editing the UI
```bash
# edit www/index.html, then:
npx cap copy ios
```

## Regenerate logo / icons
```bash
python resources/make_logo.py
npx capacitor-assets generate --ios --assetPath assets
```

## Notes
- Fonts load from Google Fonts (HTTPS) on first run; serif/mono fallbacks render
  offline. Progress is stored on-device via `localStorage` (persists between launches).
- Orientation: portrait + landscape. Min target: arm64 iPhone/iPad.
