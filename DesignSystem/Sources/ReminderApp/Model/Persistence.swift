import Foundation
import SwiftData

/// The on-disk shadow of `CaptureItem`.
///
/// The screens deliberately work in value types — Editing takes a copy of a
/// `CaptureItem`, mutates it as a draft, and commits it back only when the
/// user is done — so the model layer keeps two representations rather than
/// one. `StoredCapture` is the reference-typed, SwiftData-managed half that
/// only `CaptureStore` ever touches; everything above the store sees structs.
/// The cost is the mapping below; the benefit is that a half-finished edit
/// can't leak into the list behind it through a shared object identity, which
/// is exactly the bug SwiftData's live objects invite.
///
/// Enums are stored as their raw strings rather than as enum properties. All
/// three (`ItemType`, `Priority`, `CaptureItem.State`) are `String`-backed
/// already, and SwiftData's enum support leans on macro-generated metadata
/// that gets fragile when the enum lives in one module and the `@Model` in
/// another. A raw string is a string in every schema version, survives a case
/// being renamed in code, and degrades to a default instead of failing to
/// open the store.
@Model
public final class StoredCapture {
    /// Unique so `upsert` really is an upsert: the store fetches by id and
    /// writes into the existing row, and the constraint is what makes a
    /// double-insert impossible rather than merely unlikely.
    #Unique<StoredCapture>([\.id])

    public var id: UUID = UUID()
    public var title: String = ""
    /// The whole raw record, flattened. Kept alongside the dated segments
    /// below rather than replaced by them: it is what rows written by earlier
    /// builds already hold, so it is the only thing that can be read back when
    /// there are no segments on disk yet.
    public var transcript: String = ""
    /// `ItemType.rawValue`.
    public var typeRaw: String = ItemType.task.rawValue
    public var dueAt: Date?
    public var followUpAt: Date?
    /// `Priority.rawValue`.
    public var priorityRaw: String = Priority.none.rawValue
    public var confidence: Double = 1.0
    /// `CaptureItem.State.rawValue`.
    public var stateRaw: String = CaptureItem.State.active.rawValue
    public var createdAt: Date = Date.now
    /// See `CaptureItem.summarizedAt`. Optional with no default, so adding it
    /// stays a lightweight migration: rows written by an earlier build come
    /// back with nil, meaning "not known to have been summarized". That is the
    /// safe answer for them — nothing re-summarizes a capture on open, so an
    /// old note keeps the body it already has either way.
    public var summarizedAt: Date?
    /// See `CaptureItem.summarizedBody`. Optional with no default for the same
    /// reason as the stamp above: a row written by an earlier build comes back
    /// with nil, which reads as "no summary on record to have gone stale" and
    /// leaves that note exactly as it is.
    public var summarizedBody: String?
    /// See `CaptureItem.typedAt`. Optional with no default, same as the two
    /// above: a row written before the tag existed comes back with nil, which
    /// reads as "no model has named this category" — so an old note simply
    /// shows no tag until the next re-read gives it one.
    public var typedAt: Date?

    /// This note's meaning as a packed `CaptureVector`, or nil if it has never
    /// been embedded — see `CaptureVector.data` for the layout.
    ///
    /// Optional with no default, the same lightweight-migration shape as the
    /// three stamps above: a row written before the index existed comes back
    /// nil, which reads as "not embedded yet" and puts the note in the backfill
    /// queue. That is exactly right — the vector is derived, so recomputing it
    /// costs nothing but a few milliseconds and loses nothing at all.
    ///
    /// Stored here rather than on `CaptureItem` on purpose. The vector is
    /// machinery, not content: no screen shows it, no edit changes it directly,
    /// and putting it on the value type would push a few hundred floats through
    /// every draft copy Editing makes on every keystroke.
    public var embedding: Data?

    /// The text `embedding` was built from. Answers "is this vector still about
    /// this note?" the way `summarizedBody` answers it for the summary, and for
    /// the same reason: comparing the source is exact, where a date would have
    /// to be kept in step with every edit.
    public var embeddedBody: String?

    /// Children are owned outright: a capture's passages, action items and
    /// questions have no meaning apart from it, so deleting the capture must
    /// take them with it rather than leaving orphans behind to accumulate.
    @Relationship(deleteRule: .cascade, inverse: \StoredPassage.capture)
    public var passages: [StoredPassage]? = []

    /// The raw record, one row per sitting. Optional with an empty default, so
    /// adding it stays a lightweight migration: a row written by an earlier
    /// build comes back with none, and `asValue` rebuilds them from the flat
    /// `transcript` string instead.
    @Relationship(deleteRule: .cascade, inverse: \StoredTranscriptSegment.capture)
    public var transcriptSegments: [StoredTranscriptSegment]? = []

    @Relationship(deleteRule: .cascade, inverse: \StoredActionItem.capture)
    public var actionItems: [StoredActionItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \StoredFollowUpQuestion.capture)
    public var followUpQuestions: [StoredFollowUpQuestion]? = []

    public init(from item: CaptureItem) {
        self.id = item.id
        self.title = item.title
        self.transcript = item.transcript
        self.typeRaw = item.type.rawValue
        self.dueAt = item.dueAt
        self.followUpAt = item.followUpAt
        self.priorityRaw = item.priority.rawValue
        self.confidence = item.confidence
        self.stateRaw = item.state.rawValue
        self.createdAt = item.createdAt
        self.summarizedAt = item.summarizedAt
        self.summarizedBody = item.summarizedBody
        self.typedAt = item.typedAt
        self.passages = []
        self.transcriptSegments = []
        self.actionItems = []
        self.followUpQuestions = []
        applyChildren(item)
    }

    /// Overwrites this row from `item` in place, keeping its object identity so
    /// SwiftData sees an update rather than a delete-and-insert.
    ///
    /// Child collections are replaced wholesale rather than diffed. A capture
    /// carries a handful of passages and action items, never hundreds, so the
    /// cheapest correct thing beats the cleverest one: reconciling by id would
    /// buy nothing measurable and would be the place a reordering or a dropped
    /// child eventually hides.
    public func apply(_ item: CaptureItem) {
        self.id = item.id
        self.title = item.title
        self.transcript = item.transcript
        self.typeRaw = item.type.rawValue
        self.dueAt = item.dueAt
        self.followUpAt = item.followUpAt
        self.priorityRaw = item.priority.rawValue
        self.confidence = item.confidence
        self.stateRaw = item.state.rawValue
        self.createdAt = item.createdAt
        self.summarizedAt = item.summarizedAt
        self.summarizedBody = item.summarizedBody
        self.typedAt = item.typedAt

        // Detach through the context so the cascade rule actually fires;
        // emptying the array alone would leave the old rows in the store with
        // a nil parent.
        if let context = modelContext {
            for passage in passages ?? [] { context.delete(passage) }
            for segment in transcriptSegments ?? [] { context.delete(segment) }
            for action in actionItems ?? [] { context.delete(action) }
            for question in followUpQuestions ?? [] { context.delete(question) }
        }
        passages = []
        transcriptSegments = []
        actionItems = []
        followUpQuestions = []
        applyChildren(item)
    }

    private func applyChildren(_ item: CaptureItem) {
        // `order` is written from the array index here and sorted on the way
        // back out. Passage order is semantically load-bearing — a passage is
        // a dated sitting, and "what I added on Thursday" only means anything
        // if Thursday still comes after Tuesday — and a to-many relationship
        // is a set with no promised order, so the index has to be a real
        // stored field rather than something inferred from the array.
        passages = item.passages.enumerated().map { StoredPassage(from: $1, order: $0) }
        transcriptSegments = item.transcriptSegments.enumerated().map {
            StoredTranscriptSegment(from: $1, order: $0)
        }
        actionItems = item.actionItems.enumerated().map { StoredActionItem(from: $1, order: $0) }
        followUpQuestions = item.followUpQuestions.enumerated().map {
            StoredFollowUpQuestion(from: $1, order: $0)
        }
    }

    /// The dated recordings on disk, or nil if this row has none — an older row
    /// that has not been written since the segments existed.
    private var storedSegments: [CapturePassage]? {
        let rows = (transcriptSegments ?? []).sorted { $0.order < $1.order }
        return rows.isEmpty ? nil : rows.map(\.asValue)
    }

    /// The value-typed view of this row — what the store's in-memory mirror and
    /// every screen above it actually hold.
    ///
    /// Unknown raw strings fall back to the neutral case rather than failing.
    /// A row written by a future build with a new `ItemType` should still open
    /// and still be readable; losing one field beats losing the capture.
    public var asValue: CaptureItem {
        CaptureItem(
            id: id,
            title: title,
            passages: (passages ?? []).sorted { $0.order < $1.order }.map(\.asValue),
            transcript: transcript,
            // Nil, not an empty array, when the row predates the segment
            // table: that is what tells the initializer to cut the flat
            // transcript above into sittings rather than to believe a capture
            // with words in it was never spoken.
            transcriptSegments: storedSegments,
            type: ItemType(rawValue: typeRaw) ?? .task,
            actionItems: (actionItems ?? []).sorted { $0.order < $1.order }.map(\.asValue),
            dueAt: dueAt,
            followUpAt: followUpAt,
            priority: Priority(rawValue: priorityRaw) ?? .none,
            confidence: confidence,
            state: CaptureItem.State(rawValue: stateRaw) ?? .active,
            followUpQuestions: (followUpQuestions ?? []).sorted { $0.order < $1.order }.map(\.asValue),
            createdAt: createdAt,
            summarizedAt: summarizedAt,
            summarizedBody: summarizedBody,
            typedAt: typedAt
        )
    }
}

/// One sitting of body text on disk. See `CapturePassage` for why the date and
/// the position both matter.
@Model
public final class StoredPassage {
    #Unique<StoredPassage>([\.id])

    public var id: UUID = UUID()
    public var text: String = ""
    public var createdAt: Date = Date.now
    /// Position within the capture's body. Not derivable from `createdAt`:
    /// passages are appended in the order they were spoken, and two written in
    /// the same second must still come back in the order the user wrote them.
    public var order: Int = 0
    public var capture: StoredCapture?

    public init(from passage: CapturePassage, order: Int) {
        self.id = passage.id
        self.text = passage.text
        self.createdAt = passage.createdAt
        self.order = order
    }

    public var asValue: CapturePassage {
        CapturePassage(id: id, text: text, createdAt: createdAt)
    }
}

/// One sitting of raw spoken words on disk. Ordered for the same reason the
/// body's passages are: the recordings are a log, and a log read back shuffled
/// is a different log.
@Model
public final class StoredTranscriptSegment {
    #Unique<StoredTranscriptSegment>([\.id])

    public var id: UUID = UUID()
    public var text: String = ""
    public var createdAt: Date = Date.now
    public var order: Int = 0
    public var capture: StoredCapture?

    public init(from segment: CapturePassage, order: Int) {
        self.id = segment.id
        self.text = segment.text
        self.createdAt = segment.createdAt
        self.order = order
    }

    public var asValue: CapturePassage {
        CapturePassage(id: id, text: text, createdAt: createdAt)
    }
}

/// One extracted to-do on disk. Ordered because a list of steps read back
/// shuffled is a different list.
@Model
public final class StoredActionItem {
    #Unique<StoredActionItem>([\.id])

    public var id: UUID = UUID()
    public var text: String = ""
    public var isDone: Bool = false
    public var order: Int = 0
    public var capture: StoredCapture?

    public init(from item: ActionItem, order: Int) {
        self.id = item.id
        self.text = item.text
        self.isDone = item.isDone
        self.order = order
    }

    public var asValue: ActionItem {
        ActionItem(id: id, text: text, isDone: isDone)
    }
}

/// One outstanding question on disk, plus whatever the user has answered so
/// far. Ordered so the questions in Editing don't rearrange themselves under
/// a half-typed answer between launches.
@Model
public final class StoredFollowUpQuestion {
    #Unique<StoredFollowUpQuestion>([\.id])

    public var id: UUID = UUID()
    public var question: String = ""
    public var answer: String = ""
    public var order: Int = 0
    public var capture: StoredCapture?

    public init(from question: FollowUpQuestion, order: Int) {
        self.id = question.id
        self.question = question.question
        self.answer = question.answer
        self.order = order
    }

    public var asValue: FollowUpQuestion {
        FollowUpQuestion(id: id, question: question, answer: answer)
    }
}

/// A single row recording that this store has already been given its seed
/// content.
///
/// Without it, "seed when the store is empty" quietly means "re-seed whenever
/// the user deletes everything" — which is precisely the moment they were most
/// deliberate about wanting an empty list. The marker separates *never been
/// used* from *emptied on purpose*, and those have to behave differently.
@Model
public final class StoreMetadata {
    #Unique<StoreMetadata>([\.key])

    /// There is only ever one of these; the key exists so the constraint has
    /// something to be unique on and so later flags can share the table.
    public var key: String = StoreMetadata.seededKey
    public var didSeed: Bool = false

    public static let seededKey = "captureStore"

    public init(key: String = StoreMetadata.seededKey, didSeed: Bool = false) {
        self.key = key
        self.didSeed = didSeed
    }
}

/// Everything the container has to know about. Kept in one place so the app,
/// the previews and any future test container can't drift out of sync over
/// which types are in the schema.
public enum CaptureSchema {
    public static let models: [any PersistentModel.Type] = [
        StoredCapture.self,
        StoredPassage.self,
        StoredTranscriptSegment.self,
        StoredActionItem.self,
        StoredFollowUpQuestion.self,
        StoreMetadata.self
    ]

    public static var schema: Schema { Schema(models) }

    /// The on-disk container the app runs on. Throwing is deliberate: a store
    /// that won't open is a fact the caller has to decide about (fall back to
    /// memory, or surface it), not something to paper over here.
    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        )
    }
}
