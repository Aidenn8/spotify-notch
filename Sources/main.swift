import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy at a time.
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != me }
        if !others.isEmpty { NSApp.terminate(nil); return }

        // Debug flags: --demo shows a fake track, --expanded pins the panel open.
        let args = CommandLine.arguments
        let demo = args.contains("--demo")

        // Spotify Notch lives and dies with Spotify (the watcher reopens it).
        if !demo {
            guard SpotifyModel.isRunning else { NSApp.terminate(nil); return }
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(appTerminated(_:)),
                name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        }
        controller = NotchController(demo: demo, pinExpanded: args.contains("--expanded"))
    }

    @objc private func appTerminated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.bundleIdentifier == SpotifyModel.bundleID else { return }
        // Let the widget retract into the notch first, and stay if Spotify
        // was relaunched in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if !SpotifyModel.isRunning { NSApp.terminate(nil) }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
