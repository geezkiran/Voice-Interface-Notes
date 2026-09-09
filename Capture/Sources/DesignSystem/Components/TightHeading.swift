import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A large multi-line heading with real control over its line height.
///
/// Why this exists rather than a plain `Text`: SwiftUI's `lineSpacing` only
/// ever *adds* leading. A negative value is clamped to zero, so the usual
/// trick for tightening a display heading (`.lineSpacing(-14)`) silently does
/// nothing no matter how large the number gets — and it also leaves the text
/// measured shorter than it draws, which is what makes a two-line heading get
/// truncated when the view below it grows. `Font.leading(.tight)` is the only
/// supported lever and it stops well short of the leading a 34pt heading
/// wants.
///
/// So the heading is drawn by a `UILabel`, where the line box is set outright
/// through a paragraph style and the height is reported back to SwiftUI
/// exactly — tight lines, and never a clipped one.
public struct DSTightHeading: View {
    /// Which family the heading is set in. The serif is the same face the
    /// title tabs use, for the headings that read as a page's masthead rather
    /// than as a label on a control.
    public enum Face {
        case system
        case serif
    }

    var text: String
    var size: CGFloat
    var weight: Font.Weight
    /// Line box as a fraction of the font's natural line height. Below 1 the
    /// lines pull together; 1.0 is the font's own leading.
    var lineHeightMultiple: CGFloat
    var tracking: CGFloat
    var color: Color
    var face: Face

    public init(
        _ text: String,
        size: CGFloat = 34,
        weight: Font.Weight = .semibold,
        lineHeightMultiple: CGFloat = DSFont.tightHeadingLineHeight,
        tracking: CGFloat = -0.3,
        color: Color = DSColor.textPrimary,
        face: Face = .system
    ) {
        self.text = text
        self.size = size
        self.weight = weight
        self.lineHeightMultiple = lineHeightMultiple
        self.tracking = tracking
        self.color = color
        self.face = face
    }

    public var body: some View {
        #if canImport(UIKit)
        TightLabel(
            text: text,
            size: size,
            weight: weight.uiKitWeight,
            lineHeightMultiple: lineHeightMultiple,
            tracking: tracking,
            color: UIColor(color),
            face: face
        )
        // The label reports its own wrapped height; taking it as fixed keeps a
        // tall neighbour from proposing less and clipping a line off.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
        #else
        // The macOS gallery only has to render something reasonable; the
        // tightest leading AppKit-side SwiftUI offers is `.tight`.
        Text(text)
            .font(
                face == .serif
                    ? DSFont.serif(size: size, weight: weight)
                    : .system(size: size, weight: weight).leading(.tight)
            )
            .tracking(tracking)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
        #endif
    }
}

#if canImport(UIKit)

private struct TightLabel: UIViewRepresentable {
    var text: String
    var size: CGFloat
    var weight: UIFont.Weight
    var lineHeightMultiple: CGFloat
    var tracking: CGFloat
    var color: UIColor
    var face: DSTightHeading.Face

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        // Zero lines and word wrapping: the heading is as tall as the text
        // makes it, at any length, and there is no line count at which it
        // starts dropping words into an ellipsis.
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.backgroundColor = .clear
        // A tightened line box is smaller than the glyphs' own extent, so the
        // first line's ascenders and the last line's descenders sit outside
        // it. `sizeThatFits` hands that overflow back as extra height, and
        // this makes sure nothing is cut off in the meantime.
        label.clipsToBounds = false
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = attributedText
    }

    /// The height is always whatever the wrapped text needs — the proposal's
    /// height is never consulted, so a cramped proposal can't shorten the
    /// heading into a truncated one. Every line the text wraps to is measured
    /// and reported, however many that is.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        let proposedWidth = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let fitted = label.sizeThatFits(
            CGSize(width: proposedWidth ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        )
        // The measured height counts the tightened line boxes only. Ink that
        // spills past the first and last of them — which is exactly what
        // tightening buys — needs room of its own, or the ascenders on line
        // one meet the control above and the descenders on the last line get
        // shaved. UILabel centers its text in a taller box, so the extra
        // splits evenly top and bottom, which is where the spill is.
        return CGSize(
            width: proposedWidth ?? ceil(fitted.width),
            height: ceil(fitted.height) + inkOverflow
        )
    }

    /// How far the glyphs reach beyond the line box the paragraph style
    /// clamps them to. Zero once the box is at or above the font's own
    /// leading — nothing spills out of a line box that was never tightened.
    private var inkOverflow: CGFloat {
        let font = resolvedFont
        return max(0, (font.lineHeight - lineHeight(for: font)).rounded(.up))
    }

    private func lineHeight(for font: UIFont) -> CGFloat {
        (font.lineHeight * lineHeightMultiple).rounded()
    }

    private var attributedText: NSAttributedString {
        let font = resolvedFont
        let lineHeight = lineHeight(for: font)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: tracking,
            .paragraphStyle: paragraph,
            // Shrinking the line box leaves the glyphs sitting high inside it,
            // because the baseline doesn't move with it. This recentres them.
            .baselineOffset: (lineHeight - font.lineHeight) / 4
        ]

        // The serif ships one regular face and no weight axis, so weight has
        // to be faked the same way SwiftUI fakes it for `.custom(...).weight()`:
        // a stroke of the fill color, widening every stem. Negative width means
        // "stroke *and* fill" — a positive one would draw an outline.
        if let stroke = syntheticStrokeWidth {
            attributes[.strokeWidth] = stroke
            attributes[.strokeColor] = color
        }

        return NSAttributedString(string: text, attributes: attributes)
    }

    private var resolvedFont: UIFont {
        guard face == .serif else { return UIFont.systemFont(ofSize: size, weight: weight) }
        DSFont.registerSerif()
        // A missing face would otherwise fail silently as `nil`; falling back
        // to the system font keeps the heading readable rather than blank.
        return UIFont(name: DSFont.serifName, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: weight)
    }

    private var syntheticStrokeWidth: CGFloat? {
        guard face == .serif else { return nil }
        switch weight {
        case .medium: return -1.0
        case .semibold: return -1.6
        case .bold: return -2.2
        case .heavy, .black: return -3.0
        default: return nil
        }
    }
}

private extension Font.Weight {
    var uiKitWeight: UIFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

#endif
