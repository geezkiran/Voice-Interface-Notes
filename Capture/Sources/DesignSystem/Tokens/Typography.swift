import SwiftUI

/// Type language: Apple's system font throughout, at Apple's own sizes.
/// Hierarchy comes from size/weight steps only — no second family, no
/// tracking tricks.
///
/// There is **no monospaced role**. Numbers — durations, counts, times — are
/// set in the same face as everything else; where digits change in place and
/// the layout would twitch, the call site adds `.monospacedDigit()`, which
/// buys tabular figures without changing the family.
public enum DSFont {
    /// Large navigation title ("Captures"), matching `.largeTitle` bold.
    public static let display = Font.system(size: 34, weight: .bold)
    /// Section headers within a screen ("Action items", "Transcript").
    public static let title = Font.system(size: 22, weight: .bold)
    public static let headline = Font.system(size: 19, weight: .semibold)
    /// Long-form body copy — the transcript, the AI summary.
    public static let body = Font.system(size: 17, weight: .regular)
    /// Bold inline lead-ins inside a bullet ("**Breakfast**: ...").
    public static let bodyEmphasis = Font.system(size: 17, weight: .semibold)
    public static let caption = Font.system(size: 15, weight: .regular)
    public static let footnote = Font.system(size: 13, weight: .medium)

    /// The Notes-style row pair: a semibold title line over a lighter meta
    /// line that leads with the date.
    public static let rowTitle = Font.system(size: 17, weight: .semibold)
    /// Home's note-row title. A step larger than `rowTitle` — it is the one
    /// line the whole list is scanned by — but a step lighter in weight, so
    /// the extra size reads as scale rather than as shouting over the
    /// screen's own title.
    public static let rowTitleLarge = Font.system(size: 18, weight: .medium)
    public static let rowMeta = Font.system(size: 15, weight: .regular)
    /// The timestamp on the row's last line. Smaller than the preview above it
    /// and a weight heavier: it is the shortest string in the row, and at the
    /// tertiary grey it needs the weight to stay legible once it steps down.
    public static let rowDate = Font.system(size: 14, weight: .medium)

    /// A form field's label, sitting above its value.
    public static let fieldLabel = Font.system(size: 13, weight: .semibold)

    /// Line box for a large heading, as a fraction of the font's own line
    /// height. Display type at 34pt reads better pulled well under its natural
    /// leading — a wrapped heading should look like one block, not like two
    /// rows of a list. Applied by `DSTightHeading`, which is the only way to
    /// get it: SwiftUI's `lineSpacing` cannot go below zero.
    public static let tightHeadingLineHeight: CGFloat = 0.85

    /// Small numeric meta — a row's due time, an elapsed counter. The quietest
    /// step in the scale, and the one that used to be monospaced.
    public static let metaSmall = Font.system(size: 12, weight: .medium)
}

public extension View {
    /// The generous line spacing long-form text (transcript, AI summary)
    /// reads with — apply to any multi-line `Text` using `DSFont.body`.
    func dsReadingLineSpacing() -> some View {
        lineSpacing(6)
    }
}
