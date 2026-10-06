// Records the README demo (GIF + MP4) and screenshots.
//
// The real widget (NotchView in --demo mode) is rendered in an off-screen
// window, so recording never touches the actual notch or the pointer. A
// scripted sequence plays (hover open, skip to a song with lyrics, close),
// and every frame of that window is composited onto a drawn MacBook bezel,
// menu bar and notch, with a cursor showing what the "user" is doing.
//
// Build and run with tools/record-demo.sh.

import AppKit
import AVFoundation
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/media", isDirectory: true)
let fps = 30.0
let scale: CGFloat = 2

// MARK: Scene

/// A 13" MacBook Air at its default scaling has a 185 x 33 pt notch; use the
/// real one when recording on a notched Mac.
let geometry: NotchGeometry = {
    let real = NotchGeometry.detect()
    let notched = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    let width = notched ? real.notchWidth : 185
    let height = notched ? real.notchHeight : 33
    return NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1710, height: 1107),
                         notchWidth: width, notchHeight: height, centerX: 855)
}()

let bezel: CGFloat = 14                       // laptop frame above the screen
let canvas = CGSize(width: 640, height: 290)  // points
let cx = canvas.width / 2
let windowSize = geometry.maxWindowSize

// MARK: Widget

NSApplication.shared.setActivationPolicy(.accessory)
let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                     reason: "Recording the demo")

let state = NotchState(geometry: geometry)
state.style = .solid
let model = SpotifyModel(demo: true)
let lyrics = LyricsModel(spotify: model, demo: true)
var cancellables = Set<AnyCancellable>()

let host = NSHostingView(rootView: NotchView(state: state, model: model, lyrics: lyrics, onQuit: {}))
host.sizingOptions = []
let container = PinnedContainerView(content: host, size: windowSize)
let panel = NotchPanel()
panel.contentView = container
// Far off every screen: rendered and capturable, but never seen.
panel.setFrame(NSRect(x: -20000, y: -20000, width: windowSize.width, height: windowSize.height),
               display: true)
panel.orderFrontRegardless()

/// Mirrors NotchController.updateLayout without the window resizing.
func setMode(_ mode: NotchMode) {
    let old = state.mode
    lyrics.visible = mode == .expanded
    withAnimation(NotchController.animation(from: old, to: mode)) { state.mode = mode }
}

lyrics.$showing.removeDuplicates()
    .sink { showing in
        DispatchQueue.main.async {
            withAnimation(NotchController.animation(from: state.mode, to: state.mode)) {
                state.lyricsLayout = showing
            }
        }
    }
    .store(in: &cancellables)

// MARK: Script

/// Cursor stops (top-left origin, canvas points). The next button follows
/// from NotchView's layout: the open panel is 424 pt wide, its controls row
/// is inset 46 pt and spreads five 34 pt buttons over 332 pt, and the row's
/// center is 142 pt below the top of the screen.
let screenTop = bezel
let rest = CGPoint(x: cx + 252, y: screenTop + 206)
let notch = CGPoint(x: cx + 14, y: screenTop + 15)
let nextButton = CGPoint(x: cx + 75, y: screenTop + 142)
let aside = CGPoint(x: cx + 180, y: screenTop + 212)

struct Move { let start, end: Double; let from, to: CGPoint }
let moves = [
    Move(start: 1.2, end: 2.15, from: rest, to: notch),
    Move(start: 3.3, end: 4.05, from: notch, to: nextButton),
    Move(start: 4.75, end: 5.35, from: nextButton, to: aside),
    Move(start: 10.0, end: 10.6, from: aside, to: rest),
]
let clickTime = 4.3
let duration = 13.4

var events: [(time: Double, run: () -> Void)] = [
    (2.23, { setMode(.expanded) }),
    // The lyrics song starts 1.7 s before its next line, so two lines go
    // by while the panel is open.
    (clickTime, { model.next() }),
    (10.25, { setMode(.compact) }),
    (12.0, { model.previous() }),
]

/// Stills, captured without the cursor: (name, time, crop in canvas points).
let stills: [(name: String, time: Double, crop: CGRect)] = [
    ("compact", 0.8, CGRect(x: cx - 190, y: 0, width: 380, height: screenTop + 62)),
    ("expanded", 3.1, CGRect(x: cx - 260, y: 0, width: 520, height: screenTop + 196)),
    ("lyrics", 8.2, CGRect(x: cx - 260, y: 0, width: 520, height: screenTop + 250)),
]

func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }

func cursorPosition(at t: Double) -> CGPoint {
    var p = rest
    for m in moves {
        if t >= m.end { p = m.to; continue }
        if t > m.start {
            let f = CGFloat(ease((t - m.start) / (m.end - m.start)))
            return CGPoint(x: m.from.x + (m.to.x - m.from.x) * f, y: m.from.y + (m.to.y - m.from.y) * f)
        }
        break
    }
    return p
}

// MARK: Drawing

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let pixelSize = CGSize(width: canvas.width * scale, height: canvas.height * scale)

func makeContext() -> CGContext {
    let ctx = CGContext(data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height),
                        bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Top-left origin in points, like the layout numbers above.
    ctx.translateBy(x: 0, y: pixelSize.height)
    ctx.scaleBy(x: scale, y: -scale)
    return ctx
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Wallpaper, menu bar, laptop bezel and the physical notch.
let backdrop: CGImage = {
    let ctx = makeContext()
    let screen = CGRect(x: 0, y: screenTop, width: canvas.width, height: canvas.height - screenTop)
    let wallpaper = CGGradient(colorsSpace: sRGB, colors: [color(0x2a3170), color(0x45367a), color(0x5c3a78)] as CFArray,
                               locations: [0, 0.55, 1])!
    ctx.saveGState()
    ctx.clip(to: screen)
    ctx.drawLinearGradient(wallpaper, start: CGPoint(x: 0, y: screenTop),
                           end: CGPoint(x: canvas.width, y: canvas.height), options: [])
    // Menu bar: a slightly darker band, as high as the notch.
    ctx.setFillColor(color(0x000000, 0.18))
    ctx.fill(CGRect(x: 0, y: screenTop, width: canvas.width, height: geometry.notchHeight))
    ctx.restoreGState()

    ctx.setFillColor(color(0x050505))
    ctx.fill(CGRect(x: 0, y: 0, width: canvas.width, height: screenTop))

    let notchRect = CGRect(x: cx - geometry.notchWidth / 2 - 3, y: screenTop - 1,
                           width: geometry.notchWidth + 6, height: geometry.notchHeight + 1)
    ctx.saveGState()
    // NotchShape draws in a flipped (top-down) rect, which this context is.
    ctx.addPath(NotchShape(topRadius: 3, bottomRadius: 9).path(in: notchRect).cgPath)
    ctx.setFillColor(color(0x050505))
    ctx.fillPath()
    ctx.restoreGState()
    return ctx.makeImage()!
}()

let cursorImage: CGImage? = {
    let arrow = NSCursor.arrow.image
    var rect = CGRect(origin: .zero, size: arrow.size)
    return arrow.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
}()
let cursorSize = NSCursor.arrow.image.size
let cursorHotSpot = NSCursor.arrow.hotSpot

func compose(_ widget: CGImage?, cursor: CGPoint?, click: Double?) -> CGImage {
    let ctx = makeContext()
    ctx.saveGState()
    // CGImages draw upright in an unflipped space, so flip locally.
    ctx.translateBy(x: 0, y: canvas.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(backdrop, in: CGRect(origin: .zero, size: canvas))
    if let widget {
        let rect = CGRect(x: cx - windowSize.width / 2, y: canvas.height - screenTop - windowSize.height,
                          width: windowSize.width, height: windowSize.height)
        ctx.draw(widget, in: rect)
    }
    ctx.restoreGState()

    if let cursor {
        if let click, click >= 0, click < 0.45 {
            // A fading ring where the click lands, as screen recorders show.
            let f = CGFloat(click / 0.45)
            let r = 9 + 10 * f
            ctx.setStrokeColor(color(0xffffff, 0.75 * (1 - f)))
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: cursor.x - r, y: cursor.y - r, width: 2 * r, height: 2 * r))
        }
        if let cursorImage {
            ctx.saveGState()
            let rect = CGRect(x: cursor.x - cursorHotSpot.x, y: cursor.y - cursorHotSpot.y,
                              width: cursorSize.width, height: cursorSize.height)
            ctx.translateBy(x: 0, y: rect.midY * 2)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cursorImage, in: rect)
            ctx.restoreGState()
        }
    }
    return ctx.makeImage()!
}

func captureWidget() -> CGImage? {
    CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(panel.windowNumber),
                            [.boundsIgnoreFraming, .bestResolution])
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: Encoders

final class VideoWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var frame: Int64 = 0

    init(url: URL, size: CGSize) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000,
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CGImage) {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        guard let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: CMTimeScale(fps)))
        frame += 1
    }

    func finish(_ done: @escaping () -> Void) {
        input.markAsFinished()
        writer.finishWriting(completionHandler: done)
    }
}

// MARK: Recording

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let framesDir = FileManager.default.temporaryDirectory.appendingPathComponent("spotify-notch-frames", isDirectory: true)
try? FileManager.default.removeItem(at: framesDir)
try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

let encodeQueue = DispatchQueue(label: "encode")
let video = try VideoWriter(url: outDir.appendingPathComponent("demo.mp4"), size: pixelSize)
var frameIndex = 0
var pendingStills = stills
var start: Date?

func tick(_ timer: Timer) {
    guard let start else { return }
    let t = Date().timeIntervalSince(start)
    while let next = events.first, next.time <= t {
        events.removeFirst()
        next.run()
    }
    guard t <= duration else {
        timer.invalidate()
        finishRecording()
        return
    }
    // Frames are numbered by their slot, so a late tick still lands on time.
    let slot = Int((t * fps).rounded())
    guard slot >= frameIndex else { return }
    frameIndex = slot + 1

    let widget = captureWidget()
    let cursor = cursorPosition(at: t)
    let click = t - clickTime
    encodeQueue.async {
        let frame = compose(widget, cursor: cursor, click: click)
        writePNG(frame, to: framesDir.appendingPathComponent(String(format: "%04d.png", slot)))
    }
    while let still = pendingStills.first, still.time <= t {
        pendingStills.removeFirst()
        encodeQueue.async {
            let crop = still.crop.applying(CGAffineTransform(scaleX: scale, y: scale))
            if let image = compose(widget, cursor: nil, click: nil).cropping(to: crop) {
                writePNG(image, to: outDir.appendingPathComponent("\(still.name).png"))
            }
        }
    }
}

func finishRecording() {
    encodeQueue.async {
        // Fill any dropped slots with the frame before, then encode in order.
        let files = (try? FileManager.default.contentsOfDirectory(atPath: framesDir.path))?.sorted() ?? []
        let last = files.compactMap { Int($0.prefix(4)) }.max() ?? 0
        func load(_ i: Int) -> CGImage? {
            let url = framesDir.appendingPathComponent(String(format: "%04d.png", i))
            return CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        }
        let first = files.compactMap { Int($0.prefix(4)) }.min() ?? 0
        var previous = load(first)
        var frames: [CGImage] = []
        for i in 0...last {
            if let image = load(i) { previous = image }
            if let previous { frames.append(previous) }
        }
        frames.forEach(video.append)
        writeGIF(frames, to: outDir.appendingPathComponent("demo.gif"))
        video.finish {
            print("recorded \(frames.count) frames to \(outDir.path)")
            print("frames: \(framesDir.path)")
            UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
            ProcessInfo.processInfo.endActivity(activity)
            exit(0)
        }
    }
}

func writeGIF(_ frames: [CGImage], to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                     frames.count, nil) else { return }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (i, frame) in frames.enumerated() {
        // Centiseconds that add up to exactly 1/fps per frame on average.
        let delay = (Double(i + 1) * 100 / fps).rounded() - (Double(i) * 100 / fps).rounded()
        CGImageDestinationAddImage(dest, frame, [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFDelayTime: delay / 100]] as CFDictionary)
    }
    CGImageDestinationFinalize(dest)
}

// Pre-roll: open on the amber song, already in the notch, lyrics turned on.
model.previous()
lyrics.enabled = true
state.mode = .compact
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    start = Date()
    let timer = Timer(timeInterval: 1 / fps / 2, repeats: true, block: tick)
    RunLoop.main.add(timer, forMode: .common)
}
NSApplication.shared.run()
