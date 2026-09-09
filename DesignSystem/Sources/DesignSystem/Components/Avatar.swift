import SwiftUI

/// The user's own picture, top-right of Home.
public struct DSAvatar: View {
    var image: Image
    var size: CGFloat

    public init(image: Image? = nil, size: CGFloat = 44) {
        self.image = image ?? Image("ProfileAvatar", bundle: .module)
        self.size = size
    }

    public var body: some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(DSColor.border, lineWidth: 1)
            }
    }
}
