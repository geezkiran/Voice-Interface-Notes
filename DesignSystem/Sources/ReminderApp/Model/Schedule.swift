import Foundation

/// The seven days the Schedule screen's rail shows. Kept as a value type with
/// no view knowledge so "which week am I looking at" is decided once, here.
///
/// Weeks start wherever the user's locale says they start
/// (`Calendar.current`), not on a hardcoded Monday.
public struct WeekWindow: Hashable, Sendable {
    /// Start of the first day of the window.
    public let start: Date
    /// The seven day-starts, in rail order.
    public let days: [Date]

    /// The week containing `date`.
    public init(containing date: Date = .now) {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
        self.start = start
        self.days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

/// The four horizons the Schedule screen cuts the calendar into: what's on
/// today, what's left in the week, what's left in the month, what's left in
/// the year. One capture lands in exactly one of them.
///
/// They are *horizons*, not recurrence rules — nothing in the model repeats
/// yet. "Daily" is the day you're in, "Weekly" the rest of the week around it,
/// and so on outward, which is the same question a repeat rule would answer
/// ("how far out do I have to care?") without inventing data the AI never
/// extracted.
public enum ScheduleCadence: String, CaseIterable, Identifiable, Sendable {
    case daily, weekly, monthly, annually

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .annually: "Annually"
        }
    }

    /// The stretch of calendar the horizon is holding, named the way you'd say
    /// it out loud — "Today", "This week", "September", "2026". It titles the
    /// checklist; the cadence's own name ("Daily") titles the switch above it.
    public func rangeLabel(on date: Date = .now) -> String {
        switch self {
        case .daily:
            return "Today"
        case .weekly:
            return "This week"
        case .monthly:
            return date.formatted(.dateTime.month(.wide))
        case .annually:
            return date.formatted(.dateTime.year())
        }
    }

    /// The line an empty card shows instead of a checklist. Empty is the
    /// normal state for the outer horizons, so it reads as calm rather than as
    /// something missing.
    public var emptyLine: String {
        switch self {
        case .daily: "Nothing due today."
        case .weekly: "Nothing left this week."
        case .monthly: "Nothing left this month."
        case .annually: "Nothing further out."
        }
    }
}

public extension CaptureStore {
    /// The captures belonging to one horizon, earliest first.
    ///
    /// Anything overdue is folded into **Daily** rather than left behind on a
    /// day nobody scrolls back to: the point of the screen is that everything
    /// dated is visible on it, exactly once.
    func items(in cadence: ScheduleCadence, on date: Date = .now, filter: ItemType? = nil) -> [CaptureItem] {
        let calendar = Calendar.current
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let weekEnd = calendar.dateInterval(of: .weekOfYear, for: date)?.end ?? dayEnd
        let monthEnd = calendar.dateInterval(of: .month, for: date)?.end ?? weekEnd

        return items
            .filter { $0.state != .dismissed }
            .filter { filter == nil || $0.type == filter }
            .compactMap { item in item.dueAt.map { (item, $0) } }
            .filter { _, due in
                switch cadence {
                case .daily: due < dayEnd
                case .weekly: due >= dayEnd && due < weekEnd
                case .monthly: due >= max(dayEnd, weekEnd) && due < monthEnd
                // Open-ended on purpose: a due date past December still has to
                // land somewhere, and the far card is where it belongs.
                case .annually: due >= max(dayEnd, weekEnd, monthEnd)
                }
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// How much of a horizon is already dealt with — the arc around the card's
    /// count. `nil` when the card is empty, so an empty card draws no arc.
    func progress(in cadence: ScheduleCadence, on date: Date = .now) -> Double? {
        let cadenceItems = items(in: cadence, on: date)
        guard !cadenceItems.isEmpty else { return nil }
        let done = cadenceItems.filter { $0.state == .done }.count
        return Double(done) / Double(cadenceItems.count)
    }

    /// Everything landing on one day, earliest first — the timeline's content.
    func items(on day: Date, filter: ItemType? = nil) -> [CaptureItem] {
        let calendar = Calendar.current
        return items
            .filter { $0.state != .dismissed }
            .filter { filter == nil || $0.type == filter }
            .filter { item in
                guard let due = item.dueAt else { return false }
                return calendar.isDate(due, inSameDayAs: day)
            }
            .sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
    }

    /// How much of a day is already dealt with — the arc drawn around that
    /// day's capsule in the rail. `nil` when the day is empty, so an empty day
    /// draws no arc rather than an accusing zero.
    func dayProgress(on day: Date) -> Double? {
        let dayItems = items(on: day)
        guard !dayItems.isEmpty else { return nil }
        let done = dayItems.filter { $0.state == .done }.count
        return Double(done) / Double(dayItems.count)
    }
}
