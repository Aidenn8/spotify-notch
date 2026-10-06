import AppKit
import XCTest
@testable import SpotifyNotch

final class AccentColorTests: XCTestCase {
    private func solid(_ color: NSColor) -> CGImage {
        let ctx = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return ctx.makeImage()!
    }

    private func luminance(_ color: NSColor) -> CGFloat {
        let c = color.usingColorSpace(.sRGB)!
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }

    func testGreyCoverFallsBackToSoftWhite() {
        let accent = Artwork.accent(from: solid(NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)))
        XCTAssertEqual(accent, SpotifyModel.fallbackAccent)
    }

    func testPicksTheCoverHue() {
        let accent = Artwork.accent(from: solid(NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)))
            .usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(accent.redComponent, accent.greenComponent)
        XCTAssertGreaterThan(accent.redComponent, accent.blueComponent)
    }

    func testDarkHuesAreLiftedToReadOnBlack() {
        let deepBlue = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.7, alpha: 1)
        XCTAssertLessThan(luminance(deepBlue), 0.2)
        let accent = Artwork.accent(from: solid(deepBlue))
        XCTAssertGreaterThanOrEqual(luminance(accent), 0.54)
        let rgb = accent.usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(rgb.blueComponent, rgb.redComponent, "still reads as blue")
    }
}

final class PlayerTests: XCTestCase {
    func testTimeFormatting() {
        XCTAssertEqual(ProgressRow.format(0), "0:00")
        XCTAssertEqual(ProgressRow.format(61.9), "1:01")
        XCTAssertEqual(ProgressRow.format(3600), "60:00")
        XCTAssertEqual(ProgressRow.format(-3), "0:00")
    }

    func testDemoNextAndPreviousWrapAround() {
        let model = SpotifyModel(demo: true)
        let ids = DemoTrack.all.map(\.track.id)
        XCTAssertEqual(model.track?.id, ids[0])
        model.next()
        XCTAssertEqual(model.track?.id, ids[1])
        model.previous()
        model.previous()
        XCTAssertEqual(model.track?.id, ids.last)
        XCTAssertNotNil(model.artwork)
    }

    func testPositionIsExtrapolatedAndClamped() {
        let model = SpotifyModel(demo: true)
        let start = DemoTrack.all[0].start
        let now = Date()
        XCTAssertEqual(model.position(at: now), start, accuracy: 0.5)
        XCTAssertEqual(model.position(at: now.addingTimeInterval(10)), start + 10, accuracy: 0.5)
        XCTAssertEqual(model.position(at: now.addingTimeInterval(1e6)), model.track!.duration)

        model.playPause()  // pause: the position stops moving
        let paused = model.position(at: Date())
        XCTAssertEqual(model.position(at: Date().addingTimeInterval(30)), paused, accuracy: 1e-9)
    }

    func testDemoDataIsWellFormed() {
        let ids = DemoTrack.all.map(\.track.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for demo in DemoTrack.all {
            XCTAssertEqual(demo.lyrics.map(\.time), demo.lyrics.map(\.time).sorted())
            XCTAssertLessThan(demo.start, demo.track.duration)
        }
    }
}
