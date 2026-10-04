import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy at a time (ignoring the watcher, which shares the bundle).
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != me && $0.executableURL?.lastPathComponent == me.executableURL?.lastPathComponent }
        if !others.isEmpty { NSApp.terminate(nil); return }

        // --watcher: opened by the login agent (no setup, no welcome message).
        // --quiet: set up without the welcome message (used by install.sh).
        // --uninstall: remove the login agent and quit (used by uninstall.sh).
        // Debug: --demo shows a fake track, --expanded pins the panel open.
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
                Installer.install()
            }
            if !args.contains("--watcher") && !args.contains("--quiet") {
                switch showWelcome() {
                case .done: break
                case .openSpotify:
                    // The login agent reopens us once Spotify is up.
                    openSpotify()
                    NSApp.terminate(nil)
                    return
                case .uninstalled:
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

    /// Opening the app again from Finder while it's running shows the
    /// welcome message, which is also where Uninstall lives.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !showingWelcome { _ = showWelcome() }
        return false
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

    private enum WelcomeResult { case done, openSpotify, uninstalled }
    private var showingWelcome = false

    private func showWelcome() -> WelcomeResult {
        showingWelcome = true
        defer { showingWelcome = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Spotify Notch is ready"
        alert.informativeText = """
        Your music shows up in the notch whenever Spotify is open. Hover over it \
        for controls, or right-click it to quit.

        The first time, macOS asks whether Spotify Notch can control Spotify. \
        Click OK so it can show what's playing.
        """
        alert.addButton(withTitle: "Done")
        let canOpenSpotify = !SpotifyModel.isRunning
        if canOpenSpotify { alert.addButton(withTitle: "Open Spotify") }
        alert.addButton(withTitle: "Uninstall…")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .done
        case .alertSecondButtonReturn where canOpenSpotify:
            return .openSpotify
        default:
            return confirmUninstall() ? .uninstalled : .done
        }
    }

    private func confirmUninstall() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Uninstall Spotify Notch?"
        alert.informativeText = "This removes the widget and moves the app to the Trash."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        Installer.uninstall()
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            NSApp.terminate(nil)
        }
        return true
    }

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

    private func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyModel.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
