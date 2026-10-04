import AppKit

// Private SkyLight/CoreGraphics calls. A window that lives only in a space of
// our own, raised above the regular desktop and fullscreen spaces, isn't part
// of the Spaces swipe animation: it stays glued to the notch the way the menu
// bar does, and fullscreen apps can't slide over it.
private typealias CGSConnectionID = Int32
private typealias CGSSpaceID = UInt64

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ cid: CGSConnectionID, _ flag: Int, _ options: NSDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceDestroy")
private func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)
@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int32) -> Int32
@_silgen_name("CGSSpaceGetAbsoluteLevel")
private func CGSSpaceGetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID) -> Int32
@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)
@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)
@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ windows: CFArray) -> CFArray?
@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: CFArray)
@_silgen_name("CGSHideSpaces")
private func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: CFArray)

final class StickySpace {
    // Regular desktops and fullscreen spaces sit at level 0. The window server
    // silently ignores levels above 749 (they read back as 0), so stay well
    // inside the accepted range.
    private static let level: Int32 = 500
    private static let userSpacesMask: Int32 = 0x7

    private let connection = _CGSDefaultConnection()
    private let space: CGSSpaceID

    init() {
        space = CGSSpaceCreate(connection, 0x1, nil)
        _ = CGSSpaceSetAbsoluteLevel(connection, space, Self.level)
        if CGSSpaceGetAbsoluteLevel(connection, space) != Self.level {
            NSLog("Spotify Notch: couldn't raise the notch space; it may slide with Spaces")
        }
        CGSShowSpaces(connection, [NSNumber(value: space)] as CFArray)
    }

    deinit {
        CGSHideSpaces(connection, [NSNumber(value: space)] as CFArray)
        CGSSpaceDestroy(connection, space)
    }

    /// Moves the window into the sticky space and out of every regular
    /// desktop, so no copy of it takes part in the swipe animation.
    func add(_ window: NSWindow) {
        let windows = [NSNumber(value: Int32(window.windowNumber))] as CFArray
        CGSAddWindowsToSpaces(connection, windows, [NSNumber(value: space)] as CFArray)
        if let others = CGSCopySpacesForWindows(connection, Self.userSpacesMask, windows),
           CFArrayGetCount(others) > 0 {
            CGSRemoveWindowsFromSpaces(connection, windows, others)
        }
    }
}
