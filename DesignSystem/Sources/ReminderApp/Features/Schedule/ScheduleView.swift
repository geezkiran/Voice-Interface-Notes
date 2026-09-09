// The app is iOS-only (per the plan: native SwiftUI, App Store, iOS APIs
// throughout). The screens are fenced off so `swift build` on macOS still
// checks the design system and the model layer, which are portable.
#if os(iOS)
import SwiftUI
import DesignSystem

/// **What's coming, one horizon at a time.** Home answers "what have I said?";
/// this answers "when does any of it land?" — a card and a list. The card is
/// the switch: Daily, Weekly, Monthly, Annually, with the chosen one named and
/// counted. Under it, unboxed, is that horizon's checklist.
///
/// The rules it holds to:
/// 1. **One horizon on screen, not four.** Four stacked lists make you scroll
///    to compare things you were never comparing. Picking a horizon empties
///    the screen of the others — the same move Home's tabs make.
/// 2. **A checklist, not a timetable.** An hour-by-hour rail spends the whole
///    screen drawing the empty hours between two things. A list gives every
///    row the same single tap: open it.
/// 3. **Everything dated is visible, exactly once.** Overdue folds into Daily,
///    and anything past this month lands in Annually, so no capture can hide
///    in a stretch of calendar nobody scrolls to.
/// 4. **No editing here.** Rows push into Editing, the same screen a Home row
///    opens. This is a lens on the same captures, not a second place they live.
struct ScheduleView: View {
    var store: CaptureStore
    /// An empty horizon offers a way in rather than a dead end. Same recorder
    /// the bottom bar opens — there is only ever one way in.
    var onCapture: () -> Void

    /// Opens on the day you're in: the horizon you actually act on today, and
    /// the only one that is ever urgent.
    @State private var cadence: ScheduleCadence = .daily
    /// Long horizons are shown a few rows deep until asked for in full. Reset
    /// on every switch, so a card never opens already scrolled out of shape.
    @State private var showsAll = false

    /// Enough rows to see the shape of the horizon, few enough that the card
    /// and the list stay in the thumb's reach.
    private static let collapsedCount = 4

    /// The switcher card's corner. Rounder than `DSRadius.lg`: at one line
    /// tall the card is nearly a capsule, and anything tighter reads as a
    /// table row rather than as the widget-like object it is.
    private static let cardRadius: CGFloat = 24

    /// A row's content height before padding. A one-line title only needs ~22pt;
    /// holding the rows taller than their text gives the checklist the same
    /// unhurried weight as the switcher card above it.
    private static let rowMinHeight: CGFloat = 34

    private var items: [CaptureItem] { store.items(in: cadence) }
    private var remaining: Int { items.filter { $0.state != .done }.count }
    private var visibleItems: [CaptureItem] {
        showsAll ? items : Array(items.prefix(Self.collapsedCount))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.sm) {
                switcherCard
                list
            }
            .padding(.top, DSSpacing.sm)
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.lg)
        }
        .background(DSColor.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Card one — the switch

    /// The whole card is the control: glyph, the horizon's name, how many are
    /// left, and the chevron that opens the list of the other three. One line,
    /// nothing else — the four options only take up room while you're choosing.
    private var switcherCard: some View {
        Menu {
            // A `Picker` inside a menu is the system's own dropdown: it ticks
            // the current choice and reads out as one control to VoiceOver,
            // which a stack of four buttons wouldn't.
            Picker("Horizon", selection: cadenceBinding) {
                ForEach(ScheduleCadence.allCases) { option in
                    Label(option.title, systemImage: symbol(option))
                        .tag(option)
                }
            }
        } label: {
            HStack(spacing: DSSpacing.sm) {
                badge

                Text(cadence.title)
                    .font(DSFont.title)
                    .foregroundStyle(DSColor.textPrimary)

                Spacer(minLength: 0)

                countRing

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(width: 24, height: 28)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Horizon: \(cadence.title), \(remaining) left")
        .accessibilityHint("Switch between daily, weekly, monthly and annually")
    }

    /// Switching resets how deep the list is opened — a horizon should never
    /// arrive already expanded from the last one.
    private var cadenceBinding: Binding<ScheduleCadence> {
        Binding(
            get: { cadence },
            set: { option in
                withAnimation(.easeOut(duration: 0.2)) {
                    cadence = option
                    showsAll = false
                }
            }
        )
    }

    /// The one spot of color per horizon: a filled square holding its glyph,
    /// which is what makes a switch of cadence visible at a glance rather than
    /// only as a changed word.
    private var badge: some View {
        RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous)
            .fill(tint(cadence).gradient)
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: symbol(cadence))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            )
    }

    /// How many are left, inside the arc of how many are done — a count alone
    /// says nothing about whether the horizon is going well. An empty horizon
    /// draws no arc rather than an accusing zero.
    @ViewBuilder
    private var countRing: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            let progress = Double(items.count - remaining) / Double(items.count)

            ZStack {
                Circle()
                    .stroke(DSColor.borderSubtle, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(DSColor.success, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(remaining)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.textSecondary)
                    .monospacedDigit()
            }
            .frame(width: 26, height: 26)
            .animation(.easeOut(duration: 0.2), value: progress)
            .accessibilityLabel("\(remaining) of \(items.count) left")
        }
    }

    // MARK: Card two — the horizon's checklist

    /// No card around this one. The rows already carry their own tinted
    /// shapes, and a white box around them was a second boundary drawn over
    /// the first — the checklist sits straight on the canvas instead.
    private var list: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            listHeader

            if items.isEmpty {
                emptyLine
            } else {
                ForEach(visibleItems) { item in
                    row(item)
                }

                if items.count > Self.collapsedCount {
                    viewAllButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DSSpacing.xxs)
    }

    /// What the card above only names, spelled out: the stretch of calendar
    /// this list covers, and how far through it you are.
    private var listHeader: some View {
        HStack(spacing: DSSpacing.xs) {
            Text(cadence.rangeLabel())
                .font(DSFont.rowTitle)
                .foregroundStyle(DSColor.textPrimary)

            Text(spanLabel)
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous))

            Spacer(minLength: 0)

            if !items.isEmpty {
                statusLine
            }
        }
        .padding(.horizontal, DSSpacing.xxs)
    }

    /// A line of the horizon: the title, and when it lands on the right. No
    /// tick target — the whole row is one tap into Editing, where a capture is
    /// actually worked on. The tint comes from the horizon rather than from the
    /// capture: a row's colour used to encode its kind, and with kinds gone the
    /// honest answer is that every row in one card belongs to the same card.
    private func row(_ item: CaptureItem) -> some View {
        NavigationLink(value: item.id) {
            HStack(spacing: DSSpacing.sm) {
                Text(item.title)
                    .font(DSFont.rowTitleLarge)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .strikethrough(item.state == .done, color: DSColor.textSecondary)

                Spacer(minLength: DSSpacing.xs)

                Text(timeLabel(item))
                    .font(DSFont.footnote)
                    .foregroundStyle(tint(cadence))
                    .monospacedDigit()
            }
            .frame(minHeight: Self.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(
            tint(cadence).opacity(0.10),
            in: RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
        )
        .opacity(item.state == .done ? 0.55 : 1)
    }

    /// How far through the horizon you are. The ring on the card above counts
    /// what's left; this counts what's behind you.
    private var statusLine: some View {
        Text(remaining == 0
             ? "All \(items.count) done"
             : "\(items.count - remaining) of \(items.count) done")
            .font(DSFont.metaSmall)
            .foregroundStyle(DSColor.textSecondary)
            .monospacedDigit()
    }

    private var viewAllButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { showsAll.toggle() }
        } label: {
            HStack(spacing: DSSpacing.xxs) {
                Text(showsAll ? "Show less" : "View all")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .font(DSFont.footnote)
            .foregroundStyle(DSColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .strokeBorder(DSColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// An empty horizon is the normal case for the far ones, so it stays a
    /// quiet line with a way in — never an illustration or an apology.
    private var emptyLine: some View {
        HStack(spacing: DSSpacing.xs) {
            Text(cadence.emptyLine)
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)

            Spacer(minLength: 0)

            Button(action: onCapture) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Capture something for \(cadence.title.lowercased())")
        }
    }

    // MARK: Formatting

    /// The chip beside the list's title: the exact days the horizon covers,
    /// which is the one thing its name ("This week", "September") leaves open.
    private var spanLabel: String {
        let calendar = Calendar.current
        let now = Date.now

        func interval(_ component: Calendar.Component) -> (Date, Date)? {
            guard let range = calendar.dateInterval(of: component, for: now) else { return nil }
            // `end` is the first instant of the next period — the last day the
            // horizon actually covers is the one before it.
            let last = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
            return (range.start, last)
        }

        switch cadence {
        case .daily:
            return now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .weekly:
            guard let (start, end) = interval(.weekOfYear) else { return "" }
            return "\(start.formatted(.dateTime.day()))–\(end.formatted(.dateTime.day().month(.abbreviated)))"
        case .monthly:
            guard let (start, end) = interval(.month) else { return "" }
            return "\(start.formatted(.dateTime.day()))–\(end.formatted(.dateTime.day().month(.abbreviated)))"
        case .annually:
            // Open-ended by design, so it names where it starts rather than
            // claiming an end it doesn't enforce.
            return "From \(now.formatted(.dateTime.month(.abbreviated)))"
        }
    }

    /// Each horizon reads out only the part of the date it can't infer: the
    /// hour today, the weekday this week, the date this month, the month
    /// beyond it.
    private func timeLabel(_ item: CaptureItem) -> String {
        guard let due = item.dueAt else { return "" }
        switch cadence {
        case .daily: return due.formatted(date: .omitted, time: .shortened)
        case .weekly: return due.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case .monthly: return due.formatted(.dateTime.day().month(.abbreviated))
        case .annually: return due.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func symbol(_ cadence: ScheduleCadence) -> String {
        switch cadence {
        case .daily: "sun.max.fill"
        case .weekly: "calendar"
        case .monthly: "square.grid.2x2.fill"
        case .annually: "mountain.2.fill"
        }
    }

    private func tint(_ cadence: ScheduleCadence) -> Color {
        switch cadence {
        case .daily: Color(red: 0.85, green: 0.58, blue: 0.05)
        case .weekly: Color(red: 0.35, green: 0.42, blue: 0.92)
        case .monthly: Color(red: 0.13, green: 0.62, blue: 0.60)
        case .annually: Color(red: 0.55, green: 0.38, blue: 0.90)
        }
    }
}

#Preview {
    RootView()
}

#endif
