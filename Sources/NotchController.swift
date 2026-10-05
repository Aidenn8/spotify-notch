import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        // Spaces membership is handled by StickySpace, not canJoinAllSpaces.
        collectionBehavior = [.stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that reports hover over a top-centered zone matching the
/// visible notch shape (not the whole window, which briefly stays large
/// while the panel animates closed), and accepts clicks without first
/// activating the app.
final class HoverHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    var hoverSize: CGSize = .zero {
        didSet { if hoverSize != oldValue { updateTrackingAreas() } }
    }
    private var trackingArea: NSTrackingArea?

    private var hoverRect: NSRect {
        NSRect(x: (bounds.width - hoverSize.width) / 2,
               y: isFlipped ? 0 : bounds.height - hoverSize.height,
               width: hoverSize.width, height: hoverSize.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = nil
        guard hoverSize != .zero, let window else { return }

        let rect = hoverRect
        let inside = rect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        // If the pointer is already in the zone, start in the "inside" state so
        // leaving it reliably produces an exit.
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        if inside { options.insert(.assumeInside) }
        let area = NSTrackingArea(rect: rect, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        if inside { onHover?(true) }
    }

    // SwiftUI's own hover regions (buttons, progress bar) deliver their
    // enter/exit events here too, so only react to our zone's tracking area.
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === trackingArea { onHover?(true) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === trackingArea { onHover?(false) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Holds the hosting view at a fixed size (as big as the panel ever gets),
/// pinned top-center, while the window around it grows and shrinks. SwiftUI
/// never sees a size change, so resizing the window can't shift the notch or
/// get swept into the open animation (which made it slide in from the left).
final class PinnedContainerView: NSView {
    let content: NSView
    var contentSize: CGSize { didSet { pin() } }

    init(content: NSView, size: CGSize) {
        self.content = content
        self.contentSize = size
        super.init(frame: .zero)
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Runs synchronously whenever the window resizes, before anything draws.
    override func resizeSubviews(withOldSize oldSize: NSSize) { pin() }
    override func layout() { super.layout(); pin() }

    private func pin() {
        content.frame = NSRect(x: (bounds.width - contentSize.width) / 2,
                               y: bounds.height - contentSize.height,
                               width: contentSize.width, height: contentSize.height)
    }
}

/// Owns the panel and decides which mode it's in. The window is only ever as
/// big as the current mode needs, so it never blocks clicks on the menu bar
/// or the apps underneath.
final class NotchController {
    private let panel = NotchPanel()
    private let host: HoverHostingView<NotchView>
    private let container: PinnedContainerView
    private let sticky = StickySpace()
    private let state = NotchState(geometry: .detect())
    private let model: SpotifyModel
    private let lyrics: LyricsModel
    private let pinExpanded: Bool

    private var hasTrack = false
    private var hovering = false
    private var lyricsShowing = false
    private var hoverWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(demo: Bool, pinExpanded: Bool) {
        model = SpotifyModel(demo: demo)
        lyrics = LyricsModel(spotify: model, demo: demo)
        self.pinExpanded = pinExpanded

        host = HoverHostingView(rootView: NotchView(state: state, model: model, lyrics: lyrics,
                                                    onQuit: { NSApp.terminate(nil) }))
        host.sizingOptions = []
        container = PinnedContainerView(content: host, size: state.geometry.maxWindowSize)
        host.onHover = { [weak self] in self?.hoverChanged($0) }
        panel.contentView = container
        panel.setFrame(state.geometry.windowFrame(for: .hidden), display: false)
        sticky.add(panel)

        // @Published emits before the property changes, so use the emitted value.
        model.$track.combineLatest(model.$ready)
            .map { track, ready in track != nil && ready }
            .removeDuplicates()
            .sink { [weak self] in self?.hasTrack = $0; self?.updateLayout() }
            .store(in: &cancellables)

        state.$lyricsEnabled
            .sink { [weak self] in self?.lyrics.enabled = $0 }
            .store(in: &cancellables)
        lyrics.$showing
            .removeDuplicates()
            .sink { [weak self] in self?.lyricsShowing = $0; self?.updateLayout() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.screensChanged() }
    }

    private var desiredMode: NotchMode {
        guard hasTrack else { return .hidden }
        return hovering || pinExpanded ? .expanded : .compact
    }

    private func hoverChanged(_ inside: Bool) {
        hoverWork?.cancel()
        guard inside else {
            // Close the moment the pointer leaves. updateLayout also shrinks the
            // hover zone back to the notch strip, the only place that opens it.
            hovering = false
            updateLayout()
            return
        }
        // A short delay in, so brushing past the top of the screen doesn't
        // pop it open.
        let work = DispatchWorkItem { [weak self] in
            self?.hovering = true
            self?.updateLayout()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// Moves to the wanted mode and lyrics layout. The window first grows to
    /// fit both the old and new shapes, the shape animates, and the window is
    /// trimmed to the new shape afterwards.
    private func updateLayout() {
        let newMode = desiredMode
        let newLyrics = lyricsShowing
        let oldMode = state.mode
        guard newMode != oldMode || newLyrics != state.lyricsLayout else { return }
        shrinkWork?.cancel()

        // Spotify doesn't announce shuffle/repeat changes, so re-read them on open.
        if newMode == .expanded && oldMode != .expanded { model.refresh() }
        // Lyrics only show in the open panel; their timers pause otherwise.
        lyrics.visible = newMode == .expanded

        let geo = state.geometry
        let target = geo.windowFrame(for: newMode, lyrics: newLyrics)
        panel.setFrame(panel.frame.union(target), display: true)
        if newMode != .hidden {
            panel.orderFrontRegardless()
            sticky.add(panel)
        }
        // Set right away so the space a closing panel leaves can't reopen it.
        host.hoverSize = newMode == .hidden ? .zero : geo.size(for: newMode, lyrics: newLyrics)

        let animation: Animation = newMode > oldMode ? .spring(response: 0.42, dampingFraction: 0.8)
            : newMode < oldMode ? .spring(response: 0.36, dampingFraction: 0.92)
            : .spring(response: 0.4, dampingFraction: 0.9)
        withAnimation(animation) {
            state.mode = newMode
            state.lyricsLayout = newLyrics
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.setFrame(target, display: true)
            if newMode == .hidden { self.panel.orderOut(nil) }
        }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func screensChanged() {
        let geo = NotchGeometry.detect()
        guard geo != state.geometry else { return }
        state.geometry = geo
        container.contentSize = geo.maxWindowSize
        panel.setFrame(geo.windowFrame(for: state.mode, lyrics: state.lyricsLayout), display: true)
        host.hoverSize = state.mode == .hidden ? .zero : geo.size(for: state.mode, lyrics: state.lyricsLayout)
    }
}
