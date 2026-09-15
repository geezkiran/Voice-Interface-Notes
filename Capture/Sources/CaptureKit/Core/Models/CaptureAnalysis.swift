import Foundation

/// What the model made of one capture: a title, a rewritten report, the gaps it
/// noticed, and the structure the rest of the app files by.
///
/// This is the frontier between a language model's output and the app's data
/// model. `CaptureItem` never learns that an LLM exists; it is handed a
/// finished value through `applied(to:)`, so the day the prompt changes, or the
/// provider changes, or the whole thing falls back to `TriageEngine`, nothing
/// downstream of this file notices.
public struct CaptureAnalysis: Sendable {
    /// Row-line title — the AI's read of the capture, never typed by hand.
    public var title: String
    /// The transcript rewritten as prose: every fact kept, every "um" dropped.
    /// This becomes the body's first passage.
    public var report: String
    /// Two to four things the report genuinely could not resolve.
    public var questions: [String]
    public var actionItems: [String]
    /// Whether this note is the kind of thing a person would want reminding
    /// about — a commitment, an errand, a deadline — as opposed to a thought
    /// being worked out or a record of something that happened.
    ///
    /// Nothing in the data model changes when this is true. It is a question the
    /// page asks, once, in a banner the user can ignore; only a tap on that
    /// banner writes a date. See `EditingView.offerReminder`.
    public var needsReminder: Bool
    /// The time the note itself indicated, if it indicated one — "Friday at
    /// five", resolved against the device's clock.
    ///
    /// Deliberately *not* applied to the capture. A date the model heard is the
    /// app's best guess at what the reminder should be set to, and it is offered
    /// as the banner's first option; a note that quietly acquires an alarm the
    /// user never asked for is the app scheduling their life for them.
    public var suggestedDueAt: Date?
    /// Which shelf the model put the note on, or nil when it didn't answer
    /// with one it recognised. Nil leaves the capture on whatever shelf it is
    /// already on — the on-device guess is a worse answer than the model's, but
    /// it is a far better one than moving a note somewhere at random.
    public var type: ItemType?
    /// How sure the model is about the structure it produced — the number that
    /// decides whether Home flags this capture for review.
    public var confidence: Double

    public init(
        title: String,
        report: String,
        questions: [String] = [],
        actionItems: [String] = [],
        needsReminder: Bool = false,
        suggestedDueAt: Date? = nil,
        type: ItemType? = nil,
        confidence: Double = 0.8
    ) {
        self.title = title
        self.report = report
        self.questions = questions
        self.actionItems = actionItems
        self.needsReminder = needsReminder
        self.suggestedDueAt = suggestedDueAt
        self.type = type
        self.confidence = confidence
    }

    /// Folds this analysis into a capture and hands back the result.
    ///
    /// Two invariants are load-bearing here, and both are about not destroying
    /// something the user owns:
    ///
    /// 1. **`transcript` is never touched.** It is the immutable record of what
    ///    was actually said. The report is an interpretation of it; if the
    ///    interpretation is wrong, the original still has to be there to check
    ///    against. Overwriting it would make the AI unfalsifiable.
    ///
    /// 2. **The body becomes one passage.** The analysis is run against the
    ///    whole note — every section, not just the first sitting — so the
    ///    report it hands back already contains what those sections said.
    ///    Leaving them underneath it would print the note twice. The surviving
    ///    passage keeps passage 0's id and date, so the body is still the same
    ///    object with new words in it rather than a replacement that lost its
    ///    place in the list. Nothing is destroyed by this that isn't still in
    ///    `transcriptSegments`, which is what "See Original" reads.
    public func applied(to item: CaptureItem) -> CaptureItem {
        var result = item

        // Stamped here rather than at the call site because this is the moment
        // the summary becomes real, and it has to be written in the same commit
        // as the body it describes. Recording it separately would leave a gap
        // where a capture has a summary but no record of having one, and the
        // whole point of the stamp is that a re-opened note is read, never
        // regenerated.
        result.summarizedAt = .now

        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let body = report.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.passages.isEmpty {
            result.passages = [CapturePassage(text: body, createdAt: result.createdAt)]
        } else {
            // Rewrite in place so the passage keeps its id and its date: the
            // section header still reads out the day the capture happened, not
            // the day the analysis finished. Everything after it is dropped —
            // the report was written against all of it and now says it.
            result.passages[0].text = body
            result.passages.removeSubrange(1...)
        }

        // Written from the body as it now stands, in the same commit as the
        // body itself, so the note can always answer whether it has changed
        // since. Read off `result` rather than off `body` because they can
        // differ — the summary is the whole passage list joined, and that is
        // what `isSummaryStale` will be comparing against.
        result.summarizedBody = result.summary

        result.confidence = min(max(confidence, 0), 1)
        // `suggestedDueAt` is deliberately not written here. A date is something
        // the person sets, on the banner, in one tap — the model's read of the
        // note only decides whether that banner is worth putting on screen.

        // Stamped alongside the shelf itself, so the page can tell a category a
        // model chose from the keyword guess every capture starts life with —
        // that stamp is what puts the tag under the heading.
        if let type {
            result.type = type
            result.typedAt = .now
        }

        result.actionItems = actionItems
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { ActionItem(text: $0) }

        result.followUpQuestions = questions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { FollowUpQuestion(question: $0) }

        return result
    }

    // MARK: Prompts

    /// The instructions the whole feature rests on.
    ///
    /// It is long, repetitive and blunt on purpose. Every emphatic sentence in
    /// here is load-bearing against a specific observed failure: models
    /// summarise when asked to rewrite, reach for bullet points the moment they
    /// see more than one idea, slide into third person ("the user mentioned"),
    /// and invent plausible-sounding follow-up questions when there is nothing
    /// left to ask. Softening any of it brings that behaviour straight back.
    ///
    /// The key order is fixed because the response is parsed *while it streams*:
    /// `title` first so the screen has a heading almost immediately, `report`
    /// second so the long text starts flowing while the rest is still being
    /// generated, and the cheap structural fields last where nobody is waiting
    /// on them.
    public static let systemPrompt = """
    You turn a person's spoken note into a clean, organized page of their own
    notebook. You are reorganizing what was said — not expanding it, summarising
    it, or improving it.

    Return ONE JSON object and nothing else. No preamble, no code fences, no
    trailing commentary. Its keys must appear in exactly this order:
    "title", "report", "questions", "action_items", "needs_reminder", "due_at",
    "confidence".

    The "report" value is a single string containing the full page, including its
    line breaks. Newlines inside it are escaped as \\n. Do not split the report
    across multiple keys.

    EVERY value you return is PLAIN TEXT ONLY. No markdown, ever. No #, ##, or
    any other heading marks. No *, **, _ or __ for bold or italic. No -, *, +,
    or 1. as bullet or list markers. No backticks, no code fences, no tables, no
    links, no blockquotes, no horizontal rules. If a heading or a list is the
    right shape for the content, write it as plain lines of text with no marker
    characters in front of them. The only formatting available to you is
    ordinary sentences, line breaks and blank lines.

    ────────────────────────────────

    TITLE
    Concrete and specific, at most nine words, sentence case, no trailing
    punctuation, no date stamps, no "Notes about". The standard is a good chat
    title: glanceable in a list, specific enough to know what it was without
    opening it.

    ────────────────────────────────

    REPORT — the most important field.

    FIDELITY
    Every fact, number, name, date, place, price, measurement, condition and
    qualifier in the transcript survives into the report. Drop only speech
    disfluencies, filler, repetitions, false starts and self-corrections — when
    something is corrected mid-sentence, keep the corrected version only. If you
    are unsure whether a detail matters, keep it.

    NO INVENTION
    Never add facts, reasons, conclusions, examples, implications or connective
    claims that were not stated. Do not smooth a fragment into an assertion it
    did not make. If a fragment is too thin to become a full sentence without
    inventing, leave it short — a stub is better than a fabricated sentence.
    Never write a closing summary, a framing sentence about the note itself, or
    a transition that exists only to join two paragraphs.

    LENGTH
    Output length tracks input length. A twenty-line note produces about twenty
    lines. Reorganising costs no extra words. Padding is a failure, not a
    courtesy.

    SHAPE
    Mirror the shape of the thinking rather than imposing a template.
    Complete fragments into grammatical sentences. Expand shorthand and
    abbreviations only where the meaning is unambiguous from the transcript
    itself.
    Group related fragments together even if they were said far apart; otherwise
    keep the original order.
    Use prose paragraphs for reasoning, argument and narrative. Use a list only
    where the content is genuinely list-shaped: enumerated options, specs,
    steps, names, criteria, prices — and write each entry as its own plain line
    with no bullet, dash or number in front of it. Never turn an argument into a
    list. Never bury a list inside a paragraph.
    Use a short heading only when the note contains two or more distinct topics
    AND each has at least two sentences under it. Below that, no headings at all.
    A heading is a plain short line of text on its own, with a blank line after
    it and no # or other marker in front of it.
    One idea per paragraph, two to five sentences, blank line between paragraphs.
    Lead with what the note is actually about, then the detail around it.
    There is no bold and no italic available — never emphasise a term with
    asterisks or underscores.

    AMBIGUITY — FLAG, DO NOT RESOLVE
    Mark unclear things inline in the body as [unclear]. Three cases:
    garbled or implausible transcription (keep the raw text, mark it); an
    ambiguous referent where you cannot tell what "it" or "they" points to; two
    possible readings (write the more likely one, mark the other). Never pick a
    reading silently and never resolve an ambiguity by inventing context. If more
    than about five flags would appear, keep only the ones that change the
    meaning.

    VOICE
    First person, the speaker's own tense and vocabulary, as if they had written
    the note out properly themselves. Never third person, never "the user said".
    Do not upgrade casual phrasing into formal register — keep their words for
    the things they named.

    ────────────────────────────────

    QUESTIONS — an array of up to 5 strings, and often empty.
    These are for context that is missing entirely, not for things that were said
    unclearly — those get an inline [unclear] flag in the report instead, and
    must not be duplicated as a question. Read the whole note, work out what it
    is really about, and ask only about the gap the rest of the note depends on.
    Every question must name the specific thing it is about, in the speaker's own
    words. No question that would fit any note at all. Nothing the note already
    answers. Nothing that would not change what the person does next. Each
    question is one complete sentence of flowing prose, unnumbered and
    unprefixed, and appears nowhere inside the report. If nothing is genuinely
    unclear, return an empty array.
    ACTION_ITEMS — an array of short plain strings, one per concrete thing to be
    done that was actually stated. Empty array if there are none. Never
    manufacture tasks out of musings.

    ────────────────────────────────

    NEEDS_REMINDER — true or false, and false is the common answer.

    True only when the note contains something the person has to DO, or be
    somewhere for, and would be let down by forgetting: a commitment, an
    appointment, an errand, a deadline, a promise made to someone, a thing to
    buy or book before an occasion, a renewal, a bill.

    False for everything else — thinking out loud, an opinion, a record of
    something that already happened, reference material, a design being reasoned
    about, a list of facts, a wish with no commitment behind it. A date
    mentioned in passing is not a reason to say true, and neither is an urgent
    tone. The test is one question: would a notification arriving later actually
    help this person, or merely interrupt them? If you are not sure, answer
    false.

    ────────────────────────────────

    DUE_AT — ISO 8601 with a timezone offset, or null. Only meaningful when
    needs_reminder is true; return null whenever it is false. Resolve relative
    dates like "next Tuesday" against the current date and time supplied in the
    user message. If no time was stated or clearly implied, return null — a
    reminder with no time is a perfectly good answer, and the person will pick
    one. Never guess a date that was not indicated.

    ────────────────────────────────

    CONFIDENCE — a number from 0.0 to 1.0: how sure you are about
    the structure you produced. Score low for rambling, ambiguous or very short
    input. A low score is useful; an inflated one is not.
    """

    /// The note, plus the wall-clock context the model needs to turn "next
    /// Tuesday" into a date.
    ///
    /// Takes "the note" rather than "the transcript" because the source is not
    /// always spoken: a capture typed straight into the body deserves the same
    /// framing pass as a dictated one, and the prompt's instructions read the
    /// same either way — terse is terse whether it was said or thumbed in.
    ///
    /// The timezone comes from the device rather than UTC because relative
    /// dates are relative to where the person is standing, and a note dictated
    /// at 11pm resolves to a different "tomorrow" in Auckland than in London.
    public static func userPrompt(note: String, now: Date = .now) -> String {
        """
        \(timeContext(now: now))

        Note:
        \(note)
        """
    }

    /// The one line of wall-clock context every prompt in this app opens with.
    /// Shared with `CaptureProposal` next door — there is one way this app tells
    /// a model what time it is, and it lives here.
    static func timeContext(now: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withInternetDateTime]
        return """
        Current date and time: \(formatter.string(from: now)) \
        (timezone \(TimeZone.current.identifier))
        """
    }

    // MARK: Decoding the finished document

    /// Decodes a complete response into an analysis, or returns nil so the
    /// caller can fall back to `TriageEngine`.
    ///
    /// Returning nil rather than throwing is the whole contract: a malformed
    /// reply is not an error the user should ever see, it is a reason to quietly
    /// use the local heuristics instead. Nothing about this feature is allowed
    /// to leave a capture unfiled.
    public static func complete(_ raw: String) -> CaptureAnalysis? {
        guard let data = jsonBody(of: raw) else { return nil }

        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(Payload.self, from: data) else { return nil }
        guard !payload.report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return CaptureAnalysis(
            title: payload.title,
            report: payload.report,
            questions: payload.questions,
            actionItems: payload.actionItems,
            needsReminder: payload.needsReminder,
            suggestedDueAt: payload.dueAt,
            type: payload.type,
            confidence: payload.confidence
        )
    }

    /// Pulls the JSON object out of whatever the model actually sent.
    ///
    /// `response_format` should make this unnecessary, but models still
    /// occasionally wrap the object in a ```json fence or add a sentence of
    /// throat-clearing, and it is cheaper to be tolerant here than to lose a
    /// capture's analysis to a stray backtick.
    ///
    /// Shared with `CaptureProposal`, which parses a different document out of
    /// the same endpoint and meets the same stray backticks.
    static func jsonBody(of raw: String) -> Data? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            // Drop the opening fence line (```, ```json, …) and any closing one.
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let fence = text.range(of: "```", options: .backwards) {
                text = String(text[text.startIndex..<fence.lowerBound])
            }
        }
        guard
            let open = text.firstIndex(of: "{"),
            let close = text.lastIndex(of: "}"),
            open < close
        else { return nil }
        return String(text[open...close]).data(using: .utf8)
    }

    /// Reads a flag a model may have answered with `true`, `"true"`, `"yes"` or
    /// `1` — all of which are the same answer — and treats anything else,
    /// including a missing key, as false.
    ///
    /// False is the safe default for every flag this app asks for: the one it
    /// currently asks about is whether to interrupt the user with a banner, and
    /// a garbled reply is not a reason to interrupt them. Shared with
    /// `CaptureRefinement`, which asks the same question of the same endpoint.
    static func boolean<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        _ key: Key
    ) -> Bool {
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: key) { return flag }
        if let number = try? container.decodeIfPresent(Int.self, forKey: key) { return number == 1 }
        guard let text = try? container.decodeIfPresent(String.self, forKey: key) else {
            return false
        }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["true", "yes", "1"].contains(word)
    }

    /// The wire shape, kept private so the model's snake_case and its tolerance
    /// for nonsense never leak into the app's own value type.
    private struct Payload: Decodable {
        var title: String
        var report: String
        var questions: [String]
        var actionItems: [String]
        var needsReminder: Bool
        var dueAt: Date?
        var type: ItemType?
        var confidence: Double

        enum CodingKeys: String, CodingKey {
            case title, report, questions, type, confidence
            case actionItems = "action_items"
            case needsReminder = "needs_reminder"
            case dueAt = "due_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = (try? container.decode(String.self, forKey: .title)) ?? ""
            report = (try? container.decode(String.self, forKey: .report)) ?? ""
            questions = (try? container.decode([String].self, forKey: .questions)) ?? []
            actionItems = (try? container.decode([String].self, forKey: .actionItems)) ?? []
            needsReminder = CaptureAnalysis.boolean(container, .needsReminder)

            let rawDate = try? container.decodeIfPresent(String.self, forKey: .dueAt)
            dueAt = rawDate.flatMap(CaptureAnalysis.date(from:))

            let rawType = try? container.decodeIfPresent(String.self, forKey: .type)
            type = rawType.flatMap(ItemType.named)

            // Some models answer with "0.8" rather than 0.8. Both are fine.
            if let number = try? container.decode(Double.self, forKey: .confidence) {
                confidence = number
            } else if let text = try? container.decode(String.self, forKey: .confidence),
                      let number = Double(text) {
                confidence = number
            } else {
                confidence = 0.7
            }
            confidence = min(max(confidence, 0), 1)
        }
    }
}

extension CaptureAnalysis {
    /// Lenient on purpose. Models emit fractional seconds sometimes, drop
    /// the timezone sometimes, and occasionally answer a bare "2026-04-11"
    /// when only a day was mentioned. All three are useful answers.
    ///
    /// Shared with `CaptureRefinement`, which reads the same key off the same
    /// endpoint and meets the same three spellings.
    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "null" else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone.current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            fallback.dateFormat = format
            if let date = fallback.date(from: trimmed) { return date }
        }
        return nil
    }
}

/// Reads a JSON object that is still being written.
///
/// The report is the longest thing the model produces and the only thing the
/// user is waiting to read, so it has to reach the screen character by
/// character — long before the document is valid JSON and could be handed to
/// `JSONDecoder`.
///
/// So this is a hand-written character scanner rather than the obvious
/// "try to decode the buffer after every chunk" trick. That trick is both
/// fragile (a partial document is not repairable in general) and quadratic
/// (every chunk re-parses everything received so far, which on a long report
/// means re-parsing thousands of characters hundreds of times). This scanner
/// keeps its position and its state between calls, so each character in the
/// stream is examined exactly once, for the whole life of the response.
///
/// It understands just enough JSON to do its job: object and array depth, when
/// it is inside a string, whether the previous character was an escape, and
/// which top-level key the current value belongs to. It ignores everything it
/// is not looking for, which is why nested objects and the questions array pass
/// through it harmlessly.
public struct StreamingAnalysisParser: Sendable {
    /// Everything received so far — handed to `CaptureAnalysis.complete` once
    /// the stream ends.
    public private(set) var raw: String = ""

    /// Available the moment the title's closing quote arrives, which is within
    /// the first few chunks because the prompt fixes the key order.
    public private(set) var title: String?

    /// The report as far as it has been written, already unescaped.
    public private(set) var report: String = ""

    /// True once the report's closing quote has been seen. Until then the last
    /// word on screen may still be half a word.
    public private(set) var isReportComplete: Bool = false

    // MARK: Scanner state, carried across calls

    /// The characters not yet examined. Consumed from the front, so the scanner
    /// never revisits ground it has already covered.
    private var pending: [Character] = []
    private var depth = 0
    private var inString = false
    private var isEscaped = false
    /// True when the next string encountered at depth 1 is a key rather than a
    /// value — set after `{` and after each `,` inside the root object.
    private var expectsKey = true
    /// The key whose value is currently being read, if it is one we care about.
    private var currentKey: String = ""
    /// Whether the string currently open is a key (as opposed to a value).
    private var readingKey = false
    /// Accumulator for a key name, or for the title's value.
    private var scratch: String = ""
    /// Remaining hex digits of a `\uXXXX` escape still to arrive. Held across
    /// calls so an escape split across two chunks still resolves.
    private var unicodeDigits: String?

    public init() {}

    /// Feeds the next chunk of raw model output in.
    ///
    /// Takes the *delta*, not the accumulated text: the parser does its own
    /// accumulating, and handing it the whole buffer each time would defeat the
    /// point of keeping a cursor.
    public mutating func ingest(_ delta: String) {
        guard !delta.isEmpty else { return }
        raw += delta
        pending.append(contentsOf: delta)
        scan()
    }

    private mutating func scan() {
        var index = 0
        while index < pending.count {
            let character = pending[index]
            index += 1

            if inString {
                consumeInString(character)
            } else {
                switch character {
                case "{", "[":
                    depth += 1
                    expectsKey = (character == "{")
                case "}", "]":
                    depth -= 1
                    expectsKey = false
                case "\"":
                    inString = true
                    readingKey = (depth == 1 && expectsKey)
                    scratch = ""
                case ":":
                    expectsKey = false
                case ",":
                    // A comma at depth 1 separates the root object's members,
                    // so the next string is a key again. Inside the questions
                    // array (depth 2) it separates values, and is ignored.
                    expectsKey = (depth == 1)
                    currentKey = ""
                default:
                    break
                }
            }
        }
        pending.removeAll(keepingCapacity: true)
    }

    private mutating func consumeInString(_ character: Character) {
        // A `\uXXXX` escape in progress takes priority over everything.
        if var digits = unicodeDigits {
            digits.append(character)
            if digits.count == 4 {
                unicodeDigits = nil
                if let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) {
                    emit(Character(scalar))
                }
            } else {
                unicodeDigits = digits
            }
            return
        }

        if isEscaped {
            isEscaped = false
            switch character {
            case "n": emit("\n")
            case "t": emit("\t")
            case "r": emit("\r")
            case "b": emit("\u{08}")
            case "f": emit("\u{0C}")
            case "u": unicodeDigits = ""
            // `\"`, `\\` and `\/` all stand for themselves.
            default: emit(character)
            }
            return
        }

        switch character {
        case "\\":
            // Nothing is emitted yet. This is what keeps a backslash that
            // arrived at the very end of a chunk from surfacing on screen as a
            // stray character before its partner turns up in the next chunk.
            isEscaped = true
        case "\"":
            closeString()
        default:
            emit(character)
        }
    }

    private mutating func emit(_ character: Character) {
        if readingKey {
            scratch.append(character)
        } else if currentKey == "report" {
            // The only value written straight through to the published
            // property: it is what the screen is rendering, live.
            report.append(character)
        } else if currentKey == "title" {
            scratch.append(character)
        }
        // Every other value (dates, questions) is cheap and is read
        // properly from the finished document, so it is dropped here.
    }

    private mutating func closeString() {
        inString = false
        if readingKey {
            currentKey = scratch
            readingKey = false
        } else {
            switch currentKey {
            case "title":
                title = scratch.trimmingCharacters(in: .whitespacesAndNewlines)
            case "report":
                isReportComplete = true
            default:
                break
            }
        }
        scratch = ""
    }
}

/// Runs one capture through the model, start to finish.
///
/// A free-standing enum rather than a method on `GroqClient` because this is
/// where the app's knowledge lives — which prompt, which parser, what to do
/// when the answer is malformed — and the client below it stays a transport.
public enum CaptureAnalyzer {
    /// Streams an analysis of `transcript`, reporting progress as it arrives.
    ///
    /// `onPartial` is called on the main actor with the title (nil until it has
    /// closed) and the report so far, so a SwiftUI screen can bind straight to
    /// it without a hop of its own.
    ///
    /// If the finished document fails to decode but a report was streamed, the
    /// partial is used rather than throwing: the user has been watching that
    /// text appear for several seconds, and throwing it away over a trailing
    /// brace would be indefensible.
    public static func analyze(
        note: String,
        client: GroqClient = .configured,
        onPartial: @MainActor (String?, String) -> Void
    ) async throws -> CaptureAnalysis {
        guard client.hasKey else { throw GroqError.missingKey }

        var parser = StreamingAnalysisParser()
        let stream = client.stream(
            system: CaptureAnalysis.systemPrompt,
            user: CaptureAnalysis.userPrompt(note: note)
        )

        for try await delta in stream {
            parser.ingest(delta)
            await onPartial(parser.title, parser.report)
        }

        if let analysis = CaptureAnalysis.complete(parser.raw) {
            await onPartial(analysis.title, analysis.report)
            return analysis
        }

        let salvaged = parser.report.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !salvaged.isEmpty else {
            throw GroqError.decoding("the reply wasn't a usable JSON object")
        }
        return CaptureAnalysis(
            title: parser.title ?? "",
            report: salvaged,
            // The structural fields never arrived, so say so honestly: a low
            // score is what puts the capture in front of the user for review.
            confidence: 0.5
        )
    }
}

// MARK: - Keeping a capture's read of itself current

/// The model's second, much cheaper job: re-reading a capture that has changed
/// and updating what the app says *about* it.
///
/// This is deliberately not a `CaptureAnalysis` with some fields left blank.
/// The two passes differ in the one way that matters — an analysis rewrites the
/// body, and a refinement is forbidden from touching it. A capture the person
/// has been editing for a week is theirs; the heading and the questions are
/// the app's read of it, and only those are up for revision.
/// Making that a type distinction rather than a flag means the destructive
/// version cannot be reached by accident from the edit path.
public struct CaptureRefinement: Sendable {
    public var title: String
    public var questions: [String]
    public var actionItems: [String]
    /// See `CaptureAnalysis.needsReminder`. This is the field the banner is
    /// actually driven by in practice: a re-read runs whenever the body changes,
    /// so the question "is this something to be reminded about?" is re-asked as
    /// the note is written rather than once at the moment it was made.
    public var needsReminder: Bool
    /// See `CaptureAnalysis.suggestedDueAt`. Never applied by `applied(to:)`.
    public var suggestedDueAt: Date?
    /// See `CaptureAnalysis.type`. A re-read is allowed to change its mind
    /// about the shelf — a note that grew a date is an event now — and nil
    /// still means "leave it where it is".
    public var type: ItemType?
    public var confidence: Double

    public init(
        title: String,
        questions: [String] = [],
        actionItems: [String] = [],
        needsReminder: Bool = false,
        suggestedDueAt: Date? = nil,
        type: ItemType? = nil,
        confidence: Double = 0.8
    ) {
        self.title = title
        self.questions = questions
        self.actionItems = actionItems
        self.needsReminder = needsReminder
        self.suggestedDueAt = suggestedDueAt
        self.type = type
        self.confidence = confidence
    }

    /// Folds the refreshed read into a capture. Passages and transcript are not
    /// mentioned once in here, which is the entire point of the type.
    ///
    /// An empty title is dropped rather than applied: a capture that has lost
    /// its heading looks broken in the list, and the previous heading is always
    /// a better answer than nothing.
    ///
    /// `retitling` is what separates the first read of a capture from every
    /// later one. A note that already carries a heading keeps it: adding a
    /// paragraph to a note is not asking for it to be renamed, and a heading
    /// that changes under the person every time they speak into the note is
    /// the note refusing to stay the thing they filed. The rest of the read —
    /// the shelf, the questions, the action items — is refreshed either way,
    /// and an empty heading is still filled in, since a capture with no
    /// heading at all has nothing to protect.
    public func applied(to item: CaptureItem, retitling: Bool = true) -> CaptureItem {
        var result = item

        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasHeading = !result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !heading.isEmpty, retitling || !hasHeading { result.title = heading }

        if let type {
            result.type = type
            result.typedAt = .now
        }

        result.confidence = min(max(confidence, 0), 1)

        result.actionItems = actionItems
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { ActionItem(text: $0) }

        result.followUpQuestions = questions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { FollowUpQuestion(question: $0) }

        return result
    }

    /// Sharper and shorter than the analysis prompt, because the failure modes
    /// are different. Asked to re-read a note it has seen before, a model's
    /// instinct is to justify its presence: it rewrites a perfectly good title
    /// into a synonym of itself, and it re-asks the questions it asked last
    /// time even though the new paragraph just answered them. Both are told off
    /// here explicitly.
    public static let refinementSystemPrompt = """
    You turn a person's spoken note into a clean, organized page of their own
    notebook. You are reorganizing what was said — not expanding it, summarising
    it, or improving it.

    Return ONE JSON object and nothing else. No preamble, no code fences, no
    trailing commentary. Its keys must appear in exactly this order:
    "title", "report", "questions", "type", "action_items", "needs_reminder",
    "due_at", "confidence".

    The "report" value is a single string containing the full page, including its
    line breaks. Newlines inside it are escaped as \n. Do not split the report
    across multiple keys.

    EVERY value you return is PLAIN TEXT ONLY. No markdown, ever. No #, ##, or
    any other heading marks. No *, **, _ or __ for bold or italic. No -, *, +,
    or 1. as bullet or list markers. No backticks, no code fences, no tables, no
    links, no blockquotes, no horizontal rules. If a heading or a list is the
    right shape for the content, write it as plain lines of text with no marker
    characters in front of them. The only formatting available to you is
    ordinary sentences, line breaks and blank lines.

    ────────────────────────────────

    TITLE
    Concrete and specific, at most nine words, sentence case, no trailing
    punctuation, no date stamps, no "Notes about". The standard is a good chat
    title: glanceable in a list, specific enough to know what it was without
    opening it.

    ────────────────────────────────

    REPORT — the most important field.

    FIDELITY
    Every fact, number, name, date, place, price, measurement, condition and
    qualifier in the transcript survives into the report. Drop only speech
    disfluencies, filler, repetitions, false starts and self-corrections — when
    something is corrected mid-sentence, keep the corrected version only. If you
    are unsure whether a detail matters, keep it.

    NO INVENTION
    Never add facts, reasons, conclusions, examples, implications or connective
    claims that were not stated. Do not smooth a fragment into an assertion it
    did not make. If a fragment is too thin to become a full sentence without
    inventing, leave it short — a stub is better than a fabricated sentence.
    Never write a closing summary, a framing sentence about the note itself, or
    a transition that exists only to join two paragraphs.

    LENGTH
    Output length tracks input length. A twenty-line note produces about twenty
    lines. Reorganising costs no extra words. Padding is a failure, not a
    courtesy.

    SHAPE
    Mirror the shape of the thinking rather than imposing a template.
    Complete fragments into grammatical sentences. Expand shorthand and
    abbreviations only where the meaning is unambiguous from the transcript
    itself.
    Group related fragments together even if they were said far apart; otherwise
    keep the original order.
    Use prose paragraphs for reasoning, argument and narrative. Use a list only
    where the content is genuinely list-shaped: enumerated options, specs,
    steps, names, criteria, prices — and write each entry as its own plain line
    with no bullet, dash or number in front of it. Never turn an argument into a
    list. Never bury a list inside a paragraph.
    Use a short heading only when the note contains two or more distinct topics
    AND each has at least two sentences under it. Below that, no headings at all.
    A heading is a plain short line of text on its own, with a blank line after
    it and no # or other marker in front of it.
    One idea per paragraph, two to five sentences, blank line between paragraphs.
    Lead with what the note is actually about, then the detail around it.
    There is no bold and no italic available — never emphasise a term with
    asterisks or underscores.

    AMBIGUITY — FLAG, DO NOT RESOLVE
    Mark unclear things inline in the body as [unclear]. Three cases:
    garbled or implausible transcription (keep the raw text, mark it); an
    ambiguous referent where you cannot tell what "it" or "they" points to; two
    possible readings (write the more likely one, mark the other). Never pick a
    reading silently and never resolve an ambiguity by inventing context. If more
    than about five flags would appear, keep only the ones that change the
    meaning.

    VOICE
    First person, the speaker's own tense and vocabulary, as if they had written
    the note out properly themselves. Never third person, never "the user said".
    Do not upgrade casual phrasing into formal register — keep their words for
    the things they named.

    ────────────────────────────────

    QUESTIONS — an array of up to 5 strings, and often empty.
    These are for context that is missing entirely, not for things that were said
    unclearly — those get an inline [unclear] flag in the report instead, and
    must not be duplicated as a question. Read the whole note, work out what it
    is really about, and ask only about the gap the rest of the note depends on.
    Every question must name the specific thing it is about, in the speaker's own
    words. No question that would fit any note at all. Nothing the note already
    answers. Nothing that would not change what the person does next. Each
    question is one complete sentence of flowing prose, unnumbered and
    unprefixed, and appears nowhere inside the report. If nothing is genuinely
    unclear, return an empty array.

    ────────────────────────────────

    TYPE — exactly one of: "idea", "task", "event", "shopping", "someday".
    Decide from what the note as a whole IS, not from a keyword in it.
    task — something to be done, with a doer and an outcome.
    event — something happening at a time, attended rather than completed.
    shopping — things to acquire or buy.
    idea — a thought being worked out: a possibility, a design, an argument, a
    plan being reasoned about rather than executed.
    someday — a wish or intention with no commitment and no timeframe.
    When a note both reasons about something and states things to do about it,
    the reasoning is the note and "idea" is the type; the things to do go in
    action_items. When two types genuinely fit, pick the one that explains why
    the person would open this note again, anlower confidence.

    ────────────────────────────────

    ACTION_ITEMS — an array of short plain strings, one per concrete thing to be
    done that was actually stated. Empty array if there are none. Never
    manufacture tasks out of musings.

    ────────────────────────────────

    NEEDS_REMINDER — true or false, and false is the common answer.

    True only when the note contains something the person has to DO, or be
    somewhere for, and would be let down by forgetting: a commitment, an
    appointment, an errand, a deadline, a promise made to someone, a thing to
    buy or book before an occasion, a renewal, a bill.

    False for everything else — thinking out loud, an opinion, a record of
    something that already happened, reference material, a design being reasoned
    about, a list of facts, a wish with no commitment behind it. A date
    mentioned in passing is not a reason to say true, and neither is an urgent
    tone. The test is one question: would a notification arriving later actually
    help this person, or merely interrupt them? If you are not sure, answer
    false.

    ────────────────────────────────

    DUE_AT — ISO 8601 with a timezone offset, or null. Only meaningful when
    needs_reminder is true; return null whenever it is false. Resolve relative
    dates like "next Tuesday" against the current date and time supplied in the
    user message. If no time was stated or clearly implied, return null — a
    reminder with no time is a perfectly good answer, and the person will pick
    one. Never guess a date that was not indicated.

    ────────────────────────────────

    CONFIDENCE — a number from 0.0 to 1.0: how sure you are about the type and
    the structure you produced. Score low for rambling, ambiguous or very short
    input. A low score is useful; an inflated one is not.
    """

    /// The whole note, laid out the way it reads on screen.
    ///
    /// The dates are included because they carry meaning the text does not: a
    /// paragraph added three weeks after the others is a return to the subject,
    /// and that is often what tells the model the note has moved on. The
    /// transcript goes last and is labelled as raw, so it informs the read
    /// without competing with the body the person has since edited.
    public static func refinementUserPrompt(for item: CaptureItem, now: Date = .now) -> String {
        let sections = item.passages
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { passage in
                let stamp = passage.createdAt.formatted(date: .abbreviated, time: .shortened)
                return "[Section written \(stamp)]\n\(passage.text)"
            }
            .joined(separator: "\n\n")

        var prompt = """
        \(CaptureAnalysis.timeContext(now: now))

        Current title: \(item.title.isEmpty ? "(none yet)" : item.title)

        The note as it now stands:
        \(sections.isEmpty ? "(empty)" : sections)
        """

        let spoken = item.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spoken.isEmpty {
            prompt += """


            For reference only, the raw unedited words this note was originally \
            spoken from:
            \(spoken)
            """
        }
        return prompt
    }

    /// Same tolerance as `CaptureAnalysis.complete`, and for the same reason:
    /// a malformed reply here means the capture keeps the title it already has,
    /// which is a perfectly good outcome and not worth an error.
    public static func complete(_ raw: String) -> CaptureRefinement? {
        guard let data = CaptureAnalysis.jsonBody(of: raw) else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        guard !payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !payload.questions.isEmpty
        else { return nil }

        return CaptureRefinement(
            title: payload.title,
            questions: payload.questions,
            actionItems: payload.actionItems,
            needsReminder: payload.needsReminder,
            suggestedDueAt: payload.dueAt,
            type: payload.type,
            confidence: payload.confidence
        )
    }

    private struct Payload: Decodable {
        var title: String
        var questions: [String]
        var actionItems: [String]
        var needsReminder: Bool
        var dueAt: Date?
        var type: ItemType?
        var confidence: Double

        enum CodingKeys: String, CodingKey {
            case title, questions, type, confidence
            case actionItems = "action_items"
            case needsReminder = "needs_reminder"
            case dueAt = "due_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = (try? container.decode(String.self, forKey: .title)) ?? ""
            questions = (try? container.decode([String].self, forKey: .questions)) ?? []
            actionItems = (try? container.decode([String].self, forKey: .actionItems)) ?? []
            needsReminder = CaptureAnalysis.boolean(container, .needsReminder)

            let rawDate = try? container.decodeIfPresent(String.self, forKey: .dueAt)
            dueAt = rawDate.flatMap(CaptureAnalysis.date(from:))

            let rawType = try? container.decodeIfPresent(String.self, forKey: .type)
            type = rawType.flatMap(ItemType.named)

            if let number = try? container.decode(Double.self, forKey: .confidence) {
                confidence = number
            } else if let text = try? container.decode(String.self, forKey: .confidence),
                      let number = Double(text) {
                confidence = number
            } else {
                confidence = 0.7
            }
            confidence = min(max(confidence, 0), 1)
        }
    }
}

/// Re-reads a capture that has changed and hands back the app's updated read of
/// it. The counterpart to `CaptureAnalyzer`, and the cheaper of the two by far:
/// no streaming, no body, a few dozen tokens out.
public enum CaptureRefiner {
    /// Nil rather than a throw when the model can't be reached or its answer
    /// can't be read. Every caller is a keystroke's worth of background work
    /// nobody asked for, and the correct outcome of a failed one is that the
    /// capture keeps the title and questions it already had.
    public static func refine(
        _ item: CaptureItem,
        client: GroqClient = .configured
    ) async -> CaptureRefinement? {
        guard client.hasKey else { return nil }
        guard !item.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        guard let raw = try? await client.complete(
            system: CaptureRefinement.refinementSystemPrompt,
            user: CaptureRefinement.refinementUserPrompt(for: item)
        ) else { return nil }

        return CaptureRefinement.complete(raw)
    }
}
