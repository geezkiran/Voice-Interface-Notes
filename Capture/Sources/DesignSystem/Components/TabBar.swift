import SwiftUI

/// The bottom bar: a floating Liquid Glass capsule of destinations, with the
/// capture button undocked beside it as its own glass circle.
///
/// Not a `TabView`: the system bar can't host a raised center action, and it
/// can't be split into two floating pieces. This is the iOS 26 shape instead —
/// the bar hovers over scrolling content rather than sitting on an opaque
/// surface, and the one action that isn't a place lives outside it.
///
/// Both pieces share a single `GlassEffectContainer`, so the material blends
/// between them at close range the way system glass does, instead of reading as
/// two separate panes.
///
/// Selection is carried by weight, color, and a glass highlight together
/// (filled glyph, near-black label), never by color alone.
public struct DSTabBar<Value: Hashable>: View {
    public struct Item: Identifiable {
        /// Most tabs are an SF Symbol, optionally with a filled variant for
        /// the selected state; a `drawn` one is a path from `DSVectorIcon`.
        public enum Icon {
            case symbol(String, selected: String? = nil)
            case drawn(DSVectorIcon)
        }

        public var value: Value
        public var icon: Icon
        public var label: String

        public var id: Value { value }

        public init(value: Value, icon: Icon, label: String) {
            self.value = value
            self.icon = icon
            self.label = label
        }

        public init(value: Value, symbol: String, selectedSymbol: String? = nil, label: String) {
            self.init(value: value, icon: .symbol(symbol, selected: selectedSymbol), label: label)
        }
    }

    var items: [Item]
    @Binding var selection: Value
    var captureGlyph: DSCaptureButton.Glyph
    var onCapture: () -> Void

    /// Namespace for the selection pill, so it slides between destinations
    /// instead of cross-fading in place.
    @Namespace private var selectionPill

    public init(
        items: [Item],
        selection: Binding<Value>,
        captureGlyph: DSCaptureButton.Glyph = .drawn(.levels),
        onCapture: @escaping () -> Void
    ) {
        self.items = items
        self._selection = selection
        self.captureGlyph = captureGlyph
        self.onCapture = onCapture
    }

    public var body: some View {
        // Container spacing stays well under the gap: the two shapes share one
        // material so they light and refract together, but they must not neck
        // into each other — the button is undocked, and has to read that way.
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: Self.gap) {
                destinations

                DSCaptureButton(size: 60, glyph: captureGlyph, action: onCapture)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.bottom, -4)
    }

    /// Wide enough that the bar and the button read as two objects, tight
    /// enough that the material still bridges between them.
    private static var gap: CGFloat { 12 }

    private var destinations: some View {
        HStack(spacing: 6) {
            ForEach(items) { tab($0) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// Selection thickens the glyph either way — a heavier symbol weight, or
    /// a heavier stroke on a drawn path — so the two kinds of icon read as
    /// the same control.
    @ViewBuilder
    private func icon(_ icon: Item.Icon, isSelected: Bool) -> some View {
        switch icon {
        case let .symbol(name, selected):
            Image(systemName: isSelected ? (selected ?? name) : name)
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
        case let .drawn(vector):
            // Rendered a little larger than a symbol at the same nominal size:
            // the artwork keeps a 3-unit margin inside its box, so a 25pt icon
            // draws about 19pt of glyph — level with the symbols beside it.
            DSVectorIconView(vector, size: 25, lineWidth: isSelected ? 2.4 : 1.9)
        }
    }

    private func tab(_ item: Item) -> some View {
        let isSelected = item.value == selection

        return Button {
            // The pill is a position, not a fade — animate the selection change
            // itself so the geometry match has something to interpolate.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selection = item.value
            }
        } label: {
            VStack(spacing: 3) {
                icon(item.icon, isSelected: isSelected)
                    .frame(height: 24)

                Text(item.label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textTertiary)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(DSColor.textPrimary.opacity(0.08))
                        .matchedGeometryEffect(id: "selection", in: selectionPill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
