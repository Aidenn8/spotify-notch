#!/bin/bash
# Removes the login agent and the app installed by install.sh.
DEST="$HOME/Applications/Spotify Notch.app"
pkill -x SpotifyNotch 2>/dev/null
[ -d "$DEST" ] && "$DEST/Contents/MacOS/SpotifyNotch" --uninstall
rm -rf "$DEST"
echo "uninstalled"
