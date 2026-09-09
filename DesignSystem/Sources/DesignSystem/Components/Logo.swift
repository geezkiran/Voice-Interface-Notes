import SwiftUI

/// The brand mark, top-left of Home, in place of a user avatar.
///
/// Drawn as a template rather than as artwork: the mark is a single-color
/// silhouette, so it takes `textPrimary` and flips with the ground instead of
/// staying near-black on a dark canvas. A caller passing its own image gets
/// the same treatment — anything handed to this view is a monochrome mark by
/// definition, since that is what the shape is.
public struct DSLogo: View {
    /// Which face the mark wears. The mouth is the only difference between
    /// them — same folder, same eyes — so an empty screen reads as the app
    /// itself pulling a face rather than as a second, unrelated illustration.
    public enum Mark {
        case standard
        /// Mouth turned down. For a screen with nothing on it.
        case down

        var assetName: String {
            switch self {
            case .standard: "Logo"
            case .down: "LogoDown"
            }
        }
    }

    var image: Image
    var height: CGFloat
    var tint: Color

    public init(image: Image? = nil, height: CGFloat = 24, tint: Color = DSColor.textPrimary) {
        self.image = image ?? Image(Mark.standard.assetName, bundle: .module)
        self.height = height
        self.tint = tint
    }

    public init(_ mark: Mark, height: CGFloat = 24, tint: Color = DSColor.textPrimary) {
        self.image = Image(mark.assetName, bundle: .module)
        self.height = height
        self.tint = tint
    }

    public var body: some View {
        image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(tint)
    }
}
