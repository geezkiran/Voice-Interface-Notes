// The app is iOS-only (per the plan: native SwiftUI, App Store, iOS APIs
// throughout). The screens are fenced off so `swift build` on macOS still
// checks the design system and the model layer, which are portable.
#if os(iOS)
import SwiftUI
import DesignSystem

/// One offered time, and the words for it.
///
/// The label is written out rather than derived at the point of use because
/// these are read at a glance, off a banner that is on screen for a few
/// seconds: "Tomorrow 9:00" is a time you can accept without doing arithmetic,
/// where "10/9, 09:00" is a date you have to work out.
struct ReminderSlot: Identifiable, Equatable {
    var label: String
    var date: Date

    var id: Date { date }

    /// The two or three times worth offering for this note.
    ///
    /// When the model heard a time in the words themselves, that is the whole
    /// offer — it came from the person's own sentence, so anything the app adds
    /// beside it is a worse guess competing with a good one. Otherwise the note
    /// is something to be reminded about with no time attached, and the offer is
    /// the two slots a reminder almost always wants: later today, or tomorrow
    /// morning. Anything further out is what "Pick a time" is for.
    static func offered(suggested: Date?, now: Date = .now) -> [ReminderSlot] {
        let calendar = Calendar.current

        if let suggested, suggested > now {
            return [ReminderSlot(label: label(for: suggested, now: now), date: suggested)]
        }

        var slots: [ReminderSlot] = []
        // Only worth offering while there is still an evening left to be
        // reminded in — at half past six "This evening" is a time that has
        // already happened.
        if let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now),
           evening.timeIntervalSince(now) > 3600 {
            slots.append(ReminderSlot(label: "This evening", date: evening))
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
            slots.append(ReminderSlot(label: "Tomorrow 9:00", date: morning))
        }
        return slots
    }

    /// `17:00`, `Tomorrow 17:00`, `Fri 17:00`, `12 Dec 17:00` — as much date as
    /// it takes to place the time, and no more.
    static func label(for date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let clock = date.formatted(date: .omitted, time: .shortened)

        if calendar.isDate(date, inSameDayAs: now) { return clock }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow \(clock)"
        }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        // Inside the week ahead a weekday name is the fastest thing to read;
        // past that it stops being unambiguous and a date is the honest answer.
        formatter.dateFormat = (0...6).contains(days) ? "EEE" : "d MMM"
        return "\(formatter.string(from: date)) \(clock)"
    }
}

/// The question "should I remind you about this?", asked the way a notification
/// asks it: over the page, briefly, and answerable by ignoring it.
///
/// It used to be a Timing section standing permanently at the foot of every
/// capture — two switches and a picker under every idea, every list, every
/// half-thought, on the off chance one of them was a task. That is a form
/// following you around, and the overwhelming majority of notes never answer
/// it. So the question is asked only when the note's own words suggest
/// something to be done or attended, and it is asked *over* the page rather
/// than *in* it: a banner is a thing that goes away on its own, and going away
/// on its own is what makes "no" free.
///
/// Nothing here can put a date on the capture without a tap. Dismissing, waiting
/// it out, or scrolling past all leave the note exactly as it was.
struct ReminderBanner: View {
    /// The time the model heard in the note, if it heard one. Drives the first
    /// slot; nil means the offer is the app's own two default slots.
    var suggestedAt: Date?
    /// One of the offered slots was taken.
    var onPick: (Date) -> Void
    /// "Pick a time" — hands over to the wheel.
    var onCustom: () -> Void
    /// The ✕, or a flick upwards.
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            headline
            slots
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: DSRadius.lg))
        // A notification is dismissed by flicking it away, and a banner that
        // covers the top of a page the user is reading has to be dismissable
        // without hunting for the ✕.
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height < -12 { onDismiss() }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reminder suggested for this capture")
    }

    // MARK: Headline

    /// The bell says what kind of thing is being offered before a word is read;
    /// the ✕ is the whole "no" and sits where a notification's dismiss sits.
    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
            Image(systemName: "bell.badge")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DSColor.intelligenceGradient)

            VStack(alignment: .leading, spacing: 2) {
                Text("Remind you about this?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DSColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    // A glyph this small needs a target around it that the
                    // thumb can actually find.
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not this one")
        }
    }

    /// Says where the offer came from. A time the person said out loud is worth
    /// naming as theirs — it is the difference between the app repeating them
    /// and the app deciding for them.
    private var subtitle: String {
        suggestedAt == nil
            ? "It reads like something to come back to."
            : "You mentioned a time for this."
    }

    // MARK: The offer

    /// The times, then the way out of them. "Pick a time" is last and plain:
    /// it is the answer for when none of the offered ones is right, and giving
    /// it the same weight as the slots would make the quick answers look like
    /// one option among three rather than the point of the banner.
    private var slots: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(ReminderSlot.offered(suggested: suggestedAt)) { slot in
                Button {
                    onPick(slot.date)
                } label: {
                    DSChip(slot.label, tone: .selected)
                }
                .buttonStyle(.plain)
            }

            Button("Pick a time", action: onCustom)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DSColor.accent)
                .buttonStyle(.plain)
                .padding(.leading, DSSpacing.xxs)

            Spacer(minLength: 0)
        }
    }
}

/// The wheel, for when none of the offered times is the right one.
///
/// A sheet rather than a picker unfolding inside the banner: the banner is a
/// glance-and-decide object that removes itself after a few seconds, and a date
/// wheel is a thing you fiddle with. Once you are fiddling, the interaction has
/// stopped being a notification and should stop behaving like one.
struct ReminderPickerSheet: View {
    @State private var date: Date
    var onSet: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    init(initial: Date, onSet: @escaping (Date) -> Void) {
        _date = State(initialValue: initial)
        self.onSet = onSet
    }

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            Text("Remind me")
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            DatePicker("", selection: $date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

            HStack(spacing: DSSpacing.sm) {
                Button("Cancel") { dismiss() }
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .glassEffect(.regular.interactive(), in: .capsule)

                Button("Set") {
                    onSet(date)
                    dismiss()
                }
                .font(DSFont.bodyEmphasis)
                .foregroundStyle(DSColor.onCaptureTint)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(DSColor.captureTint, in: .capsule)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.lg)
        .padding(.bottom, DSSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DSColor.background)
    }
}

#Preview("Suggested time") {
    ReminderBanner(
        suggestedAt: Calendar.current.date(byAdding: .hour, value: 26, to: .now),
        onPick: { _ in },
        onCustom: {},
        onDismiss: {}
    )
    .padding(DSSpacing.sm)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(DSColor.background)
}

#Preview("No time in the note") {
    ReminderBanner(
        suggestedAt: nil,
        onPick: { _ in },
        onCustom: {},
        onDismiss: {}
    )
    .padding(DSSpacing.sm)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(DSColor.background)
}

#endif
