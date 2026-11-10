#!/bin/zsh
# Baut BetterKeyLight.app im Ordner build/
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/BetterKeyLight.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BetterKeyLight "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Fertig: $APP"
