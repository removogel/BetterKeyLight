#!/bin/zsh
# Baut KeyLightBar.app im Ordner build/
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/KeyLightBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/KeyLightBar "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Fertig: $APP"
