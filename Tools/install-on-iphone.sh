#!/usr/bin/env bash
# Builds Tether and installs it on the iPhone plugged into this Mac (or on the same Wi-Fi after the
# first cable install), then opens it. Run Tools/setup.sh once first.
#
# Usage: Tools/install-on-iphone.sh [device-id]
#   With no device id it picks the one connected iPhone; with several, pass the one you want
#   (list them with: xcrun devicectl list devices).
set -euo pipefail
cd "$(dirname "$0")/.."

grep -q "com.shorielol" project.yml && { echo "run Tools/setup.sh <bundle-prefix> <team-id> first" >&2; exit 2; }
command -v xcodegen >/dev/null || { echo "xcodegen is missing: brew install xcodegen" >&2; exit 2; }

DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  JSON=$(mktemp); trap 'rm -f "$JSON"' EXIT
  xcrun devicectl list devices --json-output "$JSON" >/dev/null
  DEVICE=$(/usr/bin/python3 - "$JSON" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1])).get("result", {}).get("devices", [])
phones = [d for d in devices
          if d.get("hardwareProperties", {}).get("deviceType") == "iPhone"
          and d.get("connectionProperties", {}).get("pairingState") == "paired"]
connected = [d for d in phones if d.get("connectionProperties", {}).get("tunnelState") == "connected"]
pick = connected if connected else phones
if len(pick) != 1:
    sys.exit(f"found {len(pick)} iPhones; plug one in, unlock it and tap Trust, or pass a device id")
print(pick[0]["hardwareProperties"]["udid"])
PY
)
fi
echo "Installing on $DEVICE"

BUNDLE_ID=$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: \(.*\.tether\)$/\1/p' project.yml | head -1)
xcodegen generate -q
xcodebuild -project Tether.xcodeproj -scheme TetherPhone -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath build/dd-device -allowProvisioningUpdates build -quiet
APP=build/dd-device/Build/Products/Release-iphoneos/TetherPhone.app
[ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" || \
  echo "Installed. If it won't open: Settings > General > VPN & Device Management > trust your Apple ID, then open Tether."
