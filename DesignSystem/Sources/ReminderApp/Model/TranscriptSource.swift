import Foundation
import Observation

/// What the Transcribing screen needs from speech recognition, and nothing
/// more. `SFSpeechRecognizer` will conform to this later; until then
/// `SimulatedTranscriptSource` drives the screen so its layout, timing and
/// animations can be judged against realistic speech rather than lorem text.
@MainActor
public protocol TranscriptSource: AnyObject {
    /// Utterances the recognizer has committed to — one chat bubble each.
    var finalizedUtterances: [String] { get }
    /// The sentence currently being spoken, still mutating word by word.
    var partialUtterance: String { get }
    /// 0…1, sampled fast enough to drive a waveform.
    var level: Double { get }
    var elapsed: TimeInterval { get }
    /// Held mid-session: nothing is being heard, but everything said so far is
    /// still here and resuming carries on the same sentence.
    var isPaused: Bool { get }

    func start()
    func stop()
    /// Stops listening without ending the session. Unlike `stop()` the
    /// half-spoken sentence is left as it is, so `resume()` continues it rather
    /// than starting a new one.
    func pause()
    func resume()
    /// Everything said this session, joined — what the capture stores.
    func fullTranscript() -> String
}

/// A scripted stand-in for live dictation: emits a fixed monologue word by
/// word at a speaking cadence, breaking into a new bubble at each sentence
/// end, with a jittering level so the waveform behaves like a real one.
@MainActor
@Observable
public final class SimulatedTranscriptSource: TranscriptSource {
    public private(set) var finalizedUtterances: [String] = []
    public private(set) var partialUtterance: String = ""
    public private(set) var level: Double = 0
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var isPaused = false

    private var task: Task<Void, Never>?

    /// Split into sentences up front; each becomes one bubble once spoken.
    private let script: [String]

    /// Where the monologue got to. Kept outside `run()` so a paused session
    /// picks up at the next word rather than restarting the script.
    private var sentenceIndex = 0
    private var wordIndex = 0
    /// Time already spoken before the current stretch — the clock counts the
    /// session, not the pauses in it.
    private var elapsedBeforeResume: TimeInterval = 0

    public init(script: [String] = SimulatedTranscriptSource.defaultScript) {
        self.script = script
    }

    public func start() {
        guard task == nil else { return }
        isPaused = false
        task = Task { [weak self] in
            await self?.run()
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isPaused = false
        // Whatever was mid-sentence still counts — a capture never drops words.
        if !partialUtterance.isEmpty {
            finalizedUtterances.append(partialUtterance)
            partialUtterance = ""
        }
        level = 0
    }

    public func pause() {
        guard task != nil else { return }
        task?.cancel()
        task = nil
        // The partial sentence is left standing: pausing mid-thought and
        // carrying on should read as one sentence, not two.
        elapsedBeforeResume = elapsed
        level = 0
        isPaused = true
    }

    public func resume() {
        guard isPaused else { return }
        start()
    }

    public func fullTranscript() -> String {
        (finalizedUtterances + (partialUtterance.isEmpty ? [] : [partialUtterance]))
            .joined(separator: " ")
    }

    private func run() async {
        let started = Date.now
        while sentenceIndex < script.count {
            let words = script[sentenceIndex].split(separator: " ")
            while wordIndex < words.count {
                if Task.isCancelled { return }
                let word = words[wordIndex]
                partialUtterance = partialUtterance.isEmpty
                    ? String(word)
                    : partialUtterance + " " + word
                wordIndex += 1
                elapsed = elapsedBeforeResume + Date.now.timeIntervalSince(started)
                level = Double.random(in: 0.25...1.0)
                try? await Task.sleep(for: .milliseconds(Int.random(in: 110...260)))
            }
            if Task.isCancelled { return }
            finalizedUtterances.append(partialUtterance)
            partialUtterance = ""
            wordIndex = 0
            sentenceIndex += 1
            level = 0.1
            try? await Task.sleep(for: .milliseconds(420))
        }
        // Ran out of script — idle quietly rather than stopping, so the screen
        // stays in its "still listening" state until the user ends it.
        while !Task.isCancelled {
            elapsed = elapsedBeforeResume + Date.now.timeIntervalSince(started)
            level = Double.random(in: 0.02...0.12)
            try? await Task.sleep(for: .milliseconds(140))
        }
    }

    public static let defaultScript = [
        "Okay I need to sort out the trip in March before the flights get stupid.",
        "Check whether the Lisbon dates clash with the offsite, and if they do just move the whole thing a week later.",
        "Also ask Sam if they still want to come, because that changes the apartment size.",
        "And I should book the airport parking early this time, last time it cost twice as much."
    ]

    /// One breath, two subjects that have nothing to do with each other — the
    /// case the split proposal exists for. The pivot is deliberate ("oh, and
    /// completely separately"): a real two-topic capture almost always announces
    /// the turn, and the model should be leaning on that rather than on the
    /// note merely being long.
    public static let twoTopicScript = [
        "Right, the launch date. We said end of September but the beta feedback isn't going to be in until the tenth at the earliest, so realistically that's mid October.",
        "Which means the marketing site has to be ready two weeks before that, so first week of October, and I need to tell Priya that this week because she's scheduling the shoot around it.",
        "Honestly I'd rather ship late than ship on the original date with the onboarding in the state it's in.",
        "Oh, and completely separately, I need to book the dentist.",
        "It's been about eight months and they sent the reminder card ages ago.",
        "Try for a morning slot because my afternoons are wrecked for the next month."
    ]

    /// Another sitting of something already in the store — the seeded car
    /// insurance note (`CaptureStore.sampleItems`). It opens the way people
    /// actually return to a subject: no preamble, straight into the new detail,
    /// with the shared nouns doing the work of saying which note it belongs to.
    public static let continuationScript = [
        "Okay so the car insurance thing again.",
        "I got the second quote back and it's actually about sixty quid cheaper than the renewal, not forty, but that's with a five hundred excess instead of two fifty.",
        "So the saving disappears the first time I actually claim, which makes it not really a saving at all.",
        "I need to ring the current lot and ask what they'd do on price if I tell them I'm leaving, because apparently that's the only way anyone gets a sensible number out of them.",
        "Deadline is the twenty eighth, after that it just auto renews at the price they picked."
    ]

    /// The scripts a fresh capture cycles through in the Simulator, in order.
    ///
    /// A rotation rather than one fixed monologue because the two features that
    /// read a capture — the split proposal and the merge proposal — can only be
    /// judged against input that actually exhibits what they look for, and the
    /// Simulator has no microphone to supply it. Three consecutive captures
    /// exercise all three shapes: an ordinary one-subject note, a two-subject
    /// one, and a return to something already in the store.
    public static let captureScripts: [[String]] = [
        defaultScript,
        twoTopicScript,
        continuationScript
    ]

    /// What coming *back* to a capture sounds like: shorter, mid-thought, and
    /// referring to what is already written above it. Used by Editing's append
    /// dictation, where the point is to watch words land underneath existing
    /// text rather than to fill an empty screen.
    public static let appendScript = [
        "Right, picking this back up.",
        "The part I keep getting wrong is that I'm treating this as one job when it's really two.",
        "So split it: decide the shape first, then do the fiddly bit next week when there's actually time."
    ]
}
