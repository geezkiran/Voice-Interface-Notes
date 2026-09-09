import SwiftUI

/// The one place multicolor is allowed: the app's wordmark, or a moment of
/// delight (e.g. "All caught up"). Applies `DSColor.brandGradient` as a
/// foreground mask over the given text.
public struct DSGradientText: View {
    var text: String
    var font: Font

    public init(_ text: String, font: Font = DSFont.title) {
        self.text = text
        self.font = font
    }

    public var body: some View {
        Text(text)
            .font(font)
            .fontWeight(.bold)
            .foregroundStyle(DSColor.brandGradient)
    }
}
