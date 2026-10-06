import XCTest
@testable import SpotifyNotch

final class NotchGeometryTests: XCTestCase {
    /// A 13" MacBook Air at "More Space": 1710 x 1107 pt, 185 x 33 pt notch.
    let geo = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1710, height: 1107),
                            notchWidth: 185, notchHeight: 33, centerX: 855)

    func testHiddenTucksBehindTheNotch() {
        let size = geo.size(for: .hidden)
        XCTAssertLessThan(size.width, geo.notchWidth)
        XCTAssertLessThan(size.height, geo.notchHeight)
    }

    func testCompactAddsAWingOnEachSide() {
        let size = geo.size(for: .compact)
        let ears = 2 * geo.radii(for: .compact).top
        XCTAssertEqual(size.width, geo.notchWidth + 2 * NotchGeometry.wing + ears)
        XCTAssertEqual(size.height, geo.notchHeight)
    }

    func testModesGrowInOrder() {
        let sizes = [NotchMode.hidden, .compact, .expanded].map { geo.size(for: $0) }
        for (smaller, larger) in zip(sizes, sizes.dropFirst()) {
            XCTAssertLessThan(smaller.width, larger.width)
            XCTAssertLessThanOrEqual(smaller.height, larger.height)
        }
    }

    func testLyricsOnlyChangeTheOpenPanel() {
        XCTAssertEqual(geo.size(for: .compact, lyrics: true), geo.size(for: .compact))
        XCTAssertEqual(geo.size(for: .expanded, lyrics: true).height,
                       geo.size(for: .expanded).height + NotchGeometry.lyricsBlockHeight)
    }

    /// Every window shares one center and hangs from the top of the screen,
    /// so resizing between modes never shifts the notch sideways.
    func testWindowsShareCenterAndTop() {
        for mode in [NotchMode.hidden, .compact, .expanded] {
            for lyrics in [false, true] {
                let frame = geo.windowFrame(for: mode, lyrics: lyrics)
                XCTAssertEqual(frame.midX, geo.centerX, accuracy: 1e-9)
                XCTAssertEqual(frame.maxY, geo.screenFrame.maxY, accuracy: 1e-9)
                XCTAssertLessThanOrEqual(frame.width, geo.maxWindowSize.width)
                XCTAssertLessThanOrEqual(frame.height, geo.maxWindowSize.height)
            }
        }
    }

    func testShapeStaysInsideItsRect() {
        let rect = CGRect(x: 10, y: 20, width: 424, height: 225)
        for mode in [NotchMode.hidden, .compact, .expanded] {
            let r = geo.radii(for: mode)
            let bounds = NotchShape(topRadius: r.top, bottomRadius: r.bottom).path(in: rect).boundingRect
            XCTAssertEqual(bounds.minX, rect.minX, accuracy: 0.01)
            XCTAssertEqual(bounds.maxX, rect.maxX, accuracy: 0.01)
            XCTAssertEqual(bounds.minY, rect.minY, accuracy: 0.01)
            XCTAssertEqual(bounds.maxY, rect.maxY, accuracy: 0.01)
        }
    }

    func testRadiiClampForTinyRects() {
        // Larger radii than the rect allows must not produce a broken path.
        let rect = CGRect(x: 0, y: 0, width: 20, height: 8)
        let bounds = NotchShape(topRadius: 12, bottomRadius: 24).path(in: rect).boundingRect
        XCTAssertTrue(rect.insetBy(dx: -0.01, dy: -0.01).contains(bounds))
    }
}
