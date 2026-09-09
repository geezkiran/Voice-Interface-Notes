import SwiftUI

/// The Home screen's row, modelled directly on Apple Notes' note row: a
/// single-line title in semibold, then one secondary line that leads with the
/// date and continues into a preview of the content. No tags, badges or
/// flags: the row carries text only, so it never grows into a card.
///
/// Deliberately *not* a `DSCard`: Notes' list reads as one continuous surface
/// with hairline separators, and stacking bordered cards inside it would
/// fight both that and the glass floating above.
public struct DSNoteRow: View {
    var title: String
    var preview: String
    var dateLabel: String

    public init(
        title: String,
        preview: String,
        dateLabel: String
    ) {
        self.title = title
        self.preview = preview
        self.dateLabel = dateLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Every line of the row is clipped to one, the title included: a
            // list scanned at a glance wants rows of the same height more
            // than it wants the tail of a long heading, and the preview
            // underneath carries the rest of the sentence anyway.
            Text(title)
                .font(DSFont.rowTitleLarge)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.leading)

            Text(preview)
                .font(DSFont.rowMeta)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)

            // The timestamp leads the row's last line, in the corner the eye
            // reaches first. Plain text — the row carries no pills.
            HStack(alignment: .center, spacing: DSSpacing.xxs) {
                Text(dateLabel)
                    .font(DSFont.rowDate)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: DSSpacing.xs)
            }
            .padding(.top, 2)
        }
        // Tight vertical rhythm: the row already has three lines, so the list's
        // own row insets carry most of the breathing space.
        .padding(.vertical, 1)
    }
}
