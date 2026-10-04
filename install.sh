#!/bin/bash
# Builds Spotify Notch, copies it to ~/Applications and lets it set itself up
# (it registers the login agent that opens it whenever Spotify launches).
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
DEST="$HOME/Applications/Spotify Notch.app"
pkill -x SpotifyNotch 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "build/Spotify Notch.app" "$DEST"
open "$DEST" --args --quiet
echo "installed $DEST"
