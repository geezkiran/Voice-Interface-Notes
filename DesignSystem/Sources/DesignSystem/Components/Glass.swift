import SwiftUI

/// Liquid Glass primitives.
///
/// Everything here wraps Apple's own `glassEffect` rather than approximating
/// it with blurs and gradients — the material is doing the work, so the
/// system's job is only to say *where* glass is allowed and at what shape.
///
/// The rules this system holds itself to:
/// - Glass floats **over** content, never under it. A row, a card, or a form
///   field is never glass; a control that hovers above scrolling content is.
/// - Anything the user can drag a finger across gets `.interactive()`, so the
///   material reacts to touch the way system controls do.
/// - Neighbouring glass shapes live inside a single `GlassEffectContainer`,
///   which is what lets them blend and morph into one another instead of
///   reading as separate panes stacked on the same background.
/// - Tint is used at most once per screen, on the single most important
///   control — on Home that is the capture button, in `DSColor.captureTint`.
///   Everything else is clear glass.

// MARK: - Floating capture button

/// The single most important control in the app: the "get it out of your
/// head in under 3 seconds" button. It sits where Apple Notes puts its
/// compose button and wears the same yellow — but a level meter rather than a
/// plus, because it starts *listening*, not typing. Larger and centered,
/// because on Home there is exactly one thing to do.
public struct DSCaptureButton: View {
    /// Either an SF Symbol or one of the drawn paths — the resting glyph is a
    /// drawn level meter, but the states it toggles into (stop, pause) are
    /// symbols, and both have to look at home on the same disc.
    public enum Glyph {
        case symbol(String)
        case drawn(DSVectorIcon)
    }

    var size: CGFloat
    var glyph: Glyph
    /// Given when the symbol alone doesn't say what the button does — a
    /// pause/play toggle, say, where the label changes with the state.
    var label: String?
    var action: () -> Void

    /// The glyph as a fraction of the disc. Kept here, and public, so anything
    /// drawing its own circular action button lands on the same proportion
    /// rather than eyeballing a point size against this one.
    public static let glyphRatio: CGFloat = 0.44

    /// The same fraction for a drawn glyph. Larger than `glyphRatio` because
    /// the artwork keeps a 3-unit margin inside its 24-unit box — its frame has
    /// to be bigger for the ink inside to match a symbol's — but not the full
    /// 24/18 that margin implies: the bars are a solid block where a symbol is
    /// mostly air, so at parity they read heavier than the disc wants.
    public static let drawnGlyphRatio: CGFloat = glyphRatio / 0.85

    @State private var isPressed = false

    public init(
        size: CGFloat = 68,
        glyph: Glyph = .drawn(.levels),
        label: String? = nil,
        action: @escaping () -> Void
    ) {
        self.size = size
        self.glyph = glyph
        self.label = label
        self.action = action
    }

    public init(
        size: CGFloat = 68,
        symbol: String,
        label: String? = nil,
        action: @escaping () -> Void
    ) {
        self.init(size: size, glyph: .symbol(symbol), label: label, action: action)
    }

    public var body: some View {
        Button(action: action) {
            // Dark glyph, not white: yellow is a light tint, and white on it
            // fails contrast at this size. Held dark in dark mode too — the
            // disc stays yellow there, so the glyph's ink answers to the tint
            // rather than to the ground.
            glyphView
                .foregroundStyle(DSColor.onCaptureTint)
                .frame(width: size, height: size)
                // The whole disc is the target, not the glyph. A drawn glyph is
                // a stroked shape, and a stroked shape only hit-tests on its own
                // ink — without this, the level meter's five hairlines were the
                // only tappable part of a 60pt button.
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // 0.85 rather than a flat fill, so the material still refracts what
        // scrolls underneath instead of reading as a painted disc.
        .glassEffect(
            .regular.tint(DSColor.captureTint.opacity(0.85)).interactive(),
            in: .circle
        )
        .scaleEffect(isPressed ? 0.92 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(label ?? defaultLabel)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: size * Self.glyphRatio, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
        case let .drawn(vector):
            DSVectorIconView(vector, size: size * Self.drawnGlyphRatio, lineWidth: 2.2)
        }
    }

    private var defaultLabel: String {
        switch glyph {
        case .symbol("plus"), .drawn(.levels): "New capture"
        default: "Stop recording"
        }
    }
}

// MARK: - Glass icon button

/// A circular glass icon button — the untinted sibling of `DSCaptureButton`, for
/// the secondary affordances that sit next to it (search, filter, settings,
/// cancel). Clear glass, no tint: only one control per screen earns tint.
public struct DSGlassIconButtonStyle: ButtonStyle {
    var size: CGFloat

    public init(size: CGFloat = 44) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundStyle(DSColor.textPrimary)
            .frame(width: size, height: size)
            .glassEffect(.regular.interactive(), in: .circle)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == DSGlassIconButtonStyle {
    static var dsGlassIcon: DSGlassIconButtonStyle { DSGlassIconButtonStyle() }
    static func dsGlassIcon(size: CGFloat) -> DSGlassIconButtonStyle { DSGlassIconButtonStyle(size: size) }
}

// MARK: - Glass capsule bar

/// A floating pill that holds a row of controls — the filter row on Home,
/// the transport controls on Transcribing. Glass, capsule, always hovering
/// over scrolling content rather than pinned into the layout.
public struct DSGlassBar<Content: View>: View {
    var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Convenience

public extension View {
    /// Glass on a rounded rectangle at a system radius — for the occasional
    /// panel (the Transcribing screen's live-status header) that is neither a
    /// circle nor a capsule.
    func dsGlassPanel(cornerRadius: CGFloat = DSRadius.xl, interactive: Bool = false) -> some View {
        glassEffect(
            interactive ? .regular.interactive() : .regular,
            in: .rect(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
