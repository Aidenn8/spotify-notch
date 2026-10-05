# Spotify Notch

Turns the notch on your MacBook into a Spotify widget.

- **Closed:** the notch extends slightly to each side, with the album cover on
  the left and a pulsing visualizer on the right.
- **Open:** hover over it and it grows into a mini player with the cover, song,
  progress bar, and shuffle / previous / play-pause / next / repeat buttons.
- Colors are picked from the album cover.
- Pick the open panel's background: solid black (default) or one of four glass
  styles (smoky, frosted, clear, or tinted with the album's color).
- It appears when Spotify opens and disappears when Spotify quits.

## Download

**[⬇ Download Spotify Notch](https://github.com/Aidenn8/spotify-notch/releases/latest/download/Spotify-Notch.dmg)**

You need a MacBook with a notch (Apple Silicon) on macOS 14 Sonoma or later,
and the Spotify app.

### Install

1. Open the downloaded **Spotify-Notch.dmg**.
2. Drag **Spotify Notch** into the **Applications** folder.
3. Open **Spotify Notch** from your Applications folder.
4. macOS will warn that it can't check the app for malicious software. That's
   because this is a free project that isn't registered with Apple. To allow it,
   this one time:
   - Click **Done** (or **OK**) on the warning.
   - Open **System Settings → Privacy & Security**.
   - Scroll down to the message about Spotify Notch and click **Open Anyway**,
     then confirm with your password.
5. Spotify opens and the widget appears in the notch. When macOS asks whether
   Spotify Notch can control Spotify, click **OK**.

That's it. From now on the widget shows up whenever Spotify is open, even after
restarting your Mac.

### Uninstall

Drag **Spotify Notch** from your Applications folder to the Trash. It removes
its login item by itself, so nothing is left behind.

### Updating

Download the new version, drag it into Applications (replace the old one), and
open it once.

## Tips

- Right-click the widget to change the background, open Spotify, or quit.
  After quitting, it comes back the next time Spotify opens.
- Shuffle and repeat only work when music is playing on this Mac. If Spotify is
  controlling another device (for example "Playing on iPhone"), those two
  buttons can't change it.

## Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/Aidenn8/spotify-notch.git
cd spotify-notch
./install.sh      # build, copy to ~/Applications and set up
./uninstall.sh    # remove it again
```

`./build.sh` builds into `build/` without installing, and `./package.sh` makes
`dist/Spotify-Notch.dmg`. Launch flags for development: `--demo` shows a fake
track, `--expanded` pins the panel open. `tools/make-icon.swift` redraws the
app icon.

## How it works

Written in Swift (AppKit + SwiftUI) with no dependencies.

- **Playback state** comes from the notification Spotify posts whenever
  playback changes, so nothing is polled. Cover art, shuffle and repeat are read
  with one AppleScript call per change.
- **The visualizer** is a Core Animation loop that runs in the window server,
  capped at 30 fps, so the app uses no CPU while music plays. It's a stylized
  animation, not real audio levels.
- **Staying on the notch** uses private CoreGraphics/SkyLight calls to put the
  window in its own space above the desktops, so it doesn't slide when you
  switch Spaces (`Sources/StickySpace.swift`).
- **Opening with Spotify:** when you open the app it installs a small login
  agent (`Watcher/main.swift`) that waits for Spotify to launch and opens the
  widget. The widget quits when Spotify does. When the app is moved to the
  Trash, the agent removes itself.

## Known limitations

- Shuffle and repeat use Spotify's AppleScript interface, which can't reach
  other devices over Spotify Connect, and doesn't support Smart Shuffle or
  repeat-one.
- The private APIs used to stay fixed during Space switches are undocumented
  and could change in a future macOS release.
- The app isn't notarized by Apple, hence the one-time **Open Anyway** step.
