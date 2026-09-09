import SwiftUI

/// The "the model is writing this" placeholder: a word set in the page's own
/// ink with a highlight travelling through it, left to right, forever until the
/// answer lands.
///
/// It stands *in place of* the text being written rather than beside it. A
/// rewrite replaces words the user has already read, and watching their own
/// sentences get eaten a token at a time reads as damage; a single line saying
/// the page is busy, with movement in it so it is plainly alive, says the same
/// thing without showing the demolition.
///
/// The movement is a mask, not an opacity pulse — a pulse reads as a warning
/// light, a sweep reads as work in progress.
public struct DSShimmerText: View {
    var text: String
    var font: Font

    /// Where the highlight is, as a fraction of the sweep. Driven by a
    /// `TimelineView` rather than a repeating animation so it keeps its phase
    /// across the layout passes a growing page puts it through.
    private static let period: TimeInterval = 1.6

    public init(_ text: String, font: Font = .system(size: 18, weight: .regular)) {
        self.text = text
        self.font = font
    }

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.period) / Self.period

            Text(text)
                .font(font)
                .foregroundStyle(DSColor.textTertiary)
                .overlay {
                    // Plain ink, not the intelligence gradient: the sweep is a
                    // light passing over the word, and a light has no hue. On
                    // dark that is a near-white band on gray — the shimmer as
                    // asked for — and on light the same token keeps it visible
                    // by running the other way, since literal white would sweep
                    // invisibly across a near-white page.
                    Text(text)
                        .font(font)
                        .foregroundStyle(DSColor.textPrimary)
                        .mask {
                            // A band of light the width of a couple of
                            // characters, swept from just off one edge to just
                            // off the other so the line is never caught mid-lit
                            // at the turnaround.
                            GeometryReader { geo in
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .white, location: 0.5),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: geo.size.width * 0.7)
                                .offset(x: -geo.size.width * 0.7 + t * geo.size.width * 1.7)
                            }
                        }
                }
                .accessibilityLabel(text)
        }
    }
}
