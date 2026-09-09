import SwiftUI

/// Wraps its children left-to-right, top-to-bottom, moving to a new row
/// whenever the next child would overflow the available width — chips and
/// tags stacking inline instead of scrolling off screen.
public struct DSFlowLayout: Layout {
    public var horizontalSpacing: CGFloat
    public var verticalSpacing: CGFloat

    public init(horizontalSpacing: CGFloat = DSSpacing.xxs, verticalSpacing: CGFloat = DSSpacing.xxs) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: width)
        let height = rows.reduce(0) { $0 + $1.height } + verticalSpacing * CGFloat(max(0, rows.count - 1))
        let rowWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: min(rowWidth, width), height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct RowItem {
        var subview: LayoutSubview
        var size: CGSize
    }

    private struct Row {
        var items: [RowItem]
        var width: CGFloat
        var height: CGFloat
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current: [RowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let addedWidth = current.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width
            if addedWidth > maxWidth, !current.isEmpty {
                rows.append(Row(items: current, width: currentWidth, height: currentHeight))
                current = []
                currentWidth = 0
                currentHeight = 0
            }
            current.append(RowItem(subview: subview, size: size))
            currentWidth = current.isEmpty ? 0 : (currentWidth == 0 ? size.width : currentWidth + horizontalSpacing + size.width)
            currentHeight = max(currentHeight, size.height)
        }
        if !current.isEmpty {
            rows.append(Row(items: current, width: currentWidth, height: currentHeight))
        }
        return rows
    }
}
