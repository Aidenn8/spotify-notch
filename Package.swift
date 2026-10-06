// swift-tools-version:5.9
// For `swift test` and for opening the project in Xcode. The app bundle
// itself is built by build.sh.
import PackageDescription

let package = Package(
    name: "SpotifyNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SpotifyNotch", path: "Sources"),
        .executableTarget(name: "SpotifyNotchWatcher", path: "Watcher"),
        .testTarget(name: "SpotifyNotchTests", dependencies: ["SpotifyNotch"], path: "Tests"),
    ]
)
