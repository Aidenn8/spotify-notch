#!/bin/bash
# Builds "build/Spotify Notch.app" (ad-hoc signed), with the Spotify watcher inside.
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Spotify Notch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/SpotifyNotch"
swiftc -O -target arm64-apple-macos14.0 Watcher/main.swift -o "$APP/Contents/MacOS/SpotifyNotchWatcher"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/MacOS/SpotifyNotchWatcher" >/dev/null 2>&1
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "built $APP"
