import AppKit
import ImageIO
import SwiftUI

struct Track: Equatable {
    let id: String
    var name: String
    var artist: String
    var album: String
    var duration: TimeInterval
}

/// Mirrors Spotify's playback state. Updates are push-based: Spotify posts a
/// distributed notification on every change, so there is no polling.
final class SpotifyModel: ObservableObject {
    static let bundleID = "com.spotify.client"
    static let fallbackAccent = NSColor(white: 0.92, alpha: 1)

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent = SpotifyModel.fallbackAccent
    @Published private(set) var shuffling = false
    @Published private(set) var repeating = false
    /// False for the first moments after Spotify launches, while it still
    /// reports the last locally played song from its cache rather than what's
    /// actually playing (e.g. on another device). The widget stays hidden
    /// until this flips.
    @Published private(set) var ready = true

    // Playback position is extrapolated from the last known anchor.
    private var anchorPosition: TimeInterval = 0
    private var anchorDate = Date()

    private var artworkURL: String?
    private let demo: Bool
    private let scripts = ScriptRunner()
    private var refreshInFlight = false
    private var refreshQueued = false
    private var cachedTrackID: String?
    private var synced = false
    private var artworkTrackID: String?   // track the current artwork belongs to

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    init(demo: Bool = false) {
        self.demo = demo
        if demo { loadDemo(); return }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playbackChanged(_:)),
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, suspensionBehavior: .deliverImmediately)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        if Self.isRunning {
            holdWhileSpotifySyncs()
            refresh()
            // A freshly launched Spotify restores its last track without
            // announcing it, so check back a few times while it starts up.
            for delay in [2.0, 5.0, 10.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    if self?.track == nil { self?.refresh() }
                }
            }
        }
    }

    func position(at date: Date) -> TimeInterval {
        guard let track else { return 0 }
        let p = isPlaying ? anchorPosition + date.timeIntervalSince(anchorDate) : anchorPosition
        return min(max(p, 0), track.duration)
    }

    // MARK: Commands

    func playPause() {
        guard track != nil else { return }
        setPlaying(!isPlaying, position: nil)
        send("playpause")
    }

    func next() { send("next track") }
    func previous() { send("previous track") }

    func toggleShuffle() {
        shuffling.toggle()
        send("set shuffling to not shuffling", refreshAfter: true)
    }

    func toggleRepeat() {
        repeating.toggle()
        send("set repeating to not repeating", refreshAfter: true)
    }

    func seek(to seconds: TimeInterval) {
        anchorPosition = seconds
        anchorDate = Date()
        objectWillChange.send()
        send("set player position to \(seconds)", cache: false)
    }

    func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: State sync

    @objc private func playbackChanged(_ note: Notification) {
        let info = note.userInfo ?? [:]
        let state = info["Player State"] as? String
        if state == "Stopped" { clear(); return }

        // Apply what the notification carries right away, then fill in the
        // rest (artwork, shuffle, repeat) with one AppleScript round trip.
        if let id = info["Track ID"] as? String {
            let t = Track(id: id,
                          name: info["Name"] as? String ?? "",
                          artist: info["Artist"] as? String ?? "",
                          album: info["Album"] as? String ?? "",
                          duration: (info["Duration"] as? Double ?? 0) / 1000)
            setTrack(t)
        }
        if let state { setPlaying(state == "Playing", position: info["Playback Position"] as? Double) }
        refresh()
    }

    @objc private func appTerminated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if app?.bundleIdentifier == Self.bundleID { clear() }
    }

    private static let stateScript = """
    if application "Spotify" is running then
        tell application "Spotify"
            set s to player state as string
            if s is "stopped" then return {s}
            set t to current track
            return {s, id of t, name of t, artist of t, album of t, duration of t, player position, artwork url of t, shuffling, repeating}
        end tell
    end if
    return {"closed"}
    """

    func refresh() {
        guard !demo, Self.isRunning else { return }
        if refreshInFlight { refreshQueued = true; return }
        refreshInFlight = true
        scripts.run(Self.stateScript) { [weak self] result in
            guard let self else { return }
            self.refreshInFlight = false
            self.apply(result)
            if self.refreshQueued { self.refreshQueued = false; self.refresh() }
        }
    }

    private func apply(_ d: NSAppleEventDescriptor?) {
        guard let d, d.numberOfItems >= 1 else { return }
        let state = d.atIndex(1)?.stringValue
        if state == "stopped" || state == "closed" { clear(); return }
        guard d.numberOfItems >= 10 else { return }

        let t = Track(id: d.atIndex(2)?.stringValue ?? "",
                      name: d.atIndex(3)?.stringValue ?? "",
                      artist: d.atIndex(4)?.stringValue ?? "",
                      album: d.atIndex(5)?.stringValue ?? "",
                      duration: (d.atIndex(6)?.doubleValue ?? 0) / 1000)
        setTrack(t)
        setPlaying(state == "playing", position: d.atIndex(7)?.doubleValue)
        loadArtwork(d.atIndex(8)?.stringValue, for: t.id)
        let shuffle = d.atIndex(9)?.booleanValue ?? false
        let rep = d.atIndex(10)?.booleanValue ?? false
        if shuffle != shuffling { shuffling = shuffle }
        if rep != repeating { repeating = rep }
    }

    private func setTrack(_ t: Track) {
        if t != track { track = t }
        // Spotify moving off its cached song means it has synced.
        if !ready {
            if cachedTrackID == nil { cachedTrackID = t.id } else if t.id != cachedTrackID { markSynced() }
        }
    }

    private func setPlaying(_ playing: Bool, position: TimeInterval?) {
        let now = Date()
        anchorPosition = position ?? self.position(at: now)
        anchorDate = now
        if playing != isPlaying { isPlaying = playing }
        if playing && !ready { markSynced() }
    }

    private func markSynced() {
        synced = true
        revealIfReady()
    }

    /// Reveal once Spotify has synced and the cover for the real track is in,
    /// so the first thing shown is never the cached song or its cover.
    private func revealIfReady() {
        guard !ready, synced, let track, artworkTrackID == track.id else { return }
        ready = true
    }

    /// Spotify takes ~2s after launch to sync with what's really playing, so
    /// hold the widget back until it reports playback or moves off its cached
    /// song (and that song's cover has loaded), with a 4s backstop.
    private func holdWhileSpotifySyncs() {
        let launch = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            .compactMap(\.launchDate).max()
        guard let launch else { return }
        let remaining = 4 - Date().timeIntervalSince(launch)
        guard remaining > 0 else { return }
        ready = false
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            self?.ready = true
        }
    }

    private func clear() {
        guard track != nil else { return }
        track = nil
        isPlaying = false
        artworkURL = nil
        artwork = nil
        accent = Self.fallbackAccent
    }

    private func send(_ command: String, cache: Bool = true, refreshAfter: Bool = false) {
        guard !demo, Self.isRunning else { return }
        scripts.run("tell application \"Spotify\" to \(command)", cache: cache) { [weak self] _ in
            if refreshAfter { self?.refresh() }
        }
    }

    // MARK: Artwork

    private func loadArtwork(_ urlString: String?, for trackID: String) {
        guard urlString != artworkURL else {
            // Same cover (e.g. same album) already showing.
            artworkTrackID = trackID
            revealIfReady()
            return
        }
        artworkURL = urlString
        guard var s = urlString, !s.isEmpty else {
            artwork = nil
            accent = Self.fallbackAccent
            artworkTrackID = trackID
            revealIfReady()
            return
        }
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst(7) }
        guard let url = URL(string: s) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let (image, accent) = Artwork.process(data) else { return }
            DispatchQueue.main.async {
                guard let self, self.artworkURL == urlString else { return }
                // Crossfade between covers, except for the very first reveal,
                // which would otherwise briefly ghost the cached cover.
                withAnimation(self.ready ? .easeInOut(duration: 0.35) : nil) {
                    self.artwork = image
                    self.accent = accent
                }
                self.artworkTrackID = trackID
                self.revealIfReady()
            }
        }.resume()
    }

    private func loadDemo() {
        track = Track(id: "demo", name: "Midnight City", artist: "M83",
                      album: "Hurry Up, We're Dreaming", duration: 243)
        anchorPosition = 71
        isPlaying = true
        shuffling = true
        if let image = Artwork.demoImage(), let tiff = image.tiffRepresentation,
           let (thumb, accent) = Artwork.process(tiff) {
            artwork = thumb
            self.accent = accent
        }
    }
}

/// Runs AppleScript off the main thread on a single serial queue
/// (NSAppleScript isn't safe to use concurrently).
final class ScriptRunner {
    private let queue = DispatchQueue(label: "spotifynotch.applescript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    func run(_ source: String, cache: Bool = true, completion: @escaping (NSAppleEventDescriptor?) -> Void) {
        queue.async {
            let script = self.compiled[source] ?? NSAppleScript(source: source)
            if cache { self.compiled[source] = script }
            var error: NSDictionary?
            let result = script?.executeAndReturnError(&error)
            if let error { NSLog("Spotify Notch AppleScript error: \(error)") }
            DispatchQueue.main.async { completion(error == nil ? result : nil) }
        }
    }
}

enum Artwork {
    /// Downsamples the cover and picks a vivid accent color from it.
    static func process(_ data: Data) -> (NSImage, NSColor)? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 192] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let image = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
        return (image, accent(from: thumb))
    }

    /// Buckets pixels by hue, weighted by saturation x brightness, and returns
    /// the strongest hue brightened enough to read on black. Near-greyscale
    /// covers fall back to soft white.
    static func accent(from image: CGImage) -> NSColor {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return SpotifyModel.fallbackAccent }

        let binCount = 18
        var weight = [CGFloat](repeating: 0, count: binCount)
        var sat = [CGFloat](repeating: 0, count: binCount)
        var bri = [CGFloat](repeating: 0, count: binCount)
        var hx = [CGFloat](repeating: 0, count: binCount)
        var hy = [CGFloat](repeating: 0, count: binCount)

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let c = NSColor(srgbRed: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255,
                            blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            guard s > 0.2, b > 0.25 else { continue }
            let w = s * b
            let bin = min(Int(h * CGFloat(binCount)), binCount - 1)
            weight[bin] += w
            sat[bin] += s * w
            bri[bin] += b * w
            hx[bin] += cos(h * 2 * .pi) * w
            hy[bin] += sin(h * 2 * .pi) * w
        }

        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }),
              weight[best] > CGFloat(side * side) * 0.02 else { return SpotifyModel.fallbackAccent }
        var hue = atan2(hy[best], hx[best]) / (2 * .pi)
        if hue < 0 { hue += 1 }
        let s = min(max(sat[best] / weight[best], 0.4), 0.75)
        let b = max(bri[best] / weight[best], 0.92)
        let color = NSColor(hue: hue, saturation: s, brightness: b, alpha: 1)

        // Blues and purples still read dark on black at full brightness,
        // so lift anything with low perceived luminance toward white.
        guard let rgb = color.usingColorSpace(.sRGB) else { return color }
        let luma = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        let target: CGFloat = 0.55
        guard luma < target else { return color }
        return color.blended(withFraction: (target - luma) / (1 - luma), of: .white) ?? color
    }

    static func demoImage() -> NSImage? {
        let size = NSSize(width: 300, height: 300)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.36, blue: 0.55, alpha: 1),
                                NSColor(srgbRed: 0.35, green: 0.18, blue: 0.75, alpha: 1),
                                NSColor(srgbRed: 0.05, green: 0.05, blue: 0.2, alpha: 1)])?
                .draw(in: rect, angle: -60)
            NSColor(white: 1, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 190, y: 170, width: 46, height: 46)).fill()
            return true
        }
    }
}
