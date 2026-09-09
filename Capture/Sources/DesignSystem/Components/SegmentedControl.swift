import SwiftUI

/// The "Ask / Imagine" mode switch — a plain-text option sits directly on
/// the canvas until selected, at which point it gets a white pill behind
/// it. No outer track/groove; selection is expressed purely by that pill
/// appearing, which is what makes it read as light and un-chrome-y rather
/// than like a standard iOS segmented control.
public struct DSSegmentedControl: View {
    var options: [String]
    @Binding var selection: String

    public init(options: [String], selection: Binding<String>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(option)
                        .font(DSFont.headline)
                        .foregroundStyle(DSColor.textPrimary)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, DSSpacing.xs)
                        .background(
                            Capsule().fill(selection == option ? DSColor.surface : Color.clear)
                        )
                        .overlay(
                            Capsule().strokeBorder(selection == option ? DSColor.border : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
