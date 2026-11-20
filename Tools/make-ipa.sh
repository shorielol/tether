#!/usr/bin/env bash
# Builds an unsigned Release Tether.ipa for SideStore, which re-signs it on the phone with your own
# Apple ID. Same approach as NOOP's sideload build. Tether needs no entitlements (background
# Bluetooth is an Info.plist key), so a plain ad-hoc signature is enough.
#
# Usage: Tools/make-ipa.sh        → build/ipa/Tether-<version>.ipa
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate -q
xcodebuild -project Tether.xcodeproj -scheme TetherPhone -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/dd-release \
  CODE_SIGNING_ALLOWED=NO build -quiet
APP=build/dd-release/Build/Products/Release-iphoneos/TetherPhone.app
[ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }
codesign --force --deep --sign - "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
OUT="$PWD/build/ipa"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload" "$OUT"
cp -R "$APP" "$STAGE/Payload/"
IPA="$OUT/Tether-$VERSION.ipa"
rm -f "$IPA"
(cd "$STAGE" && zip -qry "$IPA" Payload)
echo "$IPA"
