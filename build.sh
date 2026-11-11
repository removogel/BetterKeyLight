#!/bin/zsh
# Builds BetterKeyLight.app into build/
set -e
cd "$(dirname "$0")"
# UNIVERSAL=1 builds for Apple silicon and Intel (needs full Xcode, used by CI).
ARCHS=()
[[ -n "$UNIVERSAL" ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)"
APP=build/BetterKeyLight.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/BetterKeyLight" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Done: $APP"
