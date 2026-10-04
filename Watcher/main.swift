import AppKit

// Tiny login agent: opens Spotify Notch whenever Spotify launches. It only reacts
// to macOS's app-launch notifications, so it sits idle the rest of the time.
// Spotify Notch quits itself when Spotify quits.

let spotifyID = "com.spotify.client"

// Lives next to the app's own executable in Spotify Notch.app/Contents/MacOS,
// so the main bundle is the app itself.
let appURL = Bundle.main.bundleURL

func openSpotifyNotch() {
    // Already open (e.g. the user just opened it, which re-registers us).
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    guard !running.contains(where: { $0.executableURL?.lastPathComponent == "SpotifyNotch" }) else { return }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    config.addsToRecentItems = false
    config.arguments = ["--watcher"]   // skip the welcome message
    NSWorkspace.shared.openApplication(at: appURL, configuration: config)
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
) { note in
    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    if app?.bundleIdentifier == spotifyID { openSpotifyNotch() }
}

if !NSRunningApplication.runningApplications(withBundleIdentifier: spotifyID).isEmpty {
    openSpotifyNotch()
}

// A plain run loop rather than NSApplication: an NSApplication here would
// register with macOS as a running copy of Spotify Notch itself (it shares
// the bundle), which would stop the real app from launching.
RunLoop.main.run()
