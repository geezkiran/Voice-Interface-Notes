import SwiftUI

/// A pill-shaped tag/toggle — category tags on a Home row, the filter row,
/// an item's type picker in Editing.
///
/// Outlined rather than filled: a chip is a *label on* content, not a block of
/// content itself, and a hairline says "this is a tag" without putting another
/// solid shape on a page that is mostly prose. The ring is what varies between
/// tones; the inside stays the page.
///
/// Three tones, and no more: `neutral` is a hairline that recedes, `selected`
/// draws the ring in ink and thickens it — chosen over an accent fill because
/// a row of these has to read as one set with one of them picked, not as one
/// button among labels — and `warning` is the one place a chip is allowed
/// color: the "needs review" flag, whose whole job is to be noticed.
public struct DSChip: View {
    public enum Tone {
        case neutral
        case selected
        case warning
    }

    var title: String
    var systemImage: String?
    var tone: Tone

    public init(_ title: String, systemImage: String? = nil, tone: Tone = .neutral) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
    }

    public init(_ title: String, systemImage: String? = nil, isSelected: Bool) {
        self.init(title, systemImage: systemImage, tone: isSelected ? .selected : .neutral)
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    // A shade under the label: the glyph is there to be
                    // recognized at a glance, not read, so it sets beside the
                    // word rather than shouting over it.
                    .font(.system(size: 11, weight: .regular))
            }
            // Just under body size: near enough that the tag reads as part of
            // the prose rather than as chrome attached to it, small enough that
            // it never competes with the line it labels.
            Text(title)
                .font(.system(size: 14, weight: .regular))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .overlay(
            Capsule()
                // Inset by half the line width so the stroke lands inside the
                // chip's own bounds — otherwise a thicker selected ring grows
                // the pill and the row twitches as the selection moves.
                .strokeBorder(stroke, lineWidth: lineWidth)
        )
    }

    /// Ink in every tone but `warning`. The ring is what recedes; the word
    /// inside it is the thing being said, and a gray word in a gray ring is
    /// two quiet elements where one is enough.
    private var foreground: Color {
        switch tone {
        case .neutral, .selected: DSColor.textPrimary
        case .warning: DSColor.warning
        }
    }

    private var stroke: Color {
        switch tone {
        // The `border` token is tuned to separate two panels of nearly the same
        // value; a lone hairline on the page needs more than that to register.
        case .neutral: DSColor.textTertiary.opacity(0.55)
        case .selected: DSColor.textPrimary
        case .warning: DSColor.warning.opacity(0.55)
        }
    }

    private var lineWidth: CGFloat {
        tone == .selected ? 1.5 : 1
    }
}
