#!/usr/bin/env bash
# Keeps Tether signed on a free Apple account without plugging in.
# Run by the LaunchAgent in Tools/com.shorielol.tether.reinstall.plist every 6 hours. It does nothing
# until the installed build is within RENEW_DAYS of expiring. Then it drops Xcode's cached Tether
# profile (so Xcode issues a fresh 7-day one), builds Release and installs over Wi-Fi or cable.
# Reinstalling keeps the app's data. If the phone isn't reachable it exits and the next run retries.
#
# Usage: Tools/auto-reinstall.sh [--force]
set -uo pipefail
cd "$(dirname "$0")/.."

DEVICE="YOUR-IPHONE-ID"
BUNDLE_ID="com.shorielol.tether"
RENEW_DAYS=3
BUILD_DIR="build/dd-auto"
APP="$BUILD_DIR/Build/Products/Release-iphoneos/TetherPhone.app"
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
LOG_DIR="$HOME/Library/Logs/Tether"
mkdir -p "$LOG_DIR"
exec >>"$LOG_DIR/auto-reinstall.log" 2>&1
echo "== $(date '+%Y-%m-%d %H:%M:%S')"

notify() {
  osascript -e "display notification \"$1\" with title \"Tether\"" >/dev/null 2>&1 || true
}

expiry_epoch() {
  local profile="$APP/embedded.mobileprovision"
  [ -f "$profile" ] || { echo 0; return; }
  local iso
  iso=$(security cms -D -i "$profile" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null) || { echo 0; return; }
  date -juf "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null || echo 0
}

now=$(date +%s)
left=$(( $(expiry_epoch) - now ))
if [ "${1:-}" != "--force" ] && [ "$left" -gt $(( RENEW_DAYS * 86400 )) ]; then
  echo "ok: $(( left / 3600 )) h left, nothing to do"
  exit 0
fi

if ! xcrun devicectl device info details --device "$DEVICE" >/dev/null 2>&1; then
  echo "phone not reachable; will retry"
  [ "$left" -lt 86400 ] && notify "Tether expires within a day and your iPhone isn't reachable. Join the same Wi-Fi as the Mac or plug it in."
  exit 1
fi

# Remove only Tether's cached team profile so Xcode fetches a fresh 7-day one.
for f in "$PROFILES"/*.mobileprovision; do
  [ -f "$f" ] || continue
  name=$(security cms -D -i "$f" 2>/dev/null | plutil -extract Name raw -o - - 2>/dev/null)
  if [ "$name" = "iOS Team Provisioning Profile: $BUNDLE_ID" ]; then
    echo "dropping cached profile $(basename "$f")"
    rm -f "$f"
  fi
done

if ! xcodebuild -project Tether.xcodeproj -scheme TetherPhone -configuration Release \
     -destination "id=$DEVICE" -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates build -quiet; then
  echo "build failed"
  notify "Tether couldn't rebuild. Open Xcode once to check the Apple account is still signed in."
  exit 1
fi

if ! xcrun devicectl device install app --device "$DEVICE" "$APP"; then
  echo "install failed"
  notify "Tether built but couldn't install. Unlock the iPhone and keep it on the same Wi-Fi."
  exit 1
fi

new_left=$(( $(expiry_epoch) - $(date +%s) ))
echo "installed; good for $(( new_left / 3600 )) h"
notify "Tether renewed on your iPhone for another 7 days."
