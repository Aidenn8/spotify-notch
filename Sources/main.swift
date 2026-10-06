import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy at a time (ignoring the watcher, which shares the bundle).
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != me && $0.executableURL?.lastPathComponent == me.executableURL?.lastPathComponent }
        if !others.isEmpty { NSApp.terminate(nil); return }

        // --watcher: opened by the login agent (no setup).
        // --quiet: set up without opening Spotify (used by install.sh).
        // --uninstall: remove the login agent and quit (used by uninstall.sh).
        // Debug: --demo shows made-up tracks, --expanded pins the panel open.
        let args = CommandLine.arguments
        let demo = args.contains("--demo")

        if args.contains("--uninstall") {
            Installer.uninstall()
            NSApp.terminate(nil)
            return
        }

        if !demo {
            guard Installer.isInStableLocation else {
                showMoveToApplications()
                NSApp.terminate(nil)
                return
            }
            if !args.contains("--watcher") {
                // Opened by hand: set up quietly. If Spotify isn't running,
                // open it; the login agent brings the widget up once it is.
                Installer.install()
                if !SpotifyModel.isRunning && !args.contains("--quiet") {
                    // Quit only once the launch request has gone through;
                    // quitting right away cancels it.
                    openSpotify { NSApp.terminate(nil) }
                    return
                }
            }

            // Spotify Notch lives and dies with Spotify.
            guard SpotifyModel.isRunning else { NSApp.terminate(nil); return }
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(appTerminated(_:)),
                name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        }
        controller = NotchController(demo: demo, pinExpanded: args.contains("--expanded"))
    }

    /// The app has no windows to bring forward when opened again from Finder.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        false
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

    // MARK: Messages

    private func showMoveToApplications() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Spotify Notch to Applications"
        alert.informativeText = """
        Drag Spotify Notch into your Applications folder, then open it from there.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func openSpotify(then done: @escaping () -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyModel.bundleID) else {
            done()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in
            DispatchQueue.main.async(execute: done)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
