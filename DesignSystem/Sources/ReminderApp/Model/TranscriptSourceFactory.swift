import Foundation
import Observation

/// The single concrete type the screens hold.
///
/// This wrapper exists for one reason: `@Observable` does not survive an
/// existential. A view holding `@State private var source: any TranscriptSource`
/// compiles fine and then never redraws, because SwiftUI has no observable
/// object to register against — only a box. So the screens hold a
/// `CaptureSource`, which is itself `@Observable`, and reads through its
/// forwarding properties land on the underlying observable's getters, which is
/// exactly what observation tracking needs to see.
///
/// It is also where the simulator/device split lives, so no screen has to know
/// which implementation it got.
@MainActor
@Observable
public final class CaptureSource: TranscriptSource {
    /// Which implementation was chosen. Deliberately not an `any TranscriptSource`
    /// stored property with a protocol-typed getter — reads must reach the
    /// concrete observable class for tracking to register.
    private let underlying: any TranscriptSource

    /// `script` is consulted only when the simulated source is chosen; on a real
    /// device there is a microphone and the script is meaningless. Callers pass
    /// it so Editing's append dictation can keep sounding like someone returning
    /// to a half-written note when running in the Simulator.
    public init(script: [String]? = nil) {
        #if targetEnvironment(simulator) || !os(iOS)
        // The Simulator has no microphone worth listening to, and the macOS
        // build has no screens at all — it exists to type-check the model layer.
        self.underlying = SimulatedTranscriptSource(
            script: script ?? TranscriptSourceFactory.nextCaptureScript()
        )
        #else
        self.underlying = DeepgramTranscriptSource()
        #endif
    }

    public var finalizedUtterances: [String] { underlying.finalizedUtterances }
    public var partialUtterance: String { underlying.partialUtterance }
    public var level: Double { underlying.level }
    public var elapsed: TimeInterval { underlying.elapsed }
    public var isPaused: Bool { underlying.isPaused }

    /// True only when live recognition could not be brought up — no microphone
    /// permission, no key, no network, no usable audio route. Always false for
    /// the simulated source, which cannot fail, so screens can read it
    /// unconditionally.
    public var failed: Bool {
        #if targetEnvironment(simulator) || !os(iOS)
        return false
        #else
        return (underlying as? DeepgramTranscriptSource)?.failed ?? false
        #endif
    }

    /// True while the live session is still being brought up — permission,
    /// socket, microphone. The simulated source is listening the instant it is
    /// started, so it is never preparing.
    public var preparing: Bool {
        #if targetEnvironment(simulator) || !os(iOS)
        return false
        #else
        return (underlying as? DeepgramTranscriptSource)?.preparing ?? false
        #endif
    }

    /// What the live session is doing while `preparing`, in the user's words.
    public var statusMessage: String? {
        #if targetEnvironment(simulator) || !os(iOS)
        return nil
        #else
        return (underlying as? DeepgramTranscriptSource)?.statusMessage
        #endif
    }

    /// Why it `failed`, when there is something more useful to say than that it
    /// did.
    public var failureMessage: String? {
        #if targetEnvironment(simulator) || !os(iOS)
        return nil
        #else
        return (underlying as? DeepgramTranscriptSource)?.failureMessage
        #endif
    }

    public func start() { underlying.start() }
    public func stop() { underlying.stop() }
    public func pause() { underlying.pause() }
    public func resume() { underlying.resume() }
    public func fullTranscript() -> String { underlying.fullTranscript() }
}

@MainActor
public enum TranscriptSourceFactory {
    /// A fresh source for a new capture. Always a new instance: a capture's
    /// transcript is its own, and reusing a source would carry the last one's
    /// bubbles into it.
    public static func make(script: [String]? = nil) -> CaptureSource {
        CaptureSource(script: script)
    }

    /// How many scripted captures have been made this launch. Only ever read in
    /// the Simulator; on a device there is a microphone and the scripts are
    /// meaningless.
    private static var scriptIndex = 0

    /// The next monologue in the rotation, so consecutive captures in the
    /// Simulator differ.
    ///
    /// One fixed script would mean every capture ever made in the Simulator is
    /// the same note about the same trip — which is fine for judging the
    /// recording screen's layout, and useless for judging anything that reads
    /// what was said. The rotation is what makes the split and merge proposals
    /// reachable without a device.
    static func nextCaptureScript() -> [String] {
        let scripts = SimulatedTranscriptSource.captureScripts
        defer { scriptIndex += 1 }
        return scripts[scriptIndex % scripts.count]
    }
}
