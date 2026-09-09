// The app is iOS-only (per the plan: native SwiftUI, App Store, iOS APIs
// throughout). The screens are fenced off so `swift build` on macOS still
// checks the design system and the model layer, which are portable.
#if os(iOS)
import SwiftUI
import DesignSystem

/// **Screen 2 of 3.** Opened by Home's capture button, full-screen, and already
/// listening by the time it finishes presenting — the plan's "under three
/// seconds" rule means there is no arm-then-record step and no confirmation
/// before recording starts.
///
/// The transcript is not a chat log: it renders as the page it is about to
/// become — the same serif heading, dated eyebrow and left-aligned prose that
/// Editing shows — so recording reads as a live preview of the capture rather
/// than as a conversation with the recognizer. The heading stays "Untitled"
/// until there is enough body to read one out of.
///
/// "Done" ends the recording and hands straight off to Editing, pre-filled;
/// there is no "review your recording" step in between.
struct TranscribingView: View {
    /// Handed the finished draft; the caller stores it and pushes Editing.
    var onDone: (CaptureItem) -> Void
    var onCancel: () -> Void

    /// The real recognizer on a device, the scripted one in the Simulator —
    /// which has no microphone, so the flow would be unjudgeable there
    /// otherwise. The screen never learns which it got.
    @State private var source = TranscriptSourceFactory.make()
    @State private var levels: [Double] = Array(repeating: 0.04, count: 34)

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()

            transcriptScroll
        }
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { transport }
        .task {
            source.start()
        }
        .onChange(of: source.level) { _, level in
            levels.removeFirst()
            levels.append(max(0.04, level))
        }
        .onChange(of: source.isPaused) { _, paused in
            // Nothing is coming in, so the waveform flattens rather than
            // freezing half-drawn mid-word.
            if paused {
                levels = Array(repeating: 0.04, count: levels.count)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button {
                source.stop()
                onCancel()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.dsGlassIcon(size: 40))

            Spacer()

            HStack(spacing: DSSpacing.xxs) {
                if source.preparing {
                    // A clock reading 0:00 while the session is still coming up
                    // is a lie the user has no way to see through — it says
                    // "recording, zero seconds in" when nothing is being heard.
                    // The spinner says the true thing instead.
                    ProgressView()
                        .controlSize(.mini)
                    Text("Starting…")
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                } else {
                    Circle()
                        // Paused, the dot goes grey and stops breathing: the pill is
                        // the one place that says whether words are still landing.
                        .fill(source.isPaused ? DSColor.textTertiary : DSColor.danger)
                        .frame(width: 7, height: 7)
                        .opacity(source.isPaused || source.level > 0.15 ? 1 : 0.35)
                        .animation(.easeInOut(duration: 0.2), value: source.level > 0.15)
                        .animation(.easeInOut(duration: 0.2), value: source.isPaused)

                    // No word here: the dot already says listening or held, and the
                    // clock says the rest. A label as well was the same fact told
                    // three times.
                    Text(timeLabel)
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textPrimary)
                        // Digits only, so the pill doesn't twitch as the seconds
                        // change width — the face stays the system one.
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .frame(height: 40)
            .glassEffect(.regular, in: .capsule)

            Spacer()

            // Balances the leading button so the status pill stays centered.
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.bottom, DSSpacing.xs)
    }

    // MARK: Transcript

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    // The same masthead the capture will carry once it opens in
                    // Editing — set in the serif at the same size, so the page
                    // does not re-typeset itself at the handoff.
                    DSTightHeading(
                        heading,
                        size: 34,
                        weight: .semibold,
                        lineHeightMultiple: 0.76,
                        tracking: 36 * -0.02,
                        // Grey while it is still a placeholder: "Untitled" is
                        // not yet the capture's name, it is the space the name
                        // will land in.
                        color: hasHeading ? DSColor.textPrimary : DSColor.textTertiary,
                        face: .serif
                    )
                    .padding(.top, DSSpacing.xs)
                    .animation(.snappy(duration: 0.24), value: heading)

                    // No eyebrow here: the header's Listening pill already says
                    // this is being spoken right now, and a second live label
                    // under it would say the same thing twice. Editing needs
                    // one because a section there sits among dated others; on
                    // this screen there is only ever the one.
                    if source.failed {
                        // Silence and "can't hear you" look identical on a
                        // waveform, so the screen has to say which it is. A
                        // capture that quietly records nothing is the worst
                        // failure this app has — you'd walk away believing the
                        // thought was safe.
                        Text(source.failureMessage ?? "I can't hear anything. Check that Notes has microphone and speech access in Settings, then start again.")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(DSColor.danger)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if source.preparing, transcript.isEmpty {
                        // Which step it is on, not just that it is on one: a
                        // model download and a permission prompt want very
                        // different things from the user.
                        Text(source.statusMessage ?? "Getting ready to listen…")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(DSColor.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if transcript.isEmpty {
                        Text("Just start talking.")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(DSColor.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        liveParagraph(transcript)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.sm)
            }
            .onChange(of: transcript) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    /// The words so far with a caret blinking at the end of them — the same
    /// treatment a section being dictated into gets in Editing. The caret is
    /// what makes this read as a document being written rather than as a
    /// transcript being displayed.
    private func liveParagraph(_ text: String) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let lit = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            (
                Text(text)
                    + Text(text.isEmpty ? "" : " ")
                    // A hairline rule rather than the block glyph: this is a
                    // text caret, so it should look like the one the keyboard
                    // puts in a field, not like a cursor in a terminal.
                    + Text("\u{2502}").foregroundStyle(lit ? DSColor.textSecondary : Color.clear)
            )
            .font(.system(size: 18, weight: .regular))
            // The same grey the body reads in once it is a capture — this is
            // that body, being written, not a different kind of text.
            .foregroundStyle(DSColor.textSecondary)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Transport

    private var transport: some View {
        VStack(spacing: DSSpacing.sm) {
            waveform

            GlassEffectContainer(spacing: 20) {
                HStack(spacing: DSSpacing.md) {
                    Button {
                        source.stop()
                        onCancel()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.dsGlassIcon(size: 52))

                    // Pause and play, nothing else. Ending the recording is the
                    // check to its right — the big button holds the session
                    // rather than finishing it, so stopping to think is not one
                    // tap away from stopping altogether.
                    DSCaptureButton(
                        size: 72,
                        symbol: source.isPaused ? "play.fill" : "pause.fill",
                        label: source.isPaused ? "Resume recording" : "Pause recording"
                    ) {
                        togglePause()
                    }

                    Button {
                        finish()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.dsGlassIcon(size: 52))
                }
            }

            Text("Tap ✓ when you're done — nothing is lost either way.")
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textTertiary)
        }
        .padding(.bottom, DSSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            // A soft scrim so bubbles scrolling behind the transport fade out
            // rather than colliding with it.
            LinearGradient(
                colors: [DSColor.background.opacity(0), DSColor.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .allowsHitTesting(false)
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(DSColor.textPrimary.opacity(0.55))
                    .frame(width: 3, height: max(3, level * 34))
            }
        }
        .frame(height: 36)
        .animation(.easeOut(duration: 0.12), value: levels)
    }

    // MARK: Actions

    private func togglePause() {
        if source.isPaused {
            source.resume()
        } else {
            source.pause()
        }
    }

    private func finish() {
        source.stop()
        let transcript = source.fullTranscript().trimmingCharacters(in: .whitespaces)
        guard !transcript.isEmpty else {
            onCancel()
            return
        }
        // The heuristic draft first, so the capture is already classified,
        // titled and questioned before a single byte goes near the network —
        // if the rewrite never happens, this is what you keep, and it is a
        // usable capture rather than a stub.
        var draft = TriageEngine.draft(from: transcript)
        // But the body starts as *exactly* what was said, not the heuristic's
        // two-sentence read of it. Two reasons: the words on screen when you
        // tap ✓ should be the words still there when Editing opens, and the
        // rewrite is meant to be seen happening — it can only visibly rewrite
        // something if the something is the real thing first.
        draft.passages = [CapturePassage(text: transcript, createdAt: .now)]
        onDone(draft)
    }

    /// Everything heard so far, joined — finalized sentences plus the one still
    /// being spoken, so the page grows word by word rather than sentence by
    /// sentence.
    private var transcript: String {
        source.fullTranscript()
    }

    /// The heading is the AI's read of the body, exactly as in Editing — so it
    /// only exists once there is a settled sentence to read. Partial speech is
    /// deliberately excluded: a title that re-wrote itself on every word would
    /// be the noisiest thing on a screen whose whole job is to stay calm.
    private var heading: String {
        let settled = source.finalizedUtterances.joined(separator: " ")
        guard !settled.isEmpty else { return "Untitled" }
        return TriageEngine.title(forBody: settled, transcript: settled)
    }

    private var hasHeading: Bool { !source.finalizedUtterances.isEmpty }

    private var timeLabel: String {
        let total = Int(source.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#endif
