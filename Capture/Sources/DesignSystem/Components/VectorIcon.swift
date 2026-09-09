import SwiftUI

/// Icons drawn as paths rather than pulled from SF Symbols.
///
/// The system is SF Symbols first — they carry weight, optical sizing and
/// Dynamic Type for free, and a hand-drawn icon gives all of that up. So this
/// exists only for the few glyphs that were art-directed elsewhere and have to
/// match exactly. Each is authored in the same 24×24 box its SVG used, stroked
/// (never filled), with round caps and joins.
public enum DSVectorIcon: Hashable, Sendable {
    /// A house with its doorway drawn as a separate line under the roof.
    case home

    /// Five vertical bars of rising-then-falling height — a voice level meter.
    /// What the capture button starts is *listening*, so it wears this rather
    /// than a plus.
    case levels

    /// The outline, scaled from its 24×24 design box into `rect` and centered.
    /// Every glyph here keeps a 3-unit margin inside that box, so a stroke
    /// centered on the path never clips.
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let offset = CGPoint(
            x: rect.midX - 12 * scale,
            y: rect.midY - 12 * scale
        )

        var path = Path()
        switch self {
        case .home:
            addHome(to: &path)
        case .levels:
            addLevels(to: &path)
        }

        return path.applying(
            CGAffineTransform(translationX: offset.x, y: offset.y)
                .scaledBy(x: scale, y: scale)
        )
    }

    /// Bars at x = 3, 7.5, 12, 16.5, 21, each centered on the box's midline so
    /// the glyph stays balanced however it's cropped.
    private func addLevels(to path: inout Path) {
        for (x, halfHeight) in [(3.0, 2.0), (7.5, 1.0), (12.0, 6.0), (16.5, 9.0), (21.0, 2.0)] {
            path.move(to: CGPoint(x: x, y: 12 - halfHeight))
            path.addLine(to: CGPoint(x: x, y: 12 + halfHeight))
        }
    }

    private func addHome(to path: inout Path) {
        // The doorstep line.
        path.move(to: CGPoint(x: 8, y: 17))
        path.addLine(to: CGPoint(x: 16, y: 17))

        // The house: roof apex, down the left eave, round the four rounded
        // corners of the body, and back up to the apex.
        path.move(to: CGPoint(x: 11.0177, y: 2.764))
        path.addLine(to: CGPoint(x: 4.23539, y: 8.03912))
        path.addCurve(
            to: CGPoint(x: 3.39203, y: 8.78886),
            control1: CGPoint(x: 3.78202, y: 8.39175),
            control2: CGPoint(x: 3.55534, y: 8.56806)
        )
        path.addCurve(
            to: CGPoint(x: 3.07403, y: 9.43905),
            control1: CGPoint(x: 3.24737, y: 8.98444),
            control2: CGPoint(x: 3.1396, y: 9.20478)
        )
        path.addCurve(
            to: CGPoint(x: 3, y: 10.5651),
            control1: CGPoint(x: 3, y: 9.70352),
            control2: CGPoint(x: 3, y: 9.9907)
        )
        path.addLine(to: CGPoint(x: 3, y: 17.8))
        path.addCurve(
            to: CGPoint(x: 3.21799, y: 19.908),
            control1: CGPoint(x: 3, y: 18.9201),
            control2: CGPoint(x: 3, y: 19.4801)
        )
        path.addCurve(
            to: CGPoint(x: 4.09202, y: 20.782),
            control1: CGPoint(x: 3.40973, y: 20.2843),
            control2: CGPoint(x: 3.71569, y: 20.5903)
        )
        path.addCurve(
            to: CGPoint(x: 6.2, y: 21),
            control1: CGPoint(x: 4.51984, y: 21),
            control2: CGPoint(x: 5.07989, y: 21)
        )
        path.addLine(to: CGPoint(x: 17.8, y: 21))
        path.addCurve(
            to: CGPoint(x: 19.908, y: 20.782),
            control1: CGPoint(x: 18.9201, y: 21),
            control2: CGPoint(x: 19.4802, y: 21)
        )
        path.addCurve(
            to: CGPoint(x: 20.782, y: 19.908),
            control1: CGPoint(x: 20.2843, y: 20.5903),
            control2: CGPoint(x: 20.5903, y: 20.2843)
        )
        path.addCurve(
            to: CGPoint(x: 21, y: 17.8),
            control1: CGPoint(x: 21, y: 19.4801),
            control2: CGPoint(x: 21, y: 18.9201)
        )
        path.addLine(to: CGPoint(x: 21, y: 10.5651))
        path.addCurve(
            to: CGPoint(x: 20.926, y: 9.43905),
            control1: CGPoint(x: 21, y: 9.9907),
            control2: CGPoint(x: 21, y: 9.70352)
        )
        path.addCurve(
            to: CGPoint(x: 20.608, y: 8.78886),
            control1: CGPoint(x: 20.8604, y: 9.20478),
            control2: CGPoint(x: 20.7526, y: 8.98444)
        )
        path.addCurve(
            to: CGPoint(x: 19.7646, y: 8.03913),
            control1: CGPoint(x: 20.4447, y: 8.56806),
            control2: CGPoint(x: 20.218, y: 8.39175)
        )
        path.addLine(to: CGPoint(x: 12.9823, y: 2.764))
        path.addCurve(
            to: CGPoint(x: 12.2613, y: 2.3016),
            control1: CGPoint(x: 12.631, y: 2.49075),
            control2: CGPoint(x: 12.4553, y: 2.35412)
        )
        path.addCurve(
            to: CGPoint(x: 11.7387, y: 2.3016),
            control1: CGPoint(x: 12.0902, y: 2.25526),
            control2: CGPoint(x: 11.9098, y: 2.25526)
        )
        path.addCurve(
            to: CGPoint(x: 11.0177, y: 2.764),
            control1: CGPoint(x: 11.5447, y: 2.35412),
            control2: CGPoint(x: 11.369, y: 2.49075)
        )
    }
}

/// A `DSVectorIcon` as a shape, for anywhere a shape is what's wanted.
public struct DSVectorShape: Shape {
    var icon: DSVectorIcon

    public init(_ icon: DSVectorIcon) {
        self.icon = icon
    }

    public func path(in rect: CGRect) -> Path {
        icon.path(in: rect)
    }
}

/// A `DSVectorIcon` rendered at a size, stroked in the current foreground
/// style. `lineWidth` is in the icon's own 24-unit terms — pass 2 to get the
/// stroke the artwork was drawn with, whatever size it's rendered at.
public struct DSVectorIconView: View {
    var icon: DSVectorIcon
    var size: CGFloat
    var lineWidth: CGFloat

    public init(_ icon: DSVectorIcon, size: CGFloat = 24, lineWidth: CGFloat = 2) {
        self.icon = icon
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        DSVectorShape(icon)
            .stroke(
                style: StrokeStyle(
                    lineWidth: lineWidth * size / 24,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: size, height: size)
    }
}
