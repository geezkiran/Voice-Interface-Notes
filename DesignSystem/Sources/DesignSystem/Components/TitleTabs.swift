import SwiftUI

/// Tabs drawn as display-size titles rather than as a control.
///
/// One row of large words — the selected one near-black, the rest grayed —
/// with no track, no pill, no underline. The point is that the row *is* the
/// screen's title: instead of "Captures" sitting above a filter, the current
/// filter names the screen, and its siblings sit beside it as the next words
/// on the line.
///
/// Selection moves by color and weight only, so nothing resizes or slides
/// under the finger; the strip scrolls the tapped title back into view.
public struct DSTitleTabs<Value: Hashable>: View {
    public struct Item: Identifiable {
        public var value: Value
        public var label: String

        public var id: Value { value }

        public init(value: Value, label: String) {
            self.value = value
            self.label = label
        }
    }

    var items: [Item]
    @Binding var selection: Value
    var size: CGFloat

    public init(items: [Item], selection: Binding<Value>, size: CGFloat = DSFont.serifTabSize) {
        self.items = items
        self._selection = selection
        self.size = size
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                // A wide gap, because there's no divider or pill doing the
                // separating — at a tight spacing the row reads as one
                // sentence rather than as a set of choices.
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        tab(item)
                            .id(item.value)
                            // No padding on the container itself — that would
                            // reserve dead space at the trailing edge too and
                            // eat into the scrollable hit area. Only the first
                            // and last titles get pushed in, by the same
                            // amount the body's cards are inset, so the row's
                            // rest position lines up with the content below it.
                            .padding(.leading, index == 0 ? DSSpacing.lg : 0)
                            .padding(.trailing, index == items.count - 1 ? DSSpacing.lg : 0)
                    }
                }
                // The row is a title, so it keeps a title's breathing room
                // above the content below it.
                .padding(.vertical, DSSpacing.xxs)
            }
            .scrollIndicators(.hidden)
            // A tapped title can be half off-screen; bring it fully in.
            // Deliberately *not* done on appear: the strip should open at its
            // first title, whatever happens to be selected, so the reading
            // order is the one the row was written in.
            .onChange(of: selection) { _, new in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private func tab(_ item: Item) -> some View {
        let isSelected = item.value == selection

        return Button {
            selection = item.value
        } label: {
            // Serif, because these titles are the page's masthead rather than
            // UI chrome — the family break is what separates them from every
            // system-font control on the screen. Selection moves by weight and
            // color only, both titles held at the same size.
            Text(item.label)
                .font(DSFont.serif(size: size, weight: isSelected ? .black : .semibold))
                // At display size the serif's default fitting reads loose;
                // pulling the letters in by a fraction of the size keeps the
                // word compact as one shape, at any `size` the caller picks.
                .tracking(size * -0.02)
                .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textTertiary)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
