#!/bin/bash
# Gateway-safe uninstall: no launchctl, no pkill.
set -euo pipefail
DEST="/Applications/NewtonsCradle.app"

osascript -e 'tell application "NewtonsCradle" to quit' >/dev/null 2>&1 || true
sleep 0.3
osascript -e 'tell application "System Events" to delete (every login item whose name is "NewtonsCradle")' >/dev/null 2>&1 || true
osascript -e 'tell application "System Events" to delete (every login item whose name is "Newton'\''s Cradle")' >/dev/null 2>&1 || true
rm -rf "$DEST"
echo "Newton's Cradle removed. Settings remain in ~/Library/Application Support/NewtonsCradle/"
