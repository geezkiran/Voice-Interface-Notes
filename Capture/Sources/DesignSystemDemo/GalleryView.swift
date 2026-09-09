import SwiftUI
import DesignSystem

/// A clone-target screen: reproduces the reference Grok screenshot's
/// layout almost element-for-element (top bar, mode toggle, prompt bubble,
/// "Thoughts" link, a long-form AI response with headers/paragraphs/bullet
/// list, and the two-row composer bar) so the design system can be judged
/// against the real thing rather than an abstract component gallery.
public struct DSGalleryView: View {
    @State private var mode: String = "Ask"

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            DSColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    // Top bar
                    HStack {
                        Button(action: {}) { Image(systemName: "line.3.horizontal") }
                            .buttonStyle(.dsIcon)

                        Spacer()

                        DSSegmentedControl(options: ["Ask", "Imagine"], selection: $mode)

                        Spacer()

                        Button(action: {}) { Image(systemName: "square.and.pencil") }
                            .buttonStyle(.dsIcon)
                    }

                    DSPromptBubble("Give me a 7-day healthy meal plan")

                    Button(action: {}) {
                        HStack(spacing: DSSpacing.xxs) {
                            Text("Thoughts")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        Text("7-Day Healthy Meal Plan")
                            .font(DSFont.display)
                            .foregroundStyle(DSColor.textPrimary)

                        Text("(Approx. 1,800–2,200 calories/day | Balanced macros | Whole-food focused | Easy to prepare)")
                            .font(DSFont.body)
                            .foregroundStyle(DSColor.textPrimary)
                            .dsReadingLineSpacing()

                        Text("This plan emphasizes vegetables, lean proteins, healthy fats, fiber-rich carbs, and variety to keep you satisfied and energized. Each day includes breakfast, lunch, dinner, and two snacks.")
                            .font(DSFont.body)
                            .foregroundStyle(DSColor.textPrimary)
                            .dsReadingLineSpacing()
                    }

                    Text("Monday")
                        .font(DSFont.title)
                        .foregroundStyle(DSColor.textPrimary)

                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        DSBulletLine(label: "Breakfast", detail: "Greek yogurt bowl – 200g plain Greek yogurt, 1 cup mixed berries, 1 tbsp chia seeds, 10 almonds")
                        DSBulletLine(label: "Snack 1", detail: "1 medium apple + 1 tbsp natural peanut butter")
                    }

                    Color.clear.frame(height: 140) // reserve space behind the floating composer
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.sm)
            }

            DSCaptureButton(action: {})
                .padding(.horizontal, DSSpacing.md)
                .padding(.bottom, DSSpacing.sm)
        }
    }
}

/// One bulleted line with a bold inline lead-in, matching the reference's
/// "**Breakfast**: Greek yogurt bowl…" list style.
struct DSBulletLine: View {
    var label: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.xs) {
            Text("•")
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)

            (
                Text("\(label): ").font(DSFont.bodyEmphasis)
                    + Text(detail).font(DSFont.body)
            )
            .foregroundStyle(DSColor.textPrimary)
            .dsReadingLineSpacing()
        }
    }
}

#Preview("Gallery") {
    DSGalleryView().preferredColorScheme(.light)
}
