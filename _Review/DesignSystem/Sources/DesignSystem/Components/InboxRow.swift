import SwiftUI

/// The core list row — a captured item in the inbox/today view. Dense,
/// left-aligned, a timestamp on the trailing edge, a chip for the
/// inferred category. No thumbnail, no card chrome around each row (the
/// list itself supplies the boundary via hairline dividers) — density over
/// decoration, matching how Grok renders a running list of items.
public struct DSInboxRow: View {
    var title: String
    var category: String?
    var timeLabel: String?
    var isLowConfidence: Bool

    public init(title: String, category: String? = nil, timeLabel: String? = nil, isLowConfidence: Bool = false) {
        self.title = title
        self.category = category
        self.timeLabel = timeLabel
        self.isLowConfidence = isLowConfidence
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(2)

                if let category {
                    DSChip(category)
                }
            }

            Spacer(minLength: DSSpacing.sm)

            VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                if let timeLabel {
                    Text(timeLabel)
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textTertiary)
                        // Digits only: the face stays the system one, the
                        // column just stops twitching as times change width.
                        .monospacedDigit()
                }
                if isLowConfidence {
                    Text("needs review")
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.warning)
                }
            }
        }
        .padding(.vertical, DSSpacing.sm)
    }
}
