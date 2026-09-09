import SwiftUI

/// A one-column wheel that hovers over the screen instead of pushing it
/// around: a short scrolling column where **whatever sits in the middle is
/// the selection**, so choosing is a scroll rather than a tap-and-confirm.
///
/// It is deliberately not a `Menu`. A menu is a list of commands that drops
/// down, covers what you were reading and takes a second tap to commit; this
/// stays anchored to the control that opened it, shows the neighbours on
/// either side of the current value, and fades out at the top and bottom
/// edges so the column reads as a window onto a longer strip rather than a
/// box with things clipped off at its rim.
public struct DSWheelPicker<Item: Hashable & Identifiable>: View {
    var items: [Item]
    @Binding var selection: Item
    var rowHeight: CGFloat
    /// How many rows are on screen at once. Odd, so there is a true middle.
    var visibleRows: Int
    var title: (Item) -> String
    var symbol: (Item) -> String

    /// Which row the scroll has come to rest under the centre line. Kept
    /// separate from `selection` so a scroll in progress can drive the
    /// highlight before it commits.
    @State private var centered: Item.ID?

    public init(
        items: [Item],
        selection: Binding<Item>,
        rowHeight: CGFloat = 44,
        visibleRows: Int = 5,
        title: @escaping (Item) -> String,
        symbol: @escaping (Item) -> String
    ) {
        self.items = items
        self._selection = selection
        self.rowHeight = rowHeight
        self.visibleRows = visibleRows
        self.title = title
        self.symbol = symbol
    }

    public var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    row(item)
                        .frame(height: rowHeight)
                        .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: rowHeight * CGFloat(visibleRows))
        // Half the column's height of empty space at each end, so the first
        // and last items can reach the middle like any other.
        .contentMargins(.vertical, rowHeight * CGFloat(visibleRows / 2), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centered, anchor: .center)
        .scrollIndicators(.hidden)
        .mask(edgeFade)
        .onAppear { centered = selection.id }
        .onChange(of: centered) { _, id in
            guard let item = items.first(where: { $0.id == id }), item != selection else { return }
            selection = item
        }
        .onChange(of: selection) { _, new in
            // A change from outside (a fresh item opened under the same
            // control) should move the wheel, not fight it.
            if centered != new.id { centered = new.id }
        }
    }

    private func row(_ item: Item) -> some View {
        let isCentered = centered == item.id
        return HStack(spacing: DSSpacing.xs) {
            Image(systemName: symbol(item))
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)
            Text(title(item))
                .font(isCentered ? DSFont.bodyEmphasis : DSFont.body)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isCentered ? DSColor.textPrimary : DSColor.textSecondary)
        .padding(.horizontal, DSSpacing.md)
        .contentShape(.rect)
        .animation(.snappy(duration: 0.18), value: isCentered)
        // Tapping a neighbour is the shortcut for scrolling it to the middle.
        .onTapGesture {
            withAnimation(.snappy(duration: 0.25)) { centered = item.id }
        }
    }

    /// Solid through the middle band, transparent at both rims.
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.28),
                .init(color: .black, location: 0.72),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
