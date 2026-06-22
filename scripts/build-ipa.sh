#!/usr/bin/env bash
# Build a real, runnable UNSIGNED .ipa locally on macOS (needs Xcode).
#   ./scripts/build-ipa.sh
# Output: dist/PrivateLedger-unsigned.ipa
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Installing JS deps"
npm install --no-audit --no-fund

echo "==> Syncing Capacitor"
npx cap sync ios

ARCH="$(mktemp -d)/App.xcarchive"
echo "==> Archiving (unsigned) -> $ARCH"
xcodebuild \
  -project ios/App/App.xcodeproj \
  -scheme App \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCH" \
  -skipPackagePluginValidation \
  clean archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""

APP="$ARCH/Products/Applications/App.app"
[ -d "$APP" ] || { echo "build failed: $APP missing"; exit 1; }

WORK="$(mktemp -d)"
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
mkdir -p dist
( cd "$WORK" && zip -qry "$OLDPWD/dist/PrivateLedger-unsigned.ipa" Payload )
echo "==> Done: dist/PrivateLedger-unsigned.ipa"
ls -lh dist/PrivateLedger-unsigned.ipa
