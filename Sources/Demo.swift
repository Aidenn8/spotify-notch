import AppKit

/// Made-up tracks for --demo, with generated covers and lyrics, so the widget
/// can be shown (and recorded for the README) without Spotify. Next and
/// previous cycle through them.
struct DemoTrack {
    let track: Track
    /// Playback position when the track comes on, in seconds.
    let start: TimeInterval
    /// Cover gradient, from the top-left corner to the bottom-right.
    let colors: [NSColor]
    let lyrics: [LyricLine]

    static let all: [DemoTrack] = [
        DemoTrack(
            track: Track(id: "demo-1", name: "Streetlight Hum", artist: "Neon Harbor",
                         album: "Night Drive", duration: 243),
            start: 68.5,
            colors: [rgb(0.98, 0.36, 0.55), rgb(0.35, 0.18, 0.75), rgb(0.05, 0.05, 0.2)],
            lyrics: lines([
                (60, "Streetlights hum a song we used to know"),
                (63.5, "Every window glowing soft and slow"),
                (67, "We keep driving with the radio on"),
                (70.5, "Chasing summer till the night is gone"),
                (74, "Neon rivers running through the town"),
                (77.5, "Nobody here is gonna slow us down"),
                (81, "Hold on tight, the city's wide awake"),
                (84.5, "Every turn is ours to take"),
                (88, ""),
                (92, "Streetlights hum a song we used to know"),
                (95.5, "Every window glowing soft and slow"),
            ])),
        DemoTrack(
            track: Track(id: "demo-2", name: "Tidewater", artist: "Cold Coast",
                         album: "Low Light", duration: 198),
            start: 40,
            colors: [rgb(0.25, 0.9, 0.78), rgb(0.05, 0.38, 0.52), rgb(0.02, 0.08, 0.16)],
            lyrics: []),
        DemoTrack(
            track: Track(id: "demo-3", name: "Paper Satellites", artist: "Lumen Fields",
                         album: "Signal Fires", duration: 221),
            start: 95,
            colors: [rgb(1.0, 0.76, 0.3), rgb(0.93, 0.36, 0.2), rgb(0.26, 0.06, 0.13)],
            lyrics: []),
    ]

    static func lyrics(for id: String) -> [LyricLine] {
        all.first { $0.track.id == id }?.lyrics ?? []
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func lines(_ pairs: [(TimeInterval, String)]) -> [LyricLine] {
        pairs.map { LyricLine(time: $0.0, text: $0.1) }
    }
}
