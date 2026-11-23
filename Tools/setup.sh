#!/usr/bin/env bash
# One-time setup so Tether builds and signs under YOUR Apple account instead of the original author's.
# It swaps the app's identifiers (com.shorielol.*) for your own prefix and sets your Apple team ID.
# Safe to run again with the same values.
#
# Usage: Tools/setup.sh <bundle-prefix> <team-id>
#   bundle-prefix  reverse-DNS you own or make up, e.g. com.alexsmith   (letters, digits, dots, hyphens)
#   team-id        your 10-character Apple team ID (Xcode > Settings > Accounts > your team), e.g. AB12CD34EF
set -euo pipefail
cd "$(dirname "$0")/.."

PREFIX="${1:-}"; TEAM="${2:-}"
[[ "$PREFIX" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || { echo "bundle prefix should look like com.yourname" >&2; exit 2; }
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "team ID should be 10 capital letters/digits, e.g. AB12CD34EF" >&2; exit 2; }

OLD="com.shorielol"
FILES=(
  project.yml
  App/iOS/Info.plist
  App/iOS/TetherPhone.entitlements
  App/Widgets/TetherWidgets.entitlements
  Packages/TetherSnapshot/Sources/TetherSnapshot/MorningSnapshot.swift
  Tools/auto-reinstall.sh
)
for file in "${FILES[@]}"; do
  [ -f "$file" ] && sed -i '' "s/${OLD//./\\.}/$PREFIX/g" "$file"
done
# Team ID: replace whatever is there (blank or an earlier value).
sed -i '' -E "s/^( *DEVELOPMENT_TEAM:).*/\1 $TEAM/" project.yml

if grep -rq "$OLD" "${FILES[@]}" 2>/dev/null; then
  echo "some identifiers were not replaced:" >&2; grep -rn "$OLD" "${FILES[@]}" >&2; exit 1
fi
echo "Tether now uses $PREFIX.tether (team $TEAM). Next: Tools/install-on-iphone.sh"
