#!/bin/bash
# Builds NewtonsCradle.app from the Swift sources.
set -euo pipefail
cd "$(dirname "$0")"

APP="NewtonsCradle.app"
BIN_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

echo "Cleaning..."
rm -rf "$APP"
mkdir -p "$BIN_DIR" "$RES_DIR"

echo "Writing Info.plist..."
cp Info.plist "$APP/Contents/Info.plist"

if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$RES_DIR/AppIcon.icns"
fi

echo "Compiling for $(uname -m)..."
swiftc -O -swift-version 5 \
    -framework Cocoa -framework CoreMotion -framework QuartzCore \
    -framework IOKit -framework GameController \
    -o "$BIN_DIR/NewtonsCradle" \
    Physics.swift MotionInput.swift CradleView.swift WallpaperWindow.swift AppController.swift main.swift

echo "Signing (ad-hoc)..."
codesign --force --sign - "$APP" || echo "  (codesign skipped — app still runs locally)"

echo ""
echo "Built: $(pwd)/$APP"
echo "  Run:     open \"$(pwd)/$APP\""
echo "  Install: ./install.sh"
