#!/bin/bash
# Builds the app and wraps it in dist/Spotify-Notch.dmg for a GitHub release.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
STAGE=$(mktemp -d)
ditto "build/Spotify Notch.app" "$STAGE/Spotify Notch.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
rm -f dist/Spotify-Notch.dmg
hdiutil create -quiet -volname "Spotify Notch" -srcfolder "$STAGE" -format UDZO -ov dist/Spotify-Notch.dmg
rm -rf "$STAGE"
echo "packaged dist/Spotify-Notch.dmg"
