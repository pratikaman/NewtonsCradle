#!/bin/bash
# Build Newton's Cradle, install to /Applications, open it, add login item.
# Avoids launchctl/pkill so it can run from inside Hermes too.
set -euo pipefail
cd "$(dirname "$0")"

DEST="/Applications/NewtonsCradle.app"

echo "==> Building..."
./build.sh

echo "==> Quitting running copy if any..."
osascript -e 'tell application "NewtonsCradle" to quit' >/dev/null 2>&1 || true
sleep 0.4

echo "==> Installing to $DEST..."
rm -rf "$DEST"
cp -R NewtonsCradle.app "$DEST"

echo "==> Adding login item..."
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/NewtonsCradle.app", hidden:false}' >/dev/null 2>&1 || true

echo "==> Launching..."
open "$DEST"

echo ""
echo "Done. Newton's Cradle is in /Applications and opens at login."
echo "  Menu bar: five-ball icon. Tilt the Mac (or move the mouse) to swing it."
echo "  Remove:  ./uninstall.sh"
