import Foundation
import NaturalLanguage

/// One note's meaning, as a number the app can compare against another note's.
///
/// The `kind` is not decoration. Two producers make vectors here — the
/// contextual model and the older sentence model — and their coordinate spaces
/// have nothing to do with each other. A cosine taken across the two is a
/// plausible-looking number computed from noise, which is the worst kind of bug
/// to have in a similarity search: it never crashes, it just quietly suggests
/// merging unrelated notes. So the kind travels with the values, is written to
/// disk with them, and `cosine` refuses any pair that disagrees.
public struct CaptureVector: Sendable, Equatable {
    /// Which model produced this. Raw values are written to disk, so they are
    /// fixed forever — a new producer takes a new number rather than reusing one.
    public enum Kind: UInt8, Sendable {
        case contextual = 1
        case sentence = 2
    }

    public let kind: Kind
    /// Unit length, always. Normalising once at construction turns every later
    /// cosine into a plain dot product, and the comparison is the thing that
    /// runs in a loop over every note.
    public let values: [Float]

    public init?(kind: Kind, values: [Float]) {
        guard !values.isEmpty else { return nil }
        var magnitude: Float = 0
        for value in values { magnitude += value * value }
        magnitude = magnitude.squareRoot()
        // A zero vector carries no direction, so there is nothing to normalise
        // and nothing to compare it against. Refusing here means the caller
        // stores no vector at all rather than one that matches everything
        // equally badly.
        guard magnitude > 1e-6, magnitude.isFinite else { return nil }
        self.kind = kind
        self.values = values.map { $0 / magnitude }
    }

    /// How alike two notes are, from -1 to 1. Nil when the two were made by
    /// different producers or somehow differ in width — the honest answer to
    /// "how similar are these?" when the question can't be asked.
    public static func cosine(_ a: CaptureVector, _ b: CaptureVector) -> Double? {
        guard a.kind == b.kind, a.values.count == b.values.count else { return nil }
        var total: Float = 0
        for index in a.values.indices {
            total += a.values[index] * b.values[index]
        }
        return Double(total)
    }

    // MARK: On-disk form

    /// A one-byte kind tag followed by little-endian `Float32`s.
    ///
    /// Hand-packed rather than `Codable`: this is a few hundred numbers written
    /// on every note save, and JSON would triple the size while making the
    /// column unreadable in a store dump. The explicit endianness is what makes
    /// the blob mean the same thing on any machine that later opens the store.
    public var data: Data {
        var bytes = Data(capacity: 1 + values.count * 4)
        bytes.append(kind.rawValue)
        for value in values {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        }
        return bytes
    }

    /// Reads a blob back, or nil if it is malformed or was written by a build
    /// that knew a producer this one doesn't. Nil means "no vector on record",
    /// which sends the note through the backfill — never an error.
    public init?(data: Data) {
        guard data.count > 1, (data.count - 1) % 4 == 0 else { return nil }
        guard let kind = Kind(rawValue: data[data.startIndex]) else { return nil }
        var values: [Float] = []
        values.reserveCapacity((data.count - 1) / 4)
        var index = data.index(after: data.startIndex)
        while index < data.endIndex {
            var pattern: UInt32 = 0
            for offset in 0..<4 {
                pattern |= UInt32(data[data.index(index, offsetBy: offset)]) << (8 * UInt32(offset))
            }
            values.append(Float(bitPattern: pattern))
            index = data.index(index, offsetBy: 4)
        }
        // Already unit length on disk; re-normalising is harmless and repairs a
        // blob written before a producer change.
        self.init(kind: kind, values: values)
    }
}

/// Turns a note's words into a `CaptureVector`, entirely on this device.
///
/// No key, no network, no provider. That is the whole reason this is Apple's
/// model rather than an embeddings API: the similarity lookup runs on the
/// capture path, moments after the user stops speaking, and putting a network
/// round-trip there would make the one flow the app promises always to work
/// depend on a connection. The model that reads the note *afterwards* is
/// allowed to need the network, because by then the note is already saved.
public enum CaptureEmbedder {
    /// A note's subject is established in its first breath; the rest is detail.
    /// Pooling ten thousand characters into one 512-dimensional vector averages
    /// the note into mush, and the mush is what makes everything look alike.
    static let characterBudget = 2000

    /// The best producer this device can use *for this whole session*.
    ///
    /// Decided once and held, rather than asked per note, because a vector is
    /// only ever compared against vectors of the same kind. A session that
    /// started on the sentence model and switched to the contextual one halfway
    /// through would write an index whose two halves cannot see each other —
    /// every note captured after the switch would find no candidates at all,
    /// which looks exactly like "nothing similar" and would be nearly impossible
    /// to notice. One answer per launch makes the index internally consistent by
    /// construction; the upgrade lands on the next launch instead, where the
    /// backfill re-embeds everything because the stored kind no longer matches.
    public static func preferredKind() async -> CaptureVector.Kind {
        await ContextualEmbedder.shared.isReady ? .contextual : .sentence
    }

    /// Asks the OS for the contextual model, if this device hasn't got it.
    ///
    /// Nothing this launch will use the result — `preferredKind` has already
    /// been decided and the session is committed to it. This is groundwork for
    /// the *next* launch, which is why it is safe to call from the backfill and
    /// safe to have take as long as it takes.
    ///
    /// Without this the contextual branch above would be unreachable code: the
    /// assets are never present until something asks for them, so a device that
    /// never asks stays on the sentence model forever.
    public static func prepareAssets() async {
        await ContextualEmbedder.shared.requestAssetsIfNeeded()
    }

    /// The vector for a note's text, or nil if no producer on this device could
    /// make one.
    ///
    /// Nil is a supported outcome, not a failure: the index then falls back to
    /// offering the most recent notes as candidates, and the model still gets to
    /// adjudicate. Nothing about this feature is allowed to leave a capture
    /// unhandled.
    public static func vector(for text: String) async -> CaptureVector? {
        let source = String(
            text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(characterBudget)
        )
        guard !source.isEmpty else { return nil }

        if let contextual = await ContextualEmbedder.shared.vector(for: source) {
            return contextual
        }
        return sentenceVector(for: source)
    }

    /// The fallback producer: the older static sentence embedding, mean-pooled
    /// over the note's sentences.
    ///
    /// Worse than the contextual model — it has no idea what surrounds a word —
    /// but it ships in the OS with no asset download at all, so it is what a
    /// device that has never had a chance to fetch the contextual model uses.
    private static func sentenceVector(for text: String) -> CaptureVector? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }

        var pooled = [Double](repeating: 0, count: embedding.dimension)
        var counted = 0

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty, let vector = embedding.vector(for: sentence) else { return true }
            for index in vector.indices where index < pooled.count {
                pooled[index] += vector[index]
            }
            counted += 1
            return true
        }

        guard counted > 0 else { return nil }
        return CaptureVector(kind: .sentence, values: pooled.map { Float($0 / Double(counted)) })
    }
}

/// Holds the contextual model, which is expensive to load and must be loaded
/// exactly once.
///
/// An actor rather than a cached global because loading is asynchronous and can
/// be asked for from two places at once — the backfill sweeping old notes and a
/// capture that just finished. Two concurrent loads of the same model is the
/// bug this serialises away. Nothing non-`Sendable` leaves: the model and its
/// results are created, read and dropped inside, and only `[Float]` comes out.
private actor ContextualEmbedder {
    static let shared = ContextualEmbedder()

    /// What happened the first time somebody asked. Held so a device without
    /// the assets tries once and then stops — the sentence fallback is a fine
    /// answer, and retrying an unavailable download on every capture is not.
    private enum State {
        case unasked
        case ready(NLContextualEmbedding)
        case unavailable
    }

    private var state: State = .unasked

    /// Whether the contextual model is usable right now, without downloading
    /// anything. Asked once per launch by `CaptureEmbedder.preferredKind`.
    var isReady: Bool { load() != nil }

    /// Fetches the model for next time, if it isn't already here.
    ///
    /// Deliberately does not touch `state`: this launch has already committed to
    /// a producer, and quietly upgrading mid-session would split the index into
    /// two mutually invisible halves. Errors are dropped — a failed download
    /// means the sentence model keeps the job, which is a working app.
    func requestAssetsIfNeeded() async {
        guard case .unavailable = state else { return }
        guard let model = NLContextualEmbedding(language: .english) else { return }
        guard !model.hasAvailableAssets else { return }
        _ = try? await model.requestAssets()
    }

    func vector(for text: String) -> CaptureVector? {
        guard let model = load() else { return nil }
        guard let result = try? model.embeddingResult(for: text, language: .english) else {
            return nil
        }

        // Mean pooling: the model gives one vector per token, and a note is a
        // point rather than a sequence for our purposes. Averaging is the
        // standard, unglamorous way to get from one to the other, and at this
        // scale it beats anything cleverer that would need tuning.
        var pooled = [Double](repeating: 0, count: model.dimension)
        var counted = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            for index in vector.indices where index < pooled.count {
                pooled[index] += vector[index]
            }
            counted += 1
            return true
        }

        guard counted > 0 else { return nil }
        return CaptureVector(kind: .contextual, values: pooled.map { Float($0 / Double(counted)) })
    }

    /// The model, loading it on the first call.
    ///
    /// Deliberately does *not* request an asset download. `requestAssets` can
    /// sit on the network for a long time, and this is called moments after the
    /// user stopped speaking; the sentence fallback answers immediately and is
    /// what the first few captures on a fresh install will use. The assets
    /// arrive on their own soon enough, and every note is re-embedded when they
    /// do because the stored kind no longer matches.
    private func load() -> NLContextualEmbedding? {
        switch state {
        case let .ready(model):
            return model
        case .unavailable:
            return nil
        case .unasked:
            guard
                let model = NLContextualEmbedding(language: .english),
                model.hasAvailableAssets,
                (try? model.load()) != nil
            else {
                state = .unavailable
                return nil
            }
            state = .ready(model)
            return model
        }
    }
}
