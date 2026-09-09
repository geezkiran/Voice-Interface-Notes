import Foundation

/// What the model thinks should happen to a capture that was just spoken —
/// leave it alone, add it to a note that already exists, or break it into
/// several.
///
/// The third frontier type in this file's family, alongside `CaptureAnalysis`
/// (rewrite the body) and `CaptureRefinement` (re-read the heading). It is an
/// enum rather than a struct with optional fields for the same reason
/// `CaptureRefinement` is its own type rather than a half-filled analysis: the
/// three outcomes do genuinely different things to the store, and a shape that
/// can express "merge into nothing" or "split into one part" is a shape where
/// those become runtime bugs instead of unrepresentable states.
///
/// Nothing here touches the store. A proposal is a suggestion sitting in a
/// screen's state until somebody taps a button — which is the entire design:
/// the app never reorganises a person's notes on its own.
public enum CaptureProposal: Sendable, Equatable {
    /// The capture is one note about one thing, and nothing like it exists yet.
    /// By far the most common answer, and the one every ambiguity resolves to.
    case keep

    /// This is another sitting of a note that already exists. `reason` is one
    /// sentence in the speaker's own words — it is the card's headline, and a
    /// generic one ("these are similar") makes the card worthless.
    case merge(into: UUID, reason: String)

    /// Two or more notes were spoken in one breath. Ordered as they were said.
    case split(reason: String, parts: [Part])

    /// One note-to-be: a heading, the share of the body that belongs to it, and
    /// the shelf it goes on.
    public struct Part: Sendable, Equatable {
        public var title: String
        public var body: String
        public var type: ItemType?

        public init(title: String, body: String, type: ItemType? = nil) {
            self.title = title
            self.body = body
            self.type = type
        }
    }

    /// Whether there is anything to show the user. `keep` is an answer, not a
    /// proposal — there is no card for "I did nothing".
    public var isActionable: Bool {
        if case .keep = self { return false }
        return true
    }

    // MARK: Prompt

    /// Blunt in the same way the other two prompts in this app are blunt, and
    /// for the same reason: every emphatic line is aimed at a specific thing
    /// models do when asked this question.
    ///
    /// The big one is that a model asked "should this be split?" will split
    /// almost anything — asked to look for structure it finds structure, and a
    /// note with two paragraphs comes back as two notes. The second is that
    /// "related" and "the same thing" collapse into each other: two notes about
    /// the same project read as duplicates to a model even when one is a
    /// shopping list and the other is an argument. Both failures are expensive
    /// in a way the user feels — a wrong split scatters one thought across two
    /// notes, and a wrong merge buries a new thought inside an old note — so the
    /// prompt is weighted hard towards leaving things alone.
    public static let systemPrompt = """
    You are looking at a note a person has just spoken into their notebook, and
    at a few notes they wrote earlier. You decide one thing: should this new note
    be left exactly as it is, added onto one of the earlier notes, or broken into
    separate notes?

    Return ONE JSON object and nothing else. No preamble, no code fences, no
    trailing commentary. Its keys must appear in exactly this order:
    "action", "reason", "merge_into", "parts".

    EVERY value you return is PLAIN TEXT ONLY. No markdown, ever. No #, ##, or
    any other heading marks. No *, **, _ or __ for bold or italic. No -, *, +,
    or 1. as bullet or list markers. No backticks, no code fences, no tables, no
    links, no blockquotes, no horizontal rules. The only formatting available to
    you is ordinary sentences, line breaks and blank lines.

    ────────────────────────────────

    ACTION — exactly one of: "keep", "merge", "split".

    "keep" IS THE DEFAULT AND THE MOST COMMON ANSWER. Choose it whenever you are
    not certain. A note left alone costs the person nothing; a wrong split
    scatters one thought across two notes, and a wrong merge buries a new thought
    inside an old one. When you are weighing keep against either other option,
    choose keep.

    ────────────────────────────────

    MERGE — the new note is another sitting of a note that already exists.

    Merge ONLY when the new note and the earlier note are about THE SAME SPECIFIC
    THING: the same task, the same event, the same decision, the same object.
    The test is whether the person, re-reading them a month later, would be
    confused to find them apart.

    Do NOT merge because two notes:
    share a project, a person, a place or a topic;
    are both about work, or both about the house, or both about the same trip;
    would sit in the same category or on the same shelf;
    use similar words.
    Same subject area is NOT the same note. Two separate tasks for one project
    are two notes. A new idea about something you have thought about before is
    only a merge if it is genuinely more of THAT thought, not a fresh one
    standing beside it.

    "merge_into" is the id number of the earlier note, taken from the list in the
    user message. Use the number exactly as given. Never invent an id, and never
    merge into a note that is not in the list.

    ────────────────────────────────

    SPLIT — two or more unrelated things were said in one breath.

    Split ONLY when the parts have nothing to do with each other: different
    subject, different purpose, nothing either part needs from the other to make
    sense. The test is whether each part, on its own with its own title, is a
    note the person would open on purpose.

    Do NOT split:
    a single subject discussed at length, however long;
    reasoning followed by the things to do about it — the things to do are action
    items on one note, not notes of their own;
    a topic with several aspects, stages, options or sections — those are
    paragraphs, or at most headings, inside ONE note;
    a decision and its consequences;
    anything where one part opens by referring back to the other ("and while I'm
    at it", "which reminds me" is a genuine topic change, but "so that means"
    is not).
    A long note is not a reason to split. Length is not structure.

    "parts" is an array of 2 to 4 objects, in the order the things were said.
    Each has "title", "body", and "type".
    "title": concrete and specific, at most nine words, sentence case, no trailing
    punctuation. The standard is a good chat title.
    "body": that part's share of the note, in the person's own words. Reorganise
    what was said; never summarise it, expand it, or add a sentence that was not
    there. Every fact, number, name, date, place and qualifier belonging to that
    part survives into its body. First person, the speaker's own vocabulary and
    tense, ordinary sentences and paragraphs. Between them the parts must account
    for everything said — nothing may be dropped, and nothing may appear twice.
    "type": exactly one of "idea", "task", "event", "shopping", "someday", chosen
    from what that part as a whole IS.
    task — something to be done, with a doer and an outcome.
    event — something happening at a time, attended rather than completed.
    shopping — things to acquire or buy.
    idea — a thought being worked out: a possibility, a design, an argument.
    someday — a wish or intention with no commitment and no timeframe.

    ────────────────────────────────

    REASON — one short sentence, said to the person, in their own vocabulary,
    naming the specific things involved. It is the only explanation they will
    see, and they are deciding from it.
    Good: "This starts on the Q3 launch date and then moves to booking the
    dentist."
    Good: "You said more about the car insurance quotes you noted last week."
    Bad: "The note contains two distinct topics." — names nothing.
    Bad: "These notes are semantically similar." — describes your process, not
    their note.
    For "keep", return an empty string.

    ────────────────────────────────

    Unused keys still appear, empty: "merge_into" is null unless the action is
    "merge", and "parts" is an empty array unless the action is "split".
    """

    /// The new note, then the shortlist it might belong to.
    ///
    /// Candidates are numbered `1`, `2`, `3` rather than carrying their UUIDs.
    /// A model asked to echo a 36-character identifier back will eventually
    /// mistype one, and a mistyped id is a merge into the wrong note — or, if it
    /// matches nothing, a proposal silently dropped. A single digit is
    /// unmistakable, and the mapping back lives in `CaptureProposer` where it
    /// can be checked.
    ///
    /// Each candidate is shown short: its heading, when it last grew, and the
    /// opening of its body. That is what a person skims to answer "is this the
    /// same thing?", and sending whole notes would put five long documents in
    /// front of the model to decide one question about a sixth.
    public static func userPrompt(
        note: String,
        candidates: [(number: Int, item: CaptureItem)],
        now: Date = .now
    ) -> String {
        var prompt = """
        \(CaptureAnalysis.timeContext(now: now))

        The note just spoken:
        \(note)
        """

        if candidates.isEmpty {
            prompt += """


            There are no earlier notes to compare against, so "merge" is not
            available. Decide only between "keep" and "split".
            """
            return prompt
        }

        let list = candidates.map { number, item in
            let body = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = body.isEmpty ? item.transcript : body
            let excerpt = String(text.prefix(400))
            return """
            [\(number)] \(item.title.isEmpty ? "(untitled)" : item.title)
            Last added to \(item.lastAddedAt.formatted(date: .abbreviated, time: .shortened))
            \(excerpt)
            """
        }.joined(separator: "\n\n")

        prompt += """


        Earlier notes it might belong to:
        \(list)
        """
        return prompt
    }

    // MARK: Decoding

    /// Reads the model's answer, given the id mapping the prompt used.
    ///
    /// Nil rather than a throw, exactly as `CaptureAnalysis.complete` and
    /// `CaptureRefinement.complete` do: an unreadable answer here means no card
    /// appears, which is the same outcome as "keep" and is not something the
    /// user should ever be told about.
    ///
    /// Every way the answer can be wrong collapses to `keep`: a merge into a
    /// number that wasn't offered, a split into one part or five, a split whose
    /// parts have no words in them. The model gets to propose, never to insist.
    public static func complete(_ raw: String, numbering: [Int: UUID]) -> CaptureProposal? {
        guard let data = CaptureAnalysis.jsonBody(of: raw) else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }

        let reason = payload.reason.trimmingCharacters(in: .whitespacesAndNewlines)

        switch payload.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "merge":
            guard let number = payload.mergeInto, let id = numbering[number] else { return .keep }
            guard !reason.isEmpty else { return .keep }
            return .merge(into: id, reason: reason)

        case "split":
            let parts = payload.parts
                .map {
                    Part(
                        title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        body: $0.body.trimmingCharacters(in: .whitespacesAndNewlines),
                        type: $0.type
                    )
                }
                .filter { !$0.body.isEmpty && !$0.title.isEmpty }
            // Fewer than two is not a split, and beyond four the model has
            // stopped finding topics and started finding paragraphs.
            guard (2...4).contains(parts.count), !reason.isEmpty else { return .keep }
            return .split(reason: reason, parts: parts)

        default:
            return .keep
        }
    }

    /// The wire shape. Kept private so the model's snake_case and its tolerance
    /// for nonsense never leak into the enum above.
    private struct Payload: Decodable {
        var action: String
        var reason: String
        var mergeInto: Int?
        var parts: [PartPayload]

        enum CodingKeys: String, CodingKey {
            case action, reason, parts
            case mergeInto = "merge_into"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            action = (try? container.decode(String.self, forKey: .action)) ?? "keep"
            reason = (try? container.decode(String.self, forKey: .reason)) ?? ""
            parts = (try? container.decode([PartPayload].self, forKey: .parts)) ?? []
            // Some models answer with "2" rather than 2, and some with the
            // bracketed form they were shown. All three name the same note.
            if let number = try? container.decodeIfPresent(Int.self, forKey: .mergeInto) {
                mergeInto = number
            } else if let text = try? container.decodeIfPresent(String.self, forKey: .mergeInto) {
                mergeInto = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")))
            } else {
                mergeInto = nil
            }
        }

        struct PartPayload: Decodable {
            var title: String
            var body: String
            var type: ItemType?

            enum CodingKeys: String, CodingKey {
                case title, body, type
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                title = (try? container.decode(String.self, forKey: .title)) ?? ""
                body = (try? container.decode(String.self, forKey: .body)) ?? ""
                let rawType = try? container.decodeIfPresent(String.self, forKey: .type)
                type = rawType.flatMap(ItemType.named)
            }
        }
    }
}

/// Works out what to propose about a capture, if anything.
///
/// Two stages, and the split between them is the point. The on-device index
/// narrows every note ever captured down to a handful of candidates for nothing,
/// instantly, offline; the model then reads only those. So the request that goes
/// out is a fixed size no matter how many notes the person has, and the thing
/// deciding whether two notes are "the same" is a model reading them rather than
/// a cosine threshold — because a threshold cannot tell the difference between
/// the same subject and the same note, and that distinction is the entire
/// feature.
public enum CaptureProposer {
    /// Below this, a capture has nothing to propose about.
    ///
    /// A three-second note has no second topic to split off, and it is exactly
    /// the case where merges misfire: "milk, eggs, bread" resembles every
    /// shopping note ever written, and the model has too few words to tell
    /// whether it is the same list or a new one.
    static let minimumCharacters = 150

    /// Nil whenever there is nothing worth showing — no key, too short, nothing
    /// alike, an unreadable answer, or a plain `keep`. Every one of those is a
    /// screen that simply never shows a card, which is the correct behaviour for
    /// background work nobody asked for.
    public static func propose(
        for item: CaptureItem,
        store: CaptureStore,
        client: GroqClient = .configured
    ) async -> CaptureProposal? {
        guard client.hasKey else { return nil }

        let note = CaptureIndex.embeddableText(of: item)
        guard note.count >= minimumCharacters else { return nil }

        let candidates = await store.candidates(for: item)
        guard !Task.isCancelled else { return nil }

        // Numbered here, once, and mapped back here — the only place that knows
        // both the digits the model was shown and the notes they stand for.
        let numbering = Dictionary(
            uniqueKeysWithValues: candidates.enumerated().map { ($0.offset + 1, $0.element.id) }
        )
        let numbered = candidates.enumerated().map { (number: $0.offset + 1, item: $0.element) }

        guard let raw = try? await client.complete(
            system: CaptureProposal.systemPrompt,
            user: CaptureProposal.userPrompt(note: note, candidates: numbered)
        ) else { return nil }
        guard !Task.isCancelled else { return nil }

        guard let proposal = CaptureProposal.complete(raw, numbering: numbering),
              proposal.isActionable
        else { return nil }

        // A merge target deleted while the request was out. Rare, and cheap to
        // check, and the alternative is a card offering to add the note to
        // something that no longer exists.
        if case let .merge(id, _) = proposal {
            guard await store.contains(id) else { return nil }
        }
        return proposal
    }
}
