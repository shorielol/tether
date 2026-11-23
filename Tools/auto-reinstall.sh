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

# Your iPhone's id (`xcrun devicectl list devices`), kept out of the repo: set TETHER_DEVICE_ID or write it
# to ~/Library/Application Support/Tether/device-id.
DEVICE="${TETHER_DEVICE_ID:-$(cat "$HOME/Library/Application Support/Tether/device-id" 2>/dev/null)}"
[ -n "$DEVICE" ] || { echo "no iPhone id: set TETHER_DEVICE_ID or write it to ~/Library/Application Support/Tether/device-id"; exit 2; }
BUNDLE_ID="com.shorielol.tether"
# The app and its lock-screen widget extension each carry their own 7-day profile (ADR-005).
BUNDLE_IDS=("$BUNDLE_ID" "$BUNDLE_ID.widgets")
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

profile_expiry() {
  local profile="$1/embedded.mobileprovision"
  [ -f "$profile" ] || { echo 0; return; }
  local iso
  iso=$(security cms -D -i "$profile" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null) || { echo 0; return; }
  date -juf "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null || echo 0
}

# Whichever runs out first: the app or the widget extension. A missing profile counts as expired.
expiry_epoch() {
  local app widgets
  app=$(profile_expiry "$APP")
  widgets=$(profile_expiry "$APP/PlugIns/TetherWidgets.appex")
  [ "$app" -lt "$widgets" ] && echo "$app" || echo "$widgets"
}

# What is actually on the phone, shared by every copy of this script (the Desktop repo and the
# renewal clone). Without it each copy judged expiry by its own last build, so the clone reinstalled
# its older code over a newer build from the Desktop (2026-11-22).
STATE="$HOME/Library/Application Support/Tether/installed.txt"

state_value() {
  [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE" | head -1
}

installed_expiry() {
  local recorded
  recorded=$(state_value expiry)
  if [ -n "$recorded" ]; then echo "$recorded"; else expiry_epoch; fi
}

now=$(date +%s)
left=$(( $(installed_expiry) - now ))
if [ "${1:-}" != "--force" ] && [ "$left" -gt $(( RENEW_DAYS * 86400 )) ]; then
  echo "ok: $(( left / 3600 )) h left, nothing to do"
  exit 0
fi

if ! xcrun devicectl device info details --device "$DEVICE" >/dev/null 2>&1; then
  echo "phone not reachable; will retry"
  [ "$left" -lt 86400 ] && notify "Tether expires within a day and your iPhone isn't reachable. Join the same Wi-Fi as the Mac or plug it in."
  exit 1
fi

# Never install older code than the phone already has. A copy that doesn't contain the installed
# commit is behind, so it stops and says so instead of quietly undoing newer work.
head_commit=$(git rev-parse HEAD 2>/dev/null || echo "")
installed_commit=$(state_value commit)
if [ -n "$installed_commit" ] && ! git merge-base --is-ancestor "$installed_commit" HEAD 2>/dev/null; then
  echo "skipping: this copy (${head_commit:0:7}) is older than the build on the phone (${installed_commit:0:7})"
  notify "Tether's renewal copy is behind the app on your iPhone, so it didn't reinstall. Push the repo so it can renew."
  exit 1
fi

# Remove only Tether's cached team profiles (app + widgets) so Xcode fetches fresh 7-day ones.
for f in "$PROFILES"/*.mobileprovision; do
  [ -f "$f" ] || continue
  name=$(security cms -D -i "$f" 2>/dev/null | plutil -extract Name raw -o - - 2>/dev/null)
  for id in "${BUNDLE_IDS[@]}"; do
    if [ "$name" = "iOS Team Provisioning Profile: $id" ]; then
      echo "dropping cached profile $(basename "$f") ($id)"
      rm -f "$f"
    fi
  done
done

# The .xcodeproj is generated and git-ignored, so regenerate it from project.yml: a copy that only
# pulls from git would otherwise build with a stale file list and miss new screens.
XCODEGEN=$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)
if [ -x "$XCODEGEN" ] && ! "$XCODEGEN" generate --quiet; then
  echo "xcodegen failed"
  notify "Tether couldn't regenerate its Xcode project. Run xcodegen in the repo once to see why."
  exit 1
fi

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

new_expiry=$(expiry_epoch)
mkdir -p "$(dirname "$STATE")"
printf 'expiry=%s\ncommit=%s\n' "$new_expiry" "$head_commit" > "$STATE"
new_left=$(( new_expiry - $(date +%s) ))
echo "installed ${head_commit:0:7}; good for $(( new_left / 3600 )) h"
notify "Tether renewed on your iPhone for another 7 days."
