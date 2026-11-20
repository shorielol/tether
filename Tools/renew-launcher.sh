#!/bin/bash
# What the LaunchAgent runs. macOS blocks background jobs from reading ~/Desktop, so the job keeps
# its own copy of the repo in Application Support, pulls the latest code, and runs auto-reinstall.sh
# from there. Install: copy this file to ~/Library/Application Support/Tether/renew.sh.
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
SRC="$HOME/Library/Application Support/Tether/src"
LOG="$HOME/Library/Logs/Tether/auto-reinstall.log"
mkdir -p "$(dirname "$LOG")"
git -C "$SRC" pull --ff-only -q >>"$LOG" 2>&1 || echo "$(date '+%F %T') git pull failed; using the last copy" >>"$LOG"
cd "$SRC" && xcodegen generate -q >>"$LOG" 2>&1
exec /bin/bash "$SRC/Tools/auto-reinstall.sh" "$@"
