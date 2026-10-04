import AppKit
import SwiftUI

/// Background options for the open panel, chosen from the right-click menu.
/// The closed widget is always solid black so it blends with the notch.
enum PanelStyle: String, CaseIterable, Identifiable {
    case solid = "Solid Black"
    case smoky = "Smoky Glass"
    case frosted = "Frosted Glass"
    case clear = "Clear Glass"
    case tinted = "Album Tint"

    var id: String { rawValue }

    var isGlass: Bool { self != .solid }

    /// How dark the glass gets at the bottom of the panel (0 = just blur).
    var bottomDarkness: Double {
        switch self {
        case .solid: 1
        case .smoky: 0.6
        case .frosted: 0.2
        case .clear: 0.05
        case .tinted: 0.35
        }
    }

    /// Clear glass lets some of the unblurred background through.
    var blurOpacity: Double { self == .clear ? 0.55 : 1 }

    var shadowOpacity: Double { isGlass ? 0.2 : 0.45 }
}

struct PanelBackground: View {
    var style: PanelStyle
    var expanded: Bool
    var accent: Color
    var notchHeight: CGFloat
    var height: CGFloat

    var body: some View {
        let glass = style.isGlass && expanded
        // Keep a band around the physical notch (which is hardware and can't
        // be see-through) solid black, then fade into the glass, so the
        // camera housing doesn't look stuck on.
        let band = min(notchHeight / max(height, 1), 1)
        let dark = Color.black.opacity(style.bottomDarkness)
        ZStack {
            if style.isGlass {
                VisualEffectBlur().opacity(style.blurOpacity)
                if style == .tinted {
                    LinearGradient(colors: [accent.opacity(0.35), accent.opacity(0.15)],
                                   startPoint: .top, endPoint: .bottom)
                }
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: band),
                    .init(color: dark, location: min(band + 0.35, 1)),
                    .init(color: dark, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            // Solid black whenever closed (and for the solid style); fades out
            // as the panel opens to reveal the glass.
            Color.black.opacity(glass ? 0 : 1)
        }
    }
}

/// Dark behind-window blur. Kept "active" because the panel never becomes
/// the key window, which would otherwise grey the material out.
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
