# Spotify Notch

A small native macOS app that turns the MacBook notch into a Spotify widget.

- **Closed:** the notch extends slightly to each side, with the album cover on
  the left and a pulsing visualizer on the right.
- **Open:** hover over it and it grows into a panel with a larger cover, title
  and artist, a seekable progress bar, and shuffle / previous / play-pause /
  next / repeat controls.
- Accent colors are picked from the album cover.
- It opens when Spotify opens and quits when Spotify quits.
- It stays fixed to the notch when you swipe between desktops and fullscreen apps.

Written in Swift (AppKit + SwiftUI), with no dependencies.

## Requirements

- A Mac with a notch running macOS 14 or later (Apple Silicon)
- The Spotify desktop app
- Xcode Command Line Tools (`xcode-select --install`) to build

## Install

```sh
./install.sh
```

This builds the app, copies it to `~/Applications/Spotify Notch.app`, and
registers a small login agent that opens it whenever Spotify launches. The
first time it runs, macOS asks for permission to control Spotify. Click
**Allow**.

To remove everything:

```sh
./uninstall.sh
```

For development, `./build.sh` builds into `build/` without installing.
Launch flags: `--demo` shows a fake track, `--expanded` pins the panel open.

## How it works

- **Playback state** comes from the distributed notification Spotify posts
  whenever playback changes, so nothing is polled. Cover art, shuffle and
  repeat are read with one AppleScript call per change.
- **The visualizer** is a Core Animation loop that runs in the window server,
  capped at 30 fps, so the app sits at 0% CPU while music plays. It's a
  stylized animation, not real audio levels.
- **Staying on the notch** uses private CoreGraphics/SkyLight calls to put the
  window in its own space above the desktops, so it doesn't slide with Spaces
  (`Sources/StickySpace.swift`).
- **The watcher** (`Watcher/main.swift`) is a tiny login agent that waits for
  Spotify to launch and opens the app.

## Known limitations

- Shuffle and repeat use Spotify's AppleScript interface. When the Mac app is
  remote-controlling another device (Spotify Connect, e.g. "Playing on
  iPhone"), changing them doesn't reach that device, and Smart Shuffle and
  repeat-one aren't supported.
- The private APIs used to stay fixed during Space switches are undocumented
  and could change in a future macOS release.
- The app is ad-hoc signed, so macOS may ask again for permission to control
  Spotify after a rebuild.
