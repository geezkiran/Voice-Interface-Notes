import SwiftUI

/// The week rail that sits under a day screen's title: seven tall stadium
/// capsules, weekday initial over date, one of them selected.
///
/// Three states, and they're deliberately carried by three different signals
/// so they can all be true at once without fighting:
/// - **selected** — a filled gray capsule (where you are)
/// - **has anything on it** — a dot under the date (whether it's worth going)
/// - **progress** — an arc stroked around the capsule (how much of that day
///   is already dealt with)
public struct DSDayStrip: View {
    public struct Day: Identifiable {
        public var date: Date
        /// 0…1 arc around the capsule. `nil` draws no arc — an empty day
        /// should look empty, not like a zeroed-out gauge.
        public var progress: Double?
        public var hasItems: Bool

        public var id: Date { date }

        public init(date: Date, progress: Double? = nil, hasItems: Bool = false) {
            self.date = date
            self.progress = progress
            self.hasItems = hasItems
        }
    }

    var days: [Day]
    @Binding var selection: Date

    public init(days: [Day], selection: Binding<Date>) {
        self.days = days
        self._selection = selection
    }

    public var body: some View {
        GlassEffectContainer(spacing: DSSpacing.xxs + 2) {
            HStack(spacing: DSSpacing.xxs + 2) {
                ForEach(days) { day in
                    capsule(for: day)
                }
            }
        }
    }

    private func capsule(for day: Day) -> some View {
        let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selection)

        return Button {
            selection = Calendar.current.startOfDay(for: day.date)
        } label: {
            VStack(spacing: 1) {
                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DSColor.textSecondary)

                Text(day.date.formatted(.dateTime.day()))
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(DSColor.textPrimary)

                Circle()
                    .fill(day.hasItems ? DSColor.textPrimary : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .overlay(progressArc(day.progress))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected
                ? .regular.tint(DSColor.surfaceRaised).interactive()
                : .regular.interactive(),
            in: .capsule
        )
        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func progressArc(_ progress: Double?) -> some View {
        if let progress, progress > 0 {
            Capsule()
                .trim(from: 0, to: min(progress, 1))
                .stroke(DSColor.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }
}

/// One small gauge in the summary strip above a day: a glyph, a `done / total`
/// count, and a bar underneath. Several sit in a row.
///
/// Monochrome by design — the row is a status readout, not a chart, and a
/// rainbow of bars would be the loudest thing on a screen whose job is to
/// stay quiet.
public struct DSMeter: View {
    var symbol: String
    var value: Int
    var total: Int

    public init(symbol: String, value: Int, total: Int) {
        self.symbol = symbol
        self.value = value
        self.total = total
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)

                Text("\(value) / \(total)")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(DSColor.textPrimary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DSColor.surfaceRaised)
                    Capsule()
                        .fill(DSColor.accent)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(value) / Double(total), 1)
    }
}
