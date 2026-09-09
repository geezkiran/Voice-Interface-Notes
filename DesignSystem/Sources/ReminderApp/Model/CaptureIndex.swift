import Foundation

/// Everything the app has ever captured, as vectors — the thing that lets a new
/// note be asked "have I said this before?".
///
/// This is the app's vector database, and it is a dictionary. That is the right
/// size for the problem rather than a shortcut: one person's notes number in the
/// hundreds, maybe low thousands after years, and a brute-force cosine over a
/// few thousand 512-float vectors is a few hundred microseconds of straight-line
/// arithmetic — faster than the approximate index that would replace it, with no
/// build step, no tuning, no staleness and no dependency. The seam is
/// `nearest(to:)`; the day a real ANN index is warranted, that method changes
/// and nothing above it does.
///
/// It mirrors `CaptureStore.items` in both shape and spirit: loaded once, kept
/// current by the same mutations that write to disk, never invalidated and
/// re-fetched. See `CaptureStore`'s class doc for why that matters.
/// Not `@Observable`: no screen reads it. The index answers a question the
/// proposal machinery asks and nothing renders from it, so making it observable
/// would add tracking overhead to a type nothing is watching.
@MainActor
public final class CaptureIndex {
    /// Vectors by capture id. Only notes that have one appear — a note whose
    /// text produced no vector is simply absent, and absence is what the
    /// backfill looks for.
    private var vectors: [UUID: CaptureVector] = [:]

    /// The text each vector was built from.
    ///
    /// The same question `summarizedBody` answers for the summary — *is this
    /// still about the note it describes?* — and answered the same way, by
    /// keeping the source rather than a hash or a date. A note dictated into
    /// twice more has a vector describing a note that no longer exists, and
    /// comparing the text is the only exact way to know.
    private var sources: [UUID: String] = [:]

    /// The producer everything in this index must have been made by, fixed for
    /// the life of the session.
    ///
    /// Vectors from different producers cannot be compared, so a mixed index is
    /// one where notes silently stop matching each other. Rather than letting
    /// that happen and hoping the `nil` from `cosine` is handled everywhere, the
    /// index simply declares which kind it holds: anything else is stale and
    /// gets re-embedded. That makes the day the contextual model becomes
    /// available a one-launch backfill rather than a permanent split brain.
    private var kind: CaptureVector.Kind = .sentence

    public init() {}

    /// Fixes the producer for this session. Called once, before anything is
    /// hydrated or embedded.
    func adopt(_ kind: CaptureVector.Kind) {
        self.kind = kind
    }

    // MARK: Reading

    /// Whether this note's vector is current: it exists, it was made from these
    /// exact words, and it came from the producer this session is using.
    public func isCurrent(_ item: CaptureItem, source: String) -> Bool {
        guard let vector = vectors[item.id] else { return false }
        return vector.kind == kind && sources[item.id] == source
    }

    public func vector(for id: UUID) -> CaptureVector? { vectors[id] }

    /// The notes most like this one, best first.
    ///
    /// `floor` is the whole difference between a useful shortlist and a
    /// nuisance. Cosine over pooled embeddings runs high — two unrelated work
    /// notes routinely sit around 0.4 simply for sharing a register — so the bar
    /// has to be well above "vaguely related" before a candidate is worth a
    /// model's attention. It is deliberately not a merge threshold: everything
    /// that clears it is still only a *candidate*, and the model decides.
    public func nearest(
        to vector: CaptureVector,
        excluding excluded: Set<UUID> = [],
        limit: Int = 5,
        floor: Double = 0.55
    ) -> [(id: UUID, score: Double)] {
        vectors
            .compactMap { id, stored -> (id: UUID, score: Double)? in
                guard !excluded.contains(id) else { return nil }
                guard let score = CaptureVector.cosine(vector, stored), score >= floor else {
                    return nil
                }
                return (id, score)
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Writing

    /// Takes a vector only if it was made by this session's producer. A vector
    /// of the wrong kind is not a lesser answer to keep around — it is one the
    /// search would have to skip on every query, so it is left out and the note
    /// stays on the backfill's list.
    public func store(_ vector: CaptureVector, source: String, for id: UUID) {
        guard vector.kind == kind else { return }
        vectors[id] = vector
        sources[id] = source
    }

    public func remove(_ id: UUID) {
        vectors.removeValue(forKey: id)
        sources.removeValue(forKey: id)
    }

    /// Every note the index has no current vector for, oldest first — the
    /// backfill's worklist.
    ///
    /// Oldest first because the backfill runs at launch behind whatever the user
    /// is already doing, and the notes they are about to be compared against are
    /// the ones that have been sitting there longest. A note captured this
    /// minute is embedded on its own save anyway.
    func stale(in items: [CaptureItem]) -> [CaptureItem] {
        items
            .filter { $0.state != .dismissed }
            .filter { !isCurrent($0, source: CaptureIndex.embeddableText(of: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// What a note is vectorised *from*.
    ///
    /// The raw words, not the summary. Two reasons, and both are about asking
    /// the same question of every note: the transcript exists from the moment a
    /// capture is saved, long before anything has summarised it, so using it
    /// means a note is comparable immediately rather than only after a model has
    /// read it; and it is the one representation a rewrite can never change, so
    /// a note's position in this index doesn't move because its prose was
    /// tidied. A typed note has no transcript, and its body is the only thing it
    /// ever had — so that stands in.
    /// `nonisolated` because it is pure string handling over a value type, and
    /// the proposer asks it off the main actor before it has any reason to touch
    /// the store.
    nonisolated static func embeddableText(of item: CaptureItem) -> String {
        let spoken = item.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spoken.isEmpty { return spoken }
        return item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
