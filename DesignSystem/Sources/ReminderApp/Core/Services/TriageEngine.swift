import Foundation

/// A local stand-in for the backend's AI triage step, so the handoff from
/// Transcribing into Editing arrives *pre-filled* — which is the part of the
/// flow worth judging in a frontend pass, more than the quality of the
/// guesses themselves.
///
/// Every heuristic here is disposable. When the real triage call lands, this
/// type keeps its signature (transcript in, draft item out) and loses its
/// body; nothing in the screens has to move.
enum TriageEngine {
    static func draft(from transcript: String) -> CaptureItem {
        let sentences = split(transcript)
        let type = inferType(transcript)
        let actions = sentences
            .filter { containsActionVerb($0) }
            .prefix(5)
            .map { ActionItem(text: tidy($0)) }

        return CaptureItem(
            title: title(from: sentences),
            summary: sentences.prefix(2).joined(separator: " "),
            transcript: transcript,
            type: type,
            actionItems: Array(actions),
            // Short, verb-less fragments are exactly the case the plan wants
            // flagged rather than silently filed.
            confidence: transcript.count < 40 && actions.isEmpty ? 0.4 : 0.86,
            followUpQuestions: questions(for: type, transcript: transcript),
            createdAt: .now
        )
    }

    /// The heading is never typed by hand — it is always the AI's read of
    /// whatever the body currently says. So when an edited body commits, the
    /// title is regenerated from it; if the body has been emptied there is
    /// nothing to read, and the transcript stands in.
    static func title(forBody body: String, transcript: String) -> String {
        let sentences = split(body)
        return sentences.isEmpty
            ? title(from: split(transcript))
            : title(from: sentences)
    }

    // MARK: Heuristics

    private static func split(_ text: String) -> [String] {
        text.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func title(from sentences: [String]) -> String {
        guard let first = sentences.first else { return "Untitled capture" }
        let words = tidy(first).split(separator: " ")
        return words.count > 9
            ? words.prefix(9).joined(separator: " ") + "…"
            : words.joined(separator: " ")
    }

    /// Sentence-cased, with the throat-clearing openers speech always starts
    /// with removed.
    private static func tidy(_ sentence: String) -> String {
        var text = sentence
        for opener in ["okay ", "ok ", "so ", "uh ", "um ", "and ", "also "] {
            while text.lowercased().hasPrefix(opener) {
                text = String(text.dropFirst(opener.count))
            }
        }
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func containsActionVerb(_ sentence: String) -> Bool {
        let verbs = ["book", "call", "check", "ask", "buy", "send", "email",
                     "remind", "cancel", "renew", "move", "sketch", "write", "get"]
        let lowered = sentence.lowercased()
        return verbs.contains { lowered.contains($0) }
    }

    private static func inferType(_ transcript: String) -> ItemType {
        let lowered = transcript.lowercased()
        if ["dinner", "meeting", "appointment", "flight", "at seven", "o'clock"].contains(where: lowered.contains) {
            return .event
        }
        if ["buy", "groceries", "shopping", "pick up"].contains(where: lowered.contains) {
            return .shopping
        }
        if ["what if", "idea", "thinking", "rethink", "maybe we"].contains(where: lowered.contains) {
            return .idea
        }
        if ["someday", "at some point", "one day"].contains(where: lowered.contains) {
            return .someday
        }
        return .task
    }

    /// The gaps worth asking about — kept to two, because a wall of questions
    /// turns a three-second capture back into a form.
    private static func questions(for type: ItemType, transcript: String) -> [FollowUpQuestion] {
        var questions: [FollowUpQuestion] = []
        let lowered = transcript.lowercased()
        let namesADay = ["monday", "tuesday", "wednesday", "thursday", "friday",
                         "saturday", "sunday", "today", "tomorrow", "next week"]
            .contains(where: lowered.contains)

        if !namesADay {
            questions.append(FollowUpQuestion(question: "When does this need to happen?"))
        }
        if type == .event {
            questions.append(FollowUpQuestion(question: "Should I hold time for this on your calendar?"))
        } else if transcript.count > 200 {
            questions.append(FollowUpQuestion(question: "Which of these is the one that actually matters?"))
        }
        return Array(questions.prefix(2))
    }
}
