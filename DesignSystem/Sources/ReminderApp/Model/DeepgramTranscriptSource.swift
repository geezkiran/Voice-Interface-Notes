#if os(iOS)
import AVFoundation
import Foundation
import Observation

/// The real thing behind `TranscriptSource`: a live WebSocket to Deepgram, fed
/// by a microphone tap.
///
/// This replaced an on-device `SpeechAnalyzer` session. The reason was not
/// accuracy but *time to first word*: the on-device path had to resolve a
/// locale, then check, download and reserve a multi-hundred-megabyte model
/// before the microphone was even opened, which on a real phone meant the
/// capture screen sat on a spinner indefinitely. An app whose whole promise is
/// "under three seconds" cannot open with a download. A socket opens in one
/// round trip and the first partial word lands a few hundred milliseconds
/// later.
///
/// It is deliberately the *same shape* as `SimulatedTranscriptSource` —
/// finalized bubbles, one mutating partial, a level and a clock — because the
/// Transcribing screen was designed against the simulated one and must not
/// learn anything new to drive the live one. Everything specific to the network
/// (auth, framing, resampling, keep-alives, audio session state) is absorbed
/// here rather than leaking upward.
///
/// This runs on Deepgram's turn-based endpoint (Flux, `/v2/listen`) rather than
/// the general streaming one. The difference is where an utterance is allowed to
/// end: the old `/v1/listen` path cut a bubble after 300 ms of silence, so
/// pausing to think mid-sentence split one thought into two, which is exactly
/// what people do when they are talking a note out. Flux decides turn boundaries
/// with a model instead of a timer, and can take an ending back — an
/// `EagerEndOfTurn` followed by `TurnResumed` is it noticing the speaker was not
/// done after all.
///
/// The screen's two-state contract survives the move unchanged: a turn still in
/// progress is the mutating partial, and `EndOfTurn` is what settles it into a
/// bubble. Nothing above this file learned a new state.
///
/// The whole type is fenced to iOS: it needs `AVAudioSession`, which does not
/// exist on macOS, and the macOS build of this package exists only so the model
/// layer can be type-checked from the command line.
@MainActor
@Observable
public final class DeepgramTranscriptSource: TranscriptSource {
    public private(set) var finalizedUtterances: [String] = []
    public private(set) var partialUtterance: String = ""
    public private(set) var level: Double = 0
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var isPaused = false

    /// Set when the session could not be brought up at all — permission
    /// refused, no API key, no network, the audio session already owned by
    /// something else. Exposed rather than trapped because a capture failing to
    /// hear is a UI state, not a programmer error, and the screen can offer the
    /// user something better than a crash. Not part of `TranscriptSource`: the
    /// simulated source can never fail, so the protocol shouldn't pretend.
    public private(set) var failed = false

    /// True from the moment `start()` is called until the microphone is
    /// actually running and the socket is open. Short now — a permission prompt
    /// on first launch and one round trip — but not zero, and without this the
    /// screen sat at a frozen 0:00 with a flat waveform for the whole of it,
    /// which is indistinguishable from a broken app.
    public private(set) var preparing = false

    /// Which step of the bring-up we are on, in the user's words. Shown while
    /// `preparing`, so a slow start reads as work happening rather than as
    /// nothing happening.
    public private(set) var statusMessage: String?

    /// Why the session could not start, when we know something more useful than
    /// "it didn't". `failed` alone sent everyone to Settings to re-check a
    /// permission that was already granted.
    public private(set) var failureMessage: String?

    /// How long any one bring-up step gets before we call it. A socket that
    /// never opens and a socket that is about to open look identical; forever is
    /// not a state this screen can render, so it becomes a failure the user can
    /// act on.
    private static let setupTimeout: TimeInterval = 15

    /// What we send Deepgram, and so what the converter has to produce.
    /// 16 kHz mono linear PCM is Deepgram's cheapest well-supported input and
    /// is far above what speech needs; sending the microphone's native 48 kHz
    /// float would triple the bytes for no accuracy.
    private static let sampleRate = AudioCapture.sampleRate

    private let apiKey: String?

    /// The microphone, deliberately *outside* this main-actor class.
    ///
    /// Bringing up an audio session is not an async operation — `setActive`,
    /// the first touch of `inputNode`, and `engine.start()` are all synchronous
    /// calls into CoreAudio that can block for seconds. Run from a `@MainActor`
    /// method they block the main thread, which freezes the screen mid-label and
    /// — worse — stops the watchdog from ever firing, since it is a main-actor
    /// task too. That is exactly how this screen came to hang forever on
    /// "Starting the microphone…" with no timeout and no error. So every one of
    /// those calls now happens on a detached task, and only the resulting state
    /// comes back here.
    private let capture = AudioCapture()

    private var socket: URLSessionWebSocketTask?
    /// The socket, in a form the realtime audio thread can touch. The tap must
    /// not hop to the main actor per buffer — that is ~10 hops a second of pure
    /// latency on the one path that has to stay quick.
    private var sink: AudioSink?

    private var receiveTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    /// Fails the session if the bring-up never finishes. Cancelled the moment
    /// the microphone is live.
    private var watchdogTask: Task<Void, Never>?

    /// Time already spoken before the current stretch — the clock counts the
    /// session, not the pauses in it.
    private var elapsedBeforeResume: TimeInterval = 0

    /// When the current bring-up step began. Read by the watchdog.
    private var stageStartedAt: Date = .distantFuture

    /// Whether the socket has ever delivered a frame. Distinguishes a refused
    /// connection from a dropped one, which are the same exception but very
    /// different problems.
    private var hasReceived = false

    /// `apiKey` defaults to whatever the build was configured with; it is a
    /// parameter so a test can hand in a known-bad key without touching the
    /// bundle.
    public init(apiKey: String? = DeepgramCredentials.apiKey) {
        self.apiKey = apiKey
    }

    // MARK: TranscriptSource

    public func start() {
        guard socket == nil, !preparing else { return }
        isPaused = false
        failed = false
        failureMessage = nil
        hasReceived = false
        preparing = true
        stage("Getting ready to listen…")

        Task { [weak self] in
            await self?.beginSession()
        }
        // Polled rather than a single sleep, because the deadline is per *step*:
        // waiting on a permission prompt the user has not answered is not a
        // stall, but a socket that has not opened in fifteen seconds is.
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, self.preparing else { return }
                guard Date.now.timeIntervalSince(self.stageStartedAt) > Self.setupTimeout else { continue }
                // The stalled step is named because the fix differs per step — a
                // stall on access is a Settings problem, a stall on the socket
                // is a network problem.
                self.fail("Couldn't start listening — stuck at \"\(self.statusMessage ?? "startup")\". Check your connection and try again.")
                return
            }
        }
    }

    public func stop() {
        tickTask?.cancel()
        tickTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        preparing = false
        statusMessage = nil

        stopCapture()
        closeSocket()

        isPaused = false
        // Whatever was mid-sentence still counts — a capture never drops words.
        if !partialUtterance.isEmpty {
            finalizedUtterances.append(partialUtterance)
            partialUtterance = ""
        }
        level = 0
    }

    /// A deliberate pause is a turn boundary, so the socket goes with the
    /// microphone.
    ///
    /// The v1 path kept the socket open across a pause and fed it `KeepAlive`
    /// frames, so a half-spoken sentence stayed Deepgram's own in-flight
    /// utterance and pausing mid-thought read as one sentence. Flux has no
    /// documented `KeepAlive`, and a socket held open with no audio is a socket
    /// the server may close from under us — which would surface much later as a
    /// bogus "lost the connection" on resume. Closing it here is the honest
    /// version, and costs nothing that matters: the words spoken so far are
    /// already in `partialUtterance`, and a user who stopped talking on purpose
    /// has ended a turn by any definition.
    public func pause() {
        guard !isPaused else { return }
        elapsedBeforeResume = elapsed
        tickTask?.cancel()
        tickTask = nil
        stopCapture()
        // Settled here rather than left hanging, because the socket that would
        // have finished the turn is about to go away.
        if !partialUtterance.isEmpty {
            finalizedUtterances.append(partialUtterance)
            partialUtterance = ""
        }
        receiveTask?.cancel()
        receiveTask = nil
        closeSocket()
        level = 0
        isPaused = true
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        // Restarting the microphone blocks exactly as much as starting it did,
        // so resuming is a task rather than a straight-line call — and it now
        // reopens the socket too, since pausing closed it.
        Task { [weak self] in
            guard let self else { return }
            do {
                try self.openStream()
                try await self.startCapture()
                self.startTicking()
            } catch {
                self.fail(self.message(for: error))
            }
        }
    }

    public func fullTranscript() -> String {
        (finalizedUtterances + (partialUtterance.isEmpty ? [] : [partialUtterance]))
            .joined(separator: " ")
    }

    // MARK: Session

    /// Permission, then socket, then microphone. Every step is inside the same
    /// `do` on purpose: a capture that quietly reports `failed` with a sentence
    /// the user can act on is always better than one that traps.
    private func beginSession() async {
        do {
            guard let apiKey, !apiKey.isEmpty else { throw SessionError.noKey }

            stage("Waiting for microphone access…")
            guard await AVAudioApplication.requestRecordPermission() else {
                throw SessionError.denied
            }
            guard !Task.isCancelled else { return }

            stage("Connecting…")
            try openStream()

            stage("Starting the microphone…")
            try await startCapture()
            // The watchdog may have given up while the microphone was still
            // coming up. If it did, this session is already reported dead, and
            // quietly starting to record behind an error message would be the
            // worst of both.
            guard !failed, !Task.isCancelled else {
                stopCapture()
                closeSocket()
                return
            }
            startTicking()

            // Only here is the session actually hearing anything, so only here
            // does the screen stop saying it is starting.
            watchdogTask?.cancel()
            watchdogTask = nil
            preparing = false
            statusMessage = nil
        } catch {
            stopCapture()
            closeSocket()
            fail(message(for: error))
        }
    }

    /// Opens the socket and starts reading it. Separate from `beginSession`
    /// because `resume()` needs exactly this and none of the permission work.
    private func openStream() throws {
        guard let apiKey, !apiKey.isEmpty else { throw SessionError.noKey }
        let socket = try openSocket(apiKey: apiKey)
        self.socket = socket
        self.sink = AudioSink(socket: socket)
        consumeResults(from: socket)
    }

    /// Deepgram is configured entirely through query parameters, so the whole
    /// transcription contract is this one URL.
    private func openSocket(apiKey: String) throws -> URLSessionWebSocketTask {
        // `/v2/listen` is Flux's endpoint — the turn-based API is a different
        // version, not a flag on the old one.
        var components = URLComponents(string: "wss://api.deepgram.com/v2/listen")!
        components.queryItems = [
            // English-only. `flux-general-multi` exists and takes
            // `language_hint`, but nothing in the app asks the user what they
            // speak, and guessing costs accuracy on the language they do.
            .init(name: "model", value: "flux-general-en"),
            .init(name: "encoding", value: "linear16"),
            .init(name: "sample_rate", value: String(Int(Self.sampleRate))),
            // How sure Flux has to be that a turn ended before it says so
            // (0.5–0.9, default 0.7). Tuned up, because this is not a voice
            // agent waiting for its cue to speak: nothing downstream is racing
            // the user, and the only visible cost of deciding late is a bubble
            // settling a beat later. Deciding *early* is the expensive mistake —
            // it chops a thought in half on screen.
            .init(name: "eot_threshold", value: "0.8"),
            // …and the backstop for when the model never gets confident: silence
            // this long ends the turn regardless (500–60000, default 5000).
            // Eight seconds is past the length of a thinking pause and well
            // short of feeling stuck.
            .init(name: "eot_timeout_ms", value: "8000"),
            // Flux punctuates and capitalises on its own; `punctuate` and
            // `smart_format` are not parameters here. `numerals` is the one
            // piece of the old `smart_format` worth asking for explicitly,
            // since the transcript is shown as prose and handed to the rewrite
            // as-is.
            .init(name: "numerals", value: "true")
        ]
        guard let url = components.url else { throw SessionError.unavailable }

        var request = URLRequest(url: url)
        // Deepgram's own scheme, not Bearer.
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        return task
    }

    /// Turn events in, two states out. A turn in progress is the partial; a turn
    /// that ended is a bubble. That split is the entire contract the Transcribing
    /// screen animates off, so it is kept here and nowhere else.
    private func consumeResults(from socket: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard let self, !Task.isCancelled else { return }
                    // Any frame at all proves the handshake succeeded — the
                    // `Connected` frame Flux sends before the first word counts
                    // just as much as a transcript.
                    self.hasReceived = true
                    guard case let .string(text) = message,
                          let data = text.data(using: .utf8),
                          let frame = try? JSONDecoder().decode(FluxFrame.self, from: data)
                    else { continue }
                    self.apply(frame)
                } catch {
                    guard let self, !Task.isCancelled else { return }
                    // A socket that dies before it ever said anything did not
                    // "drop" — it was refused, almost always a bad or expired
                    // key, and telling the user their connection was lost would
                    // send them to debug the wrong thing. `resume()` returns
                    // before the handshake completes, so a 401 on the upgrade
                    // arrives here rather than at `openSocket`.
                    if self.hasReceived {
                        self.fail("Lost the connection to the transcription service. Everything you've said so far is still here — tap ✓ to keep it.")
                    } else {
                        self.fail("The transcription service refused the connection — the API key is probably missing or invalid. (\(error.localizedDescription))")
                    }
                    return
                }
            }
        }
    }

    /// Folds one Flux frame into the two states the screen reads.
    ///
    /// Flux's `transcript` is the whole turn so far, not a delta, so every
    /// in-progress event simply *replaces* the partial — there is nothing to
    /// accumulate and no risk of a word landing twice.
    private func apply(_ frame: FluxFrame) {
        switch frame.type {
        case "TurnInfo":
            switch frame.event {
            case "StartOfTurn":
                // Carries no words yet. Clearing here rather than on `EndOfTurn`
                // alone means a turn that ended with nothing usable cannot leave
                // the last turn's text sitting under the new one.
                partialUtterance = ""
            case "Update", "EagerEndOfTurn":
                // `EagerEndOfTurn` is a guess that the speaker is done, and Flux
                // is allowed to take it back with `TurnResumed`. Treating it as
                // final would be the v1 mistake again — a thought cut in half at
                // the first confident-looking pause — so it only updates the
                // partial, exactly like `Update`.
                guard let transcript = frame.transcript, !transcript.isEmpty else { break }
                partialUtterance = transcript
            case "TurnResumed":
                // The speaker was not done. Nothing was committed, so there is
                // nothing to undo; the next `Update` carries the longer turn.
                break
            case "EndOfTurn":
                // The one event that settles a bubble. The frame normally
                // carries the finished turn, but falling back to the partial
                // means a sparse `EndOfTurn` can never silently eat words.
                let settled = frame.transcript.flatMap { $0.isEmpty ? nil : $0 } ?? partialUtterance
                if !settled.isEmpty { finalizedUtterances.append(settled) }
                partialUtterance = ""
            default:
                break
            }
        case "FatalError":
            // Flux's own way of ending the stream. Reported with its text
            // because these are the failures that only reproduce on someone
            // else's phone, and "lost the connection" would hide the reason.
            fail("The transcription service stopped the session. Everything you've said so far is still here — tap ✓ to keep it. (\(frame.description ?? "no reason given"))")
        default:
            // `Connected`, `ConfigureSuccess`, and anything Deepgram adds later.
            break
        }
    }

    private func startTicking() {
        let started = Date.now
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                self.elapsed = self.elapsedBeforeResume + Date.now.timeIntervalSince(started)
            }
        }
    }

    /// `CloseStream` rather than a bare cancel: it ends the stream on Deepgram's
    /// terms instead of yanking the socket mid-frame. The last few words of a
    /// capture do not depend on it — `stop()` settles whatever partial was
    /// standing before this runs — but a half-closed socket is a leak the
    /// server has to time out, and there is no reason to leave one behind.
    private func closeSocket() {
        if let socket {
            socket.send(.string(#"{"type":"CloseStream"}"#)) { _ in
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
        socket = nil
        sink = nil
    }

    // MARK: Audio

    /// Starts the microphone off the main actor and waits for it. The `await`
    /// is the whole point: the blocking CoreAudio work happens on a detached
    /// task, so the screen keeps redrawing and the watchdog keeps ticking while
    /// it runs.
    private func startCapture() async throws {
        guard let sink else { throw SessionError.unavailable }
        let capture = self.capture
        // Level arrives on the realtime audio thread hundreds of times a
        // minute; it hops to the main actor here and nowhere else.
        let onLevel: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor in self?.level = value }
        }
        try await Task.detached(priority: .userInitiated) {
            try capture.start(sink: sink, onLevel: onLevel)
        }.value
    }

    /// Teardown is fire-and-forget for the same reason: `setActive(false)` and
    /// `engine.stop()` block too, and nothing on screen is waiting on them.
    private func stopCapture() {
        let capture = self.capture
        Task.detached(priority: .userInitiated) { capture.stop() }
    }

    // MARK: State

    /// Advances the visible bring-up step and restarts its watchdog budget.
    private func stage(_ message: String) {
        print("[Deepgram] \(message)")
        statusMessage = message
        stageStartedAt = .now
    }

    /// One place to land in when a session cannot run, so the watchdog and the
    /// `catch` cannot disagree about what state a dead session is in.
    private func fail(_ message: String) {
        // The user gets the sentence; the console gets it too, because these are
        // the failures that only ever reproduce on someone else's phone.
        print("[Deepgram] session failed: \(message)")
        failed = true
        failureMessage = message
        preparing = false
        statusMessage = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        // A failed session must not leave the microphone hot. This is reached
        // from the watchdog as well as from `catch`, and the watchdog fires
        // while the bring-up is still in flight — so teardown belongs here
        // rather than only on the throwing path.
        stopCapture()
        closeSocket()
    }

    /// Turns a thrown error into something worth reading. The generic case still
    /// carries the underlying description: an unrecognised failure the user can
    /// screenshot is worth more than a tidy sentence that says nothing.
    private func message(for error: Error) -> String {
        switch error {
        case SessionError.denied:
            return "Notes doesn't have microphone access yet. Turn it on in Settings › Notes, then start again."
        case SessionError.noKey:
            return "No transcription key is configured in this build, so there's nothing to send audio to."
        case SessionError.unavailable, AudioCaptureError.unavailable:
            return "The microphone isn't available right now — something else may be using it."
        default:
            return "Couldn't start listening: \(error.localizedDescription)"
        }
    }

    private enum SessionError: Error {
        /// The build has no Deepgram key.
        case noKey
        /// The audio route is not usable.
        case unavailable
        /// The user said no to the microphone.
        case denied
    }
}

// MARK: - Wire types

/// Only the four fields the screen actually reads. A Flux frame carries a great
/// deal more — per-word timings and confidences, the audio window, the
/// end-of-turn confidence, what triggered it — and decoding it all would be a
/// maintenance burden for data nothing displays.
///
/// `type` and `event` are plain strings rather than enums on purpose. Deepgram
/// can add an event tomorrow, and an unknown case must fall through to "ignore
/// this frame", never to a decode failure that drops the *whole* frame — which
/// is how a stream would go silent on a value that was only ever informational.
private struct FluxFrame: Decodable {
    let type: String
    let event: String?
    /// The turn's transcript so far, cumulative rather than a delta. Absent on
    /// the non-transcript frames (`Connected`, `ConfigureSuccess`, `FatalError`).
    let transcript: String?
    /// Only on `FatalError`.
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case type, event, transcript, description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        event = try container.decodeIfPresent(String.self, forKey: .event)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }
}

/// Where the app's Deepgram key comes from, mirroring `GroqClient.configured`.
///
/// The placeholder cases matter: an unexpanded `$(DEEPGRAM_API_KEY)` is what you
/// get when the developer cloned the repo and never made their own
/// `Secrets.xcconfig`, and it must read as *absent*, not as a key that will fail
/// with a confusing 401 at the worst possible moment.
public enum DeepgramCredentials {
    public static var apiKey: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "DEEPGRAM_API_KEY") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placeholders: Set<String> = ["", "$(DEEPGRAM_API_KEY)", "YOUR_KEY_HERE"]
        return placeholders.contains(trimmed) ? nil : trimmed
    }
}

/// The microphone, and every synchronous CoreAudio call that comes with it.
///
/// Lives outside the main actor on purpose. `AVAudioSession.setActive`, the
/// first access to `inputNode` (which brings up the audio route) and
/// `engine.start()` all block their calling thread, sometimes for seconds and
/// occasionally forever when the route is contended. On the main actor that is
/// a frozen app *and* a dead watchdog, since the watchdog is a main-actor task
/// and cannot run while the main thread is stuck inside CoreAudio.
///
/// `@unchecked Sendable` is honest here: the caller only ever drives this from
/// its own serialised tasks, and the one piece of mutable state is behind a
/// lock.
private final class AudioCapture: @unchecked Sendable {
    /// 16 kHz mono is Deepgram's cheapest well-supported input and far above
    /// what speech needs; sending the microphone's native 48 kHz float would
    /// triple the bytes on the wire for no accuracy.
    static let sampleRate = 16_000.0

    private let engine = AVAudioEngine()
    /// Owns the `AVAudioConverter` across tap callbacks, which arrive on a
    /// realtime audio thread.
    private let converter = BufferConverter()

    /// Whether a tap is currently installed. `removeTap` on a bus with no tap
    /// is tolerated but `installTap` twice is not, and pause/resume walks that
    /// path repeatedly, so the state is tracked rather than guessed.
    private let lock = NSLock()
    private var isTapped = false

    /// `.measurement` mode turns off the processing that flatters music and
    /// hurts recognition; `.record` keeps us from grabbing playback we do not
    /// need. Called on resume as well as start, which is why it is idempotent.
    ///
    /// Every line of this blocks. Never call it from the main actor.
    func start(sink: AudioSink, onLevel: @escaping @Sendable (Double) -> Void) throws {
        guard let wireFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        ) else { throw AudioCaptureError.unavailable }

        let session = AVAudioSession.sharedInstance()
        // No options. `.duckOthers` lived here and is only legal on the
        // playback, playAndRecord and multiRoute categories — with `.record`
        // the session rejects the whole call with a bad-parameter error, which
        // killed every capture on a real device.
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let tapFormat = input.outputFormat(forBus: 0)
        // A zero sample rate means the route is not up yet — installing a tap
        // against it throws deep inside CoreAudio rather than returning.
        guard tapFormat.sampleRate > 0, tapFormat.channelCount > 0 else {
            throw AudioCaptureError.unavailable
        }

        lock.lock()
        let wasTapped = isTapped
        isTapped = false
        lock.unlock()
        if wasTapped { input.removeTap(onBus: 0) }

        let converter = converter
        // 4096 frames at the input node's native 48 kHz is ~85 ms per chunk,
        // which lands on the ~80 ms Deepgram recommends for Flux. Smaller chunks
        // cost round trips for no extra responsiveness; much larger ones delay
        // the turn model's view of the audio.
        input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
            // The input node's native format is essentially never the format we
            // send, so every buffer is resampled and narrowed to 16-bit on the
            // way through, then written straight to the socket from this thread.
            if let converted = converter.convert(buffer, to: wireFormat),
               let data = BufferConverter.data(from: converted) {
                sink.send(data)
            }
            // Sampled from the raw buffer rather than the converted one: this is
            // what the user's voice actually did, before any resampling.
            onLevel(BufferConverter.level(of: buffer))
        }
        lock.lock()
        isTapped = true
        lock.unlock()

        engine.prepare()
        try engine.start()
    }

    func stop() {
        lock.lock()
        let wasTapped = isTapped
        isTapped = false
        lock.unlock()
        if wasTapped { engine.inputNode.removeTap(onBus: 0) }

        if engine.isRunning { engine.stop() }
        // Handing the session back matters more than it looks: leaving it active
        // keeps the orange mic indicator lit long after the capture ended.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private enum AudioCaptureError: Error {
    /// The audio route is not usable.
    case unavailable
}

/// The socket as the realtime audio thread sees it: one method, no actor.
/// `URLSessionWebSocketTask` is thread-safe, so `@unchecked Sendable` is honest
/// here — this box exists to say so, not to bypass a real race.
private final class AudioSink: @unchecked Sendable {
    private let socket: URLSessionWebSocketTask
    init(socket: URLSessionWebSocketTask) { self.socket = socket }
    func send(_ data: Data) {
        // Errors are dropped rather than surfaced: the receive loop is already
        // watching the same socket and will report a drop once, with a sentence,
        // instead of once per buffer from the audio thread.
        socket.send(.data(data)) { _ in }
    }
}

/// Resampling and metering, kept off the main actor because the audio tap that
/// calls into it runs on a realtime thread and must not hop actors to do its
/// work. `@unchecked Sendable` is honest here: CoreAudio guarantees the tap is
/// serialised, so the single mutable converter inside is never raced.
private final class BufferConverter: @unchecked Sendable {
    /// A single-use handoff of one buffer into `AVAudioConverter`'s input block.
    /// Exists purely to get a non-`Sendable` buffer across a `@Sendable` closure
    /// boundary that, in practice, never leaves this thread.
    private final class PendingInput: @unchecked Sendable {
        private var buffer: AVAudioPCMBuffer?
        init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        func take() -> AVAudioPCMBuffer? {
            defer { buffer = nil }
            return buffer
        }
    }

    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }

        // Rebuilt only when the route changes underneath us (headphones in,
        // call ends); allocating one per buffer would be audible.
        if converter == nil || sourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
            sourceFormat = buffer.format
        }
        guard let converter else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        // The slack matters: sample-rate conversion is not frame-exact, and a
        // capacity that is merely "about right" silently truncates audio.
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        // The converter's input block is imported as `@Sendable`, so the buffer
        // it hands back and the "already handed it over" flag cannot simply be
        // captured locals. They go in a box instead; the block is called
        // synchronously on this thread, so nothing is actually shared.
        let pending = PendingInput(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            // One buffer in, one buffer out: telling the converter there is no
            // more data is what makes it flush rather than block.
            guard let next = pending.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return next
        }

        guard conversionError == nil, status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    /// The 16-bit samples as bytes, which is exactly what Deepgram's
    /// `linear16` encoding expects on the wire — no header, no framing.
    static func data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let channels = buffer.int16ChannelData, buffer.frameLength > 0 else { return nil }
        return Data(bytes: channels[0], count: Int(buffer.frameLength) * MemoryLayout<Int16>.size)
    }

    /// RMS in dB mapped onto 0…1. The floor is -50 dB rather than silence
    /// because a room's noise floor sits around there, and anchoring lower
    /// would leave the waveform permanently half-lit.
    static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = channels[0]
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<frames {
            let sample = samples[index]
            sum += sample * sample
        }
        let rms = (sum / Float(frames)).squareRoot()
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        return min(max((decibels + 50) / 50, 0), 1)
    }
}
#endif
