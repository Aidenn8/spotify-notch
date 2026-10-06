import XCTest
@testable import SpotifyNotch

final class LyricsParsingTests: XCTestCase {
    func testParsesTimestamps() {
        let lines = LyricsFetcher.parse("[00:12.50] First line\n[01:02.05]Second line")
        XCTAssertEqual(lines, [LyricLine(time: 12.5, text: "First line"),
                               LyricLine(time: 62.05, text: "Second line")])
    }

    func testRepeatedLineWithSeveralTimestamps() {
        let lines = LyricsFetcher.parse("[00:10.00][00:30.00] Chorus\n[00:20.00] Verse")
        XCTAssertEqual(lines.map(\.time), [10, 20, 30])
        XCTAssertEqual(lines.map(\.text), ["Chorus", "Verse", "Chorus"])
    }

    func testKeepsEmptyLinesAsGaps() {
        let lines = LyricsFetcher.parse("[00:01.00] Hello\n[00:05.00]\n[00:09.00] Again")
        XCTAssertEqual(lines.map(\.text), ["Hello", "", "Again"])
    }

    func testIgnoresTagsAndUntimedText() {
        let lrc = "[ar: Some Artist]\n[ti: Some Title]\nno timestamp\n[00:03] Whole seconds"
        XCTAssertEqual(LyricsFetcher.parse(lrc), [LyricLine(time: 3, text: "Whole seconds")])
    }

    func testHandlesWindowsLineEndings() {
        let lines = LyricsFetcher.parse("[00:01.00] One\r\n[00:02.00] Two\r\n")
        XCTAssertEqual(lines.map(\.text), ["One", "Two"])
    }

    func testCleansTitlesForSearch() {
        XCTAssertEqual(LyricsFetcher.cleaned("Song (Live) - Remastered 2011"), "Song")
        XCTAssertEqual(LyricsFetcher.cleaned("Song [feat. Someone]"), "Song")
        XCTAssertEqual(LyricsFetcher.cleaned("Plain Title"), "Plain Title")
    }
}

final class LyricsTimingTests: XCTestCase {
    /// Lets the main queue run the work LyricsModel schedules on it.
    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    func testFollowsPlaybackPosition() throws {
        let spotify = SpotifyModel(demo: true)
        let lyrics = LyricsModel(spotify: spotify, demo: true)
        lyrics.enabled = true
        lyrics.visible = true
        settle()

        XCTAssertEqual(lyrics.status, .found)
        XCTAssertTrue(lyrics.showing)
        // The first demo track starts at 68.5 s; the line from 67 s is on.
        XCTAssertEqual(lyrics.text(at: lyrics.current), "We keep driving with the radio on")

        // Lines change 0.3 s early, so the scroll lands on time.
        spotify.seek(to: 73.8)
        XCTAssertEqual(lyrics.lines[lyrics.current].time, 74)
        spotify.seek(to: 10)
        XCTAssertEqual(lyrics.current, -1)
        XCTAssertNil(lyrics.text(at: -1), "before the first line shows a music note")
    }

    func testTrackWithoutLyricsMakesNoRoom() {
        let spotify = SpotifyModel(demo: true)
        let lyrics = LyricsModel(spotify: spotify, demo: true)
        lyrics.enabled = true
        settle()
        XCTAssertTrue(lyrics.showing)

        spotify.next()  // an instrumental
        settle()
        XCTAssertEqual(lyrics.status, .missing)
        XCTAssertFalse(lyrics.showing)
    }

    func testOffUnlessEnabled() {
        let spotify = SpotifyModel(demo: true)
        let lyrics = LyricsModel(spotify: spotify, demo: true)
        settle()
        XCTAssertEqual(lyrics.status, .off)
        XCTAssertFalse(lyrics.showing)
    }
}
