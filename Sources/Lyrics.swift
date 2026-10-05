import AppKit
import Combine
import SwiftUI

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

/// Time-synced lyrics for the current track, from LRCLIB (lrclib.net, free,
/// no account), shown in the open panel. Only active while the "Show
/// Lyrics" setting is on.
///
/// Rather than polling, it sets one timer for the moment the next line
/// starts, and re-times whenever playback is re-anchored. Lyrics are fetched
/// on every track change (so the panel knows whether to make room), but the
/// timers only run while the panel is open.
final class LyricsModel: ObservableObject {
    enum Status: Equatable { case off, loading, found, missing }

    @Published private(set) var status: Status = .off
    @Published private(set) var lines: [LyricLine] = []
    /// Index of the line being sung (-1 before the first one).
    @Published private(set) var current = -1
    /// Whether the widget should make room for lyrics. Stays on while the
    /// next song's lyrics load, so the layout doesn't flicker between songs.
    @Published private(set) var showing = false

    var enabled = false {
        didSet { if enabled != oldValue { reload() } }
    }

    /// Whether the lyrics are on screen (the panel is open).
    var visible = false {
        didSet { if visible != oldValue { retime() } }
    }

    /// Lines change a beat early so the scroll lands as the line starts.
    private static let lead: TimeInterval = 0.3

    private let spotify: SpotifyModel
    private let demo: Bool
    private var cache: [String: [LyricLine]] = [:]   // track id -> lines ([] = none)
    private var loadingID: String?
    private var request: URLSessionDataTask?
    private var lineTimer: Timer?
    private var syncTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(spotify: SpotifyModel, demo: Bool) {
        self.spotify = spotify
        self.demo = demo
        // @Published fires before the value changes, so read it a beat later.
        spotify.$track.map { $0?.id }.removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.reload() } }
            .store(in: &cancellables)
        spotify.$isPlaying.removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.retime() } }
            .store(in: &cancellables)
        spotify.anchorChanged
            .sink { [weak self] in self?.retime() }
            .store(in: &cancellables)
    }

    /// Text for a row of the scroller; nil marks a gap (intro or
    /// instrumental break), which shows a music note.
    func text(at index: Int) -> String? {
        if index == -1 { return nil }
        guard lines.indices.contains(index) else { return "" }
        return lines[index].text.isEmpty ? nil : lines[index].text
    }

    private func reload() {
        request?.cancel()
        request = nil
        guard enabled, let track = spotify.track else {
            loadingID = nil
            lines = []
            current = -1
            status = .off
            showing = false
            retime()
            return
        }
        if let cached = cache[track.id] { apply(cached); return }

        loadingID = track.id
        lines = []
        current = -1
        status = .loading
        retime()
        if demo {
            DispatchQueue.main.async { self.finish(Self.demoLines, for: track.id) }
            return
        }
        request = LyricsFetcher.fetch(track) { [weak self] found in
            self?.finish(found, for: track.id)
        }
    }

    private func finish(_ found: [LyricLine], for id: String) {
        cache[id] = found
        guard loadingID == id else { return }
        loadingID = nil
        apply(found)
    }

    private func apply(_ found: [LyricLine]) {
        lines = found
        status = found.isEmpty ? .missing : .found
        showing = !found.isEmpty
        retime()
    }

    /// Works out the current line from the playback position and sets a
    /// timer for the next one.
    private func retime() {
        lineTimer?.invalidate()
        lineTimer = nil
        guard status == .found else {
            stopSync()
            if current != -1 { current = -1 }
            return
        }
        guard visible else { stopSync(); return }
        let position = spotify.position(at: Date()) + Self.lead
        let index = lines.lastIndex { $0.time <= position } ?? -1
        if index != current { current = index }

        guard spotify.isPlaying else { stopSync(); return }
        startSync()
        guard lines.indices.contains(index + 1) else { return }
        let timer = Timer(timeInterval: max(lines[index + 1].time - position, 0.02), repeats: false) { [weak self] _ in
            self?.retime()
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        lineTimer = timer
    }

    /// Spotify doesn't announce seeks made in its own window, so re-read the
    /// position every few seconds while lyrics are scrolling.
    private func startSync() {
        guard syncTimer == nil else { return }
        let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in self?.spotify.syncPosition() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
    }

    private func stopSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    /// Made-up lines for --demo, timed around the demo track's position.
    private static let demoLines: [LyricLine] = [
        (60, "Streetlights hum a song we used to know"), (64.5, "Every window glowing soft and slow"),
        (69, "We keep driving with the radio on"), (73.5, ""), (76, "Chasing summer till the night is gone"),
        (80.5, "Neon rivers running through the town"), (85, "Nobody here is gonna slow us down"),
        (89.5, "Hold on tight, the city's wide awake"), (94, "Every turn is ours to take"),
        (98.5, ""), (101, "Streetlights hum a song we used to know"), (105.5, "Every window glowing soft and slow"),
        (110, "We keep driving with the radio on"), (114.5, "Chasing summer till the night is gone"),
    ].map { LyricLine(time: $0.0, text: $0.1) }
}

// MARK: - LRCLIB

enum LyricsFetcher {
    private static let base = URL(string: "https://lrclib.net/api")!
    // LRCLIB asks clients to identify themselves.
    private static let userAgent = "SpotifyNotch/1.2 (https://github.com/Aidenn8/spotify-notch)"

    private struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let syncedLyrics: String?
    }

    /// Exact match first; then a search by title and artist, accepting the
    /// result whose length is within a few seconds of the track. Calls back
    /// on the main queue with [] when there are no synced lyrics.
    @discardableResult
    static func fetch(_ track: Track, completion: @escaping ([LyricLine]) -> Void) -> URLSessionDataTask? {
        let done = { (lines: [LyricLine]) in DispatchQueue.main.async { completion(lines) } }
        let exact = request("get", [
            "track_name": track.name, "artist_name": track.artist,
            "album_name": track.album, "duration": String(Int(track.duration.rounded())),
        ])
        return load(exact, as: Record.self) { record in
            if let record, record.instrumental == true { return done([]) }
            if let lrc = record?.syncedLyrics, !lrc.isEmpty { return done(parse(lrc)) }

            let search = request("search", ["track_name": cleaned(track.name), "artist_name": track.artist])
            load(search, as: [Record].self) { results in
                let match = (results ?? [])
                    .filter { $0.instrumental != true && !($0.syncedLyrics ?? "").isEmpty }
                    .filter { abs(($0.duration ?? 0) - track.duration) <= 3 }
                    .min { abs(($0.duration ?? 0) - track.duration) < abs(($1.duration ?? 0) - track.duration) }
                done(match.flatMap(\.syncedLyrics).map(parse) ?? [])
            }
        }
    }

    private static func request(_ path: String, _ query: [String: String]) -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    @discardableResult
    private static func load<T: Decodable>(_ request: URLRequest, as type: T.Type,
                                           completion: @escaping (T?) -> Void) -> URLSessionDataTask {
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            completion(ok ? data.flatMap { try? JSONDecoder().decode(T.self, from: $0) } : nil)
        }
        task.resume()
        return task
    }

    /// "Song (Live) - Remastered 2011" -> "Song", for the search fallback.
    static func cleaned(_ title: String) -> String {
        var t = title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+-\s+.*$"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Parses LRC: "[mm:ss.xx] text", possibly several timestamps per line.
    static func parse(_ lrc: String) -> [LyricLine] {
        let stamp = #/\[(\d+):(\d+(?:\.\d+)?)\]/#
        var lines: [LyricLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while let match = rest.prefixMatch(of: stamp),
                  let minutes = Double(match.1), let seconds = Double(match.2) {
                times.append(minutes * 60 + seconds)
                rest = rest[match.range.upperBound...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { LyricLine(time: $0, text: text) }
        }
        return lines.sorted { $0.time < $1.time }
    }
}

// MARK: - Views

/// Lines stacked like a teleprompter: the current line on top, upcoming
/// lines below. When the line changes, everything slides up one row.
struct LyricsScroller: View {
    @ObservedObject var lyrics: LyricsModel
    var rows: Int
    var lineHeight: CGFloat
    var font: Font
    var currentOpacity: Double
    var upcomingOpacity: Double

    var body: some View {
        let current = lyrics.current
        VStack(spacing: 0) {
            // One row above the visible area so the outgoing line has
            // somewhere to slide to.
            ForEach((current - 1)...(current + rows), id: \.self) { index in
                let text = lyrics.text(at: index)
                let opacity = index == current ? currentOpacity : upcomingOpacity
                Group {
                    if let text { Text(text) } else { Text(Image(systemName: "music.note")) }
                }
                    .font(font)
                    .foregroundStyle(.white.opacity(text == nil ? opacity * 0.6 : opacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .scaleEffect(index == current ? 1 : 0.94)
                    .frame(maxWidth: .infinity)
                    .frame(height: lineHeight)
            }
        }
        .offset(y: -lineHeight)
        .frame(height: lineHeight * CGFloat(rows), alignment: .top)
        .clipped()
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: current)
    }
}
