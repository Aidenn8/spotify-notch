import SwiftUI

final class NotchState: ObservableObject {
    @Published var mode: NotchMode = .hidden
    @Published var geometry: NotchGeometry

    init(geometry: NotchGeometry) { self.geometry = geometry }
}

struct NotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var model: SpotifyModel
    var onQuit: () -> Void

    @Namespace private var ns

    var body: some View {
        let geo = state.geometry
        let mode = state.mode
        let size = geo.size(for: mode)
        let r = geo.radii(for: mode)
        let shape = NotchShape(topRadius: r.top, bottomRadius: r.bottom)

        shape
            .fill(Color.black)
            .overlay(alignment: .top) {
                content(mode: mode, geo: geo)
                    .padding(.horizontal, r.top)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipShape(shape)
            }
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(mode == .expanded ? 0.45 : 0), radius: 14, y: 6)
            .contextMenu {
                Button("Open Spotify") { model.openSpotify() }
                Divider()
                Button("Quit Spotify Notch", action: onQuit)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func content(mode: NotchMode, geo: NotchGeometry) -> some View {
        if let track = model.track {
            switch mode {
            case .hidden:
                Color.clear
            case .compact:
                compact(geo: geo)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            case .expanded:
                expanded(track: track, geo: geo)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
        }
    }

    // MARK: Compact — art in the left wing, visualizer in the right

    private func compact(geo: NotchGeometry) -> some View {
        HStack(spacing: 0) {
            ArtworkView(image: model.artwork, cornerRadius: 5)
                .matchedGeometryEffect(id: "art", in: ns)
                .frame(width: 20, height: 20)
            Spacer(minLength: 0)
            visualizer
        }
        .padding(.horizontal, 11)
        .frame(height: geo.notchHeight)
    }

    // MARK: Expanded

    private func expanded(track: Track, geo: NotchGeometry) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geo.notchHeight + 4)

            HStack(spacing: 12) {
                ArtworkView(image: model.artwork, cornerRadius: 10)
                    .matchedGeometryEffect(id: "art", in: ns)
                    .frame(width: 56, height: 56)
                    .onTapGesture { model.openSpotify() }
                    .help("Open Spotify")

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(track.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .lineLimit(1)
                .id(track.id)
                .transition(.opacity)

                Spacer(minLength: 8)
                visualizer
            }
            .frame(height: 56)

            ProgressRow(model: model)
                .padding(.top, 12)

            controls
                .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var visualizer: some View {
        Visualizer(playing: model.isPlaying, color: model.accent)
            .matchedGeometryEffect(id: "viz", in: ns)
            .frame(width: 18, height: 13)
    }

    private var controls: some View {
        let accent = Color(nsColor: model.accent)
        return HStack(spacing: 0) {
            IconButton(symbol: "shuffle", size: 13, active: model.shuffling, accent: accent,
                       action: model.toggleShuffle)
            Spacer()
            IconButton(symbol: "backward.fill", size: 16, action: model.previous)
            Spacer()
            IconButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", size: 22,
                       action: model.playPause)
            Spacer()
            IconButton(symbol: "forward.fill", size: 16, action: model.next)
            Spacer()
            IconButton(symbol: "repeat", size: 13, active: model.repeating, accent: accent,
                       action: model.toggleRepeat)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }
}

// MARK: - Pieces

struct ArtworkView: View {
    var image: NSImage?
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(Color.white.opacity(0.08))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .clipShape(shape)
    }
}

struct ProgressRow: View {
    @ObservedObject var model: SpotifyModel
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        // Ticks twice a second, and only exists while the panel is open.
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = max(model.track?.duration ?? 0, 1)
            let fraction = dragFraction ?? model.position(at: context.date) / duration
            let active = hovering || dragFraction != nil
            // Whole seconds on both sides so elapsed + remaining always adds up.
            let elapsed = (fraction * duration).rounded(.down)

            HStack(spacing: 10) {
                Text(Self.format(elapsed))
                    .frame(width: 34, alignment: .leading)

                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(Color.white.opacity(active ? 1 : 0.8))
                            .frame(width: g.size.width * fraction)
                    }
                    .frame(height: active ? 6 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            dragFraction = min(max(v.location.x / g.size.width, 0), 1)
                        }
                        .onEnded { _ in
                            if let f = dragFraction { model.seek(to: f * duration) }
                            dragFraction = nil
                        })
                }

                Text("-" + Self.format(duration.rounded(.down) - elapsed))
                    .frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
            .frame(height: 14)
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = max(Int(t.rounded(.down)), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct IconButton: View {
    var symbol: String
    var size: CGFloat
    var active: Bool? = nil   // nil = plain button, else a toggle
    var accent: Color = .white
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(foreground)
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.1 : 0)))
                .overlay(alignment: .bottom) {
                    if active == true {
                        Circle().fill(accent).frame(width: 3, height: 3).offset(y: -3)
                            .transition(.opacity)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.2), value: active)
    }

    private var foreground: Color {
        switch active {
        case .some(true): accent
        case .some(false): .white.opacity(0.4)
        case .none: .white
        }
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
