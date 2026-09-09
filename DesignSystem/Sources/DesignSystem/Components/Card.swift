import SwiftUI

/// The one surface-elevation trick this system allows: a hairline border,
/// never a shadow. Used for inbox rows, list cards, the Session summary
/// card — anything that needs to read as "a distinct object" without
/// implying it's floating above the page.
public struct DSCard<Content: View>: View {
    var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(DSSpacing.md)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .strokeBorder(DSColor.border, lineWidth: 1)
            )
    }
}
