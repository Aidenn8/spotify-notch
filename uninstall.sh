#!/bin/bash
# Removes the watcher and the installed app.
LABEL=com.aidenn8.spotifynotch.watcher
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
pkill -x SpotifyNotch 2>/dev/null
rm -rf "$HOME/Applications/Spotify Notch.app"
echo "uninstalled"
