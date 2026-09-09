import SwiftUI

/// The user's own query, rendered back at the top of a response — a
/// full-width white capsule with a hairline border, black text, generous
/// padding. Distinct from `DSCard`: this is specifically the "your words,
/// echoed back" surface, always this shape, never used for AI content.
public struct DSPromptBubble: View {
    var text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(DSFont.headline)
            .foregroundStyle(DSColor.textPrimary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                    .strokeBorder(DSColor.border, lineWidth: 1)
            )
    }
}
