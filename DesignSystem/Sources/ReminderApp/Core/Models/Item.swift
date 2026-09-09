import Foundation

/// The structured, working record the user actually sees — the `Item` from
/// the data model, trimmed to the fields the three screens read or write.
///
/// A value type on purpose: Home renders a snapshot, Editing works on a
/// mutable copy and commits it back, so a half-finished edit can never leak
/// into the list behind it.
public struct CaptureItem: Identifiable, Hashable, Sendable {
    public var id: UUID
    /// AI-generated and AI-owned — never typed by hand. It is the AI's read of
    /// the body, so it changes only when the body's content changes, and
    /// switching the body between summary and transcript leaves it alone.
    /// This is the row's first line.
    public var title: String
    /// The body, split into the sittings that produced it. The first passage is
    /// the AI's summary of the original capture; every later one is something
    /// the user came back and added — by voice, days later, on top of what was
    /// already written. Editing shows them as dated sections, in order.
    ///
    /// A capture is a thing you keep thinking about, so the body is a log, not
    /// a field: adding never overwrites, and the day each part arrived is part
    /// of what it means.
    public var passages: [CapturePassage]
    /// The immutable thing the user actually said, one entry per time you said
    /// something. Never edited, only shown.
    ///
    /// Dated the same way the body is, and for the same reason: a capture
    /// spoken into three times over a week is three recordings, not one long
    /// one, and "See Original" is where you go to hear which words came from
    /// which day. Flattening them into a single blob loses exactly the fact
    /// that makes the raw record worth keeping.
    public var transcriptSegments: [CapturePassage]

    /// Everything ever spoken about this capture, in the order it was spoken —
    /// what search matches, what Home previews when there is no body yet, and
    /// what a re-run of the summary is fed.
    ///
    /// Read-only: the transcript grows a sitting at a time through
    /// `appendTranscript`, so there is no way to flatten the recordings by
    /// accident.
    public var transcript: String {
        transcriptSegments
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
    public var type: ItemType
    public var actionItems: [ActionItem]
    public var dueAt: Date?
    public var followUpAt: Date?
    public var priority: Priority
    /// How sure the AI was. Below `needsReviewThreshold` the item is flagged
    /// on Home rather than silently filed — the plan's "never a dead end" rule.
    public var confidence: Double
    public var state: State
    /// Gaps the AI noticed and wants filled, answerable inline in Editing.
    public var followUpQuestions: [FollowUpQuestion]
    public var createdAt: Date
    /// When the model wrote this capture's summary, or nil if it never has.
    ///
    /// The rewrite is a once-per-capture job, and this is what makes that true
    /// across relaunches: it is written to disk with everything else, so the
    /// question "has this note been framed yet?" is answered by the note rather
    /// than by whichever screen happens to be open. Re-opening a capture reads
    /// what is stored; it does not regenerate it.
    ///
    /// A date rather than a `Bool` because the useful follow-up question is
    /// always *when* — a capture summarized before a prompt changed is the one
    /// worth offering to re-run, and a flag cannot answer that.
    public var summarizedAt: Date?

    /// The body exactly as the last summary left it, or nil if the model has
    /// never written one.
    ///
    /// The one thing `summarizedAt` cannot answer: *is the summary still about
    /// this note?* A note you have since dictated two more sections into, or
    /// edited a paragraph of, has a summary describing a note that no longer
    /// exists — and the page should say so rather than leave a stale reading
    /// standing as the capture's own words.
    ///
    /// The body itself rather than a hash or a date, because it is a few
    /// hundred bytes and comparing it is exact. A date would have to be kept in
    /// step with every keystroke; a hash would answer the same question while
    /// being unreadable in a store dump.
    public var summarizedBody: String?

    /// When the model last decided which shelf this note belongs on, or nil if
    /// it never has.
    ///
    /// Every capture has a `type` from the moment it exists — `TriageEngine`
    /// guesses one on device so nothing is ever unfiled — but a guess made from
    /// keywords in the first sentence is not a reading of the note, and Editing
    /// should not put a tag under the heading claiming otherwise. This is what
    /// separates the two: the tag appears once a model has actually read the
    /// note and named the category, and it survives relaunches for the same
    /// reason `summarizedAt` does.
    public var typedAt: Date?

    /// Whether the note has moved on since the model last read it.
    ///
    /// False for a note that was never summarized — there is nothing to be
    /// stale — and false for a row written by a build before this field
    /// existed, which is the safe answer: an old note keeps the body it has,
    /// and the worst case is one summary the app doesn't offer to refresh.
    public var isSummaryStale: Bool {
        guard let summarizedBody else { return false }
        return summarizedBody != summary
    }

    public static let needsReviewThreshold = 0.6

    public var needsReview: Bool { confidence < Self.needsReviewThreshold }

    /// The whole body as one string — what Home previews, what search matches,
    /// and what the title is regenerated from. Read-only on purpose: the body
    /// is only ever written a passage at a time, so there is no way to flatten
    /// the sections by accident.
    public var summary: String {
        passages
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// When the body last grew. Home still sorts by `createdAt` — a capture
    /// stays where you left it in the list — but this is what a section's
    /// eyebrow reads out.
    public var lastAddedAt: Date {
        passages.map(\.createdAt).max() ?? createdAt
    }

    /// Opens a new dated section on the end of the body and returns its id, so
    /// the caller can keep writing into it as words arrive.
    @discardableResult
    public mutating func openPassage(at date: Date = .now) -> UUID {
        let passage = CapturePassage(text: "", createdAt: date)
        passages.append(passage)
        return passage.id
    }

    /// Logs one sitting's worth of spoken words onto the end of the raw record.
    public mutating func appendTranscript(_ spoken: String, at date: Date = .now) {
        let trimmed = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcriptSegments.append(CapturePassage(text: trimmed, createdAt: date))
    }

    /// Cuts a flat transcript back into its sittings.
    ///
    /// Appends were written as blank-line-separated paragraphs long before the
    /// recordings carried their own dates, so a stored string is still the only
    /// record for anything captured by an earlier build — and for the seeds.
    /// The paragraphs are dated off the body's passages where the counts line
    /// up, since a sitting produces one of each; anything left over falls back
    /// to the capture's own date, which is the honest answer when the real one
    /// was never written down.
    static func segments(
        splitting transcript: String,
        alongside passages: [CapturePassage],
        createdAt: Date
    ) -> [CapturePassage] {
        transcript
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, text in
                CapturePassage(
                    text: text,
                    createdAt: index < passages.count ? passages[index].createdAt : createdAt
                )
            }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        passages: [CapturePassage]? = nil,
        transcript: String = "",
        transcriptSegments: [CapturePassage]? = nil,
        type: ItemType = .task,
        actionItems: [ActionItem] = [],
        dueAt: Date? = nil,
        followUpAt: Date? = nil,
        priority: Priority = .none,
        confidence: Double = 1.0,
        state: State = .active,
        followUpQuestions: [FollowUpQuestion] = [],
        createdAt: Date = .now,
        summarizedAt: Date? = nil,
        summarizedBody: String? = nil,
        typedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        // A one-sitting capture is just a one-section body: the summary the AI
        // wrote, dated the day it was said.
        self.passages = passages
            ?? (summary.isEmpty ? [] : [CapturePassage(text: summary, createdAt: createdAt)])
        self.transcriptSegments = transcriptSegments
            ?? Self.segments(
                splitting: transcript,
                alongside: self.passages,
                createdAt: createdAt
            )
        self.type = type
        self.actionItems = actionItems
        self.dueAt = dueAt
        self.followUpAt = followUpAt
        self.priority = priority
        self.confidence = confidence
        self.state = state
        self.followUpQuestions = followUpQuestions
        self.createdAt = createdAt
        self.summarizedAt = summarizedAt
        self.summarizedBody = summarizedBody
        self.typedAt = typedAt
    }

    public enum State: String, Sendable {
        case active, snoozed, done, dismissed
    }
}

/// One sitting's worth of body text, and the day it arrived.
///
/// Passages are never merged and never reordered: a thought added on Thursday
/// keeps saying Thursday, which is most of why anyone re-reads an old capture
/// at all. Text stays exactly as it was dictated or typed — nothing here is
/// summarized, tidied or rewritten after the fact.
public struct CapturePassage: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    /// The date the section's eyebrow reads out.
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// The AI's classification of a capture. Doubles as Home's filter set, which
/// is why it carries its own label and SF Symbol.
///
/// Case order is the order Home's tabs and Editing's type picker read in — a
/// fixed, learnable shelf order, most-used first.
public enum ItemType: String, CaseIterable, Identifiable, Sendable {
    case idea, task, event, shopping, someday

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .task: "Task"
        case .event: "Event"
        case .idea: "Idea"
        case .shopping: "Shopping"
        case .someday: "Someday"
        }
    }

    /// Plural form, used for Home's section headers.
    public var sectionTitle: String {
        switch self {
        case .task: "Tasks"
        case .event: "Events"
        case .idea: "Ideas"
        case .shopping: "Shopping"
        case .someday: "Someday"
        }
    }

    /// The shelf a model named, or nil when it named something this app has no
    /// shelf for. Lenient about case, whitespace and the plural, because those
    /// are the three ways a model answers "shopping" with "Shopping " — and
    /// strict about everything else: an unrecognised word means the note keeps
    /// the shelf it is on rather than being filed somewhere invented.
    public static func named(_ raw: String) -> ItemType? {
        let word = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !word.isEmpty else { return nil }
        return allCases.first { $0.rawValue == word || $0.sectionTitle.lowercased() == word }
    }

    public var symbol: String {
        switch self {
        case .task: "checkmark.circle"
        case .event: "calendar"
        case .idea: "lightbulb"
        case .shopping: "cart"
        case .someday: "moon.zzz"
        }
    }
}

public enum Priority: String, CaseIterable, Identifiable, Sendable {
    case none, low, medium, high

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// One extracted to-do inside a capture. A long session yields several; a
/// three-second quick capture usually yields one or none.
public struct ActionItem: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var isDone: Bool

    public init(id: UUID = UUID(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }
}

/// A gap the AI noticed ("which Tuesday?"). Answering it in Editing is
/// optional — the item saves fine with the question left hanging.
public struct FollowUpQuestion: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var question: String
    public var answer: String

    public init(id: UUID = UUID(), question: String, answer: String = "") {
        self.id = id
        self.question = question
        self.answer = answer
    }
}
