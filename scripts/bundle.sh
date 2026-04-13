#!/bin/bash
set -euo pipefail

APP="MicMixer.app"
BUILD_DIR=".build/release"
BINARY="$BUILD_DIR/MicMixer"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/MicMixer"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --sign - "$APP"

echo "Built: $APP"
