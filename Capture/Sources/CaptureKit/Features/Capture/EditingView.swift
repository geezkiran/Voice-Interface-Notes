// The app is iOS-only (per the plan: native SwiftUI, App Store, iOS APIs
// throughout). The screens are fenced off so `swift build` on macOS still
// checks the design system and the model layer, which are portable.
#if os(iOS)
import SwiftUI
import DesignSystem

/// **Screen 3 of 3.** One capture, opened either from a Home row or straight
/// off the end of a recording. Everything the AI produced is here and every
/// bit of it is editable — the plan's "correctable, not perfect" principle —
/// with the raw transcript kept underneath, never overwritten.
///
/// Edits commit as you make them, the way Notes does; there is no Save button
/// to forget to press — and nothing floats over the page in its resting state,
/// so the whole screen is the capture.
///
/// The body is a log rather than a field: `+` in the header starts dictating a
/// **new dated section** on the end of it, live, with the words landing in the
/// page as they're spoken and the page never leaving the screen. Nothing above
/// is touched — you work *on top of* what's already written.
struct EditingView: View {
    var store: CaptureStore
    var itemID: UUID
    /// True only when arriving straight off a recording. It no longer starts
    /// anything: the rewrite is a button now, so a capture lands on the page as
    /// the words that were actually said and stays that way until the user
    /// asks for a summary. Kept because the call sites still say which way in
    /// they came, and because that is the one arrival where the button is worth
    /// leading with.
    var analyzeOnOpen: Bool = false
    /// True only when arriving from Home's plus — a blank note made to be typed
    /// or pasted into, so the caret is put in it rather than the user having to
    /// find an empty line and tap it.
    var typeOnOpen: Bool = false
    /// True only when arriving straight off a recording — the one moment worth
    /// asking whether what was just said is really one note. Opening an old
    /// capture never proposes: the person has lived with that note's shape, and
    /// second-guessing it weeks later is the app being clever at them.
    var proposeOnOpen: Bool = false

    /// Accepts a merge — hands the source note and the note it should be folded
    /// into back to whoever owns the store and the navigation stack.
    var onMerge: (CaptureItem, UUID) -> Void = { _, _ in }
    /// Accepts a split, with the parts the model proposed.
    var onSplit: (CaptureItem, [CaptureProposal.Part]) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var draft: CaptureItem
    @State private var hasDue: Bool
    @State private var dueDate: Date
    @State private var hasFollowUp: Bool
    @State private var followUpDate: Date
    /// Which version of the body is on screen. The summary is the default —
    /// the transcript is the thing to fall back to when the summary reads
    /// wrong, so it costs one tap and never replaces anything. The toggle
    /// swaps the body only: the heading above it belongs to the AI and stays
    /// put until the body's content actually changes.
    @State private var showsOriginal = false
    /// Which section the keyboard is in, if any.
    @FocusState private var focusedPassage: UUID?
    /// Live dictation, running only while a section is being spoken into.
    /// Non-nil *is* the recording state; there is nothing else to keep in sync.
    @State private var dictation: CaptureSource?
    /// The section being dictated into. It exists in `draft` from the first
    /// moment — empty, then filling word by word — so the user is watching the
    /// real document grow, not a preview of one.
    @State private var livePassageID: UUID?

    /// The section the AI is rewriting, if it is rewriting one. Deliberately
    /// *not* `livePassageID`: both put a caret on a passage, but only dictation
    /// docks a transport at the foot of the screen, and only dictation is
    /// something the user started and can stop. Sharing one flag would put a
    /// Keep/Discard bar under a rewrite nobody asked to control.
    @State private var streamingPassageID: UUID?
    /// Set when the rewrite couldn't run or couldn't finish. What's on screen
    /// is then the heuristic draft, which is a real capture — so this drives a
    /// quiet retry, not an error state.
    @State private var analysisFailure: String?

    /// The in-flight re-read of the note, if there is one. Held so the next
    /// edit can cancel it: a note being worked on produces a run of these, and
    /// only the last one is describing the note as it actually ended up.
    @State private var refineTask: Task<Void, Never>?

    /// What the model thinks should happen to this capture — split it, fold it
    /// into an existing note, or (the usual answer) nothing at all. Nil until
    /// the question has been asked and answered with something worth showing.
    ///
    /// Never persisted. A proposal belongs to one trip into Editing, exactly
    /// like `analyzeOnOpen` does: a suggestion the user scrolled past is a
    /// suggestion they declined, and storing it would bring the card back every
    /// time they reopened the note.
    @State private var proposal: CaptureProposal?
    /// The note a merge proposal would fold this one into, resolved once so the
    /// card can name it.
    @State private var proposalTarget: CaptureItem?
    @State private var proposalTask: Task<Void, Never>?

    /// The reminder offer currently over the page, if there is one. Nil is the
    /// resting state and by far the common one — see `offerReminder`.
    @State private var reminderOffer: ReminderOffer?
    /// Whether this trip into the note has already asked about a reminder.
    ///
    /// One offer per visit, exactly like the merge/split proposal next door and
    /// for the same reason: a banner the person let expire is a banner they
    /// declined, and a note being edited produces a run of re-reads that would
    /// otherwise each raise it again. Not persisted — a note reopened next week
    /// is a note whose owner may well have changed their mind about it.
    @State private var hasOfferedReminder = false
    /// Whether the wheel is up. Separate from the offer, which is dismissed the
    /// moment the sheet opens: the banner has said what it came to say.
    @State private var isPickingReminder = false
    /// What the wheel opens on — the time the note suggested, when it suggested
    /// one, so "Pick a time" starts from the app's best guess rather than from
    /// this second.
    @State private var pickerDate = Self.defaultSlot

    /// Set once this note has been handed to a merge or a split, after which
    /// this screen must never write to the store again.
    ///
    /// Both actions delete the note this screen is editing. Everything on the
    /// page still commits on change, and the re-read is a request that may still
    /// be in flight — so without this, a refinement landing a second after the
    /// user tapped Split would call `store.upsert(draft)` on a capture that had
    /// just been deleted, and SwiftData would helpfully create it again. The
    /// symptom is a ghost note reappearing in Home moments after being split,
    /// which reads as the app losing track of what the user asked for.
    @State private var handedOff = false

    init(
        store: CaptureStore,
        itemID: UUID,
        analyzeOnOpen: Bool = false,
        typeOnOpen: Bool = false,
        proposeOnOpen: Bool = false,
        onMerge: @escaping (CaptureItem, UUID) -> Void = { _, _ in },
        onSplit: @escaping (CaptureItem, [CaptureProposal.Part]) -> Void = { _, _ in }
    ) {
        self.store = store
        self.itemID = itemID
        self.analyzeOnOpen = analyzeOnOpen
        self.typeOnOpen = typeOnOpen
        self.proposeOnOpen = proposeOnOpen
        self.onMerge = onMerge
        self.onSplit = onSplit
        let item = store.items.first(where: { $0.id == itemID })
            ?? CaptureItem(title: "Untitled capture")
        _draft = State(initialValue: item)
        _hasDue = State(initialValue: item.dueAt != nil)
        _dueDate = State(initialValue: item.dueAt ?? Self.defaultSlot)
        _hasFollowUp = State(initialValue: item.followUpAt != nil)
        _followUpDate = State(initialValue: item.followUpAt ?? Self.defaultSlot)
    }

    var body: some View {
        editor
            // Tapping off a section — on the heading, on the page's margin, on
            // the reminder rows — puts the keyboard down. Tapping into another
            // section still just moves the caret.
            .dismissesKeyboardOnOutsideTap()
            .overlay(alignment: .top) { reminderOverlay }
            .sheet(isPresented: $isPickingReminder) {
                ReminderPickerSheet(initial: pickerDate) { setReminder($0) }
                    .presentationDetents([.height(400)])
                    .presentationDragIndicator(.visible)
            }
    }

    private var editor: some View {
        ScrollViewReader { proxy in
            List {
                headerSection
                reminderSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            // The inset-grouped list reserves a tall empty band above its first
            // section for a header that isn't there; drop it so the title sits
            // just under the back button.
            .contentMargins(.top, 0, for: .scrollContent)
            // Headroom under the body while something is writing into it. At
            // the end of a note there is otherwise no scroll left to give, so
            // the last line can only sit hard against the transport bar — this
            // buys the room to keep the growing line a couple of lines clear of
            // it, and it costs nothing when nothing is being written.
            .contentMargins(
                .bottom,
                isDictating ? Self.liveHeadroom : 0,
                for: .scrollContent
            )
            .background(DSColor.background)
            // A plain overlay, not a toolbar item — a toolbar leading item's
            // Liquid Glass chrome isn't tunable, so the glass circle here is
            // applied by hand to match the rest of the app's floating controls.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) { header }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .onChange(of: liveText) { _, text in
                // Straight through, verbatim: what the recognizer has heard so
                // far *is* the section's text. No tidying, no re-summarizing,
                // no waiting for a sentence to finish — the page is the
                // transcript window.
                writeLive(text)
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.liveAnchor, anchor: .bottom)
                }
            }
            // The words land in a section that may well be below the fold, so
            // opening one takes the page there before the first word arrives —
            // waiting for `liveText` meant you watched a stale screen until you
            // had already said something.
            .onChange(of: livePassageID) { _, id in
                guard id != nil else { return }
                // A hop, because the row is only in the list after this update
                // commits; scrolling to an anchor that doesn't exist yet is a
                // no-op.
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(Self.liveAnchor, anchor: .bottom)
                    }
                }
            }
            .onDisappear { endDictation(keeping: true) }
            // The rewrite is no longer something to follow down the page — the
            // body is one shimmering line while it runs — but the finished
            // piece should be read from its top, so the page goes back to the
            // body when the answer lands.
            .onChange(of: isStreaming) { _, streaming in
                guard !streaming else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.liveAnchor, anchor: .top)
                }
            }
            // A hop, not a straight assignment: the field the caret is going
            // into is a row of a list that hasn't been laid out yet at `task`
            // time, and focusing a field that doesn't exist yet is a silent
            // no-op that leaves the keyboard down on a note made to be typed
            // into.
            .task {
                guard typeOnOpen, let first = draft.passages.first?.id else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                focusedPassage = first
            }
            // A capture that just came off a recording arrives titled by the
            // on-device read of it, which is the first words of what was said.
            // That is a placeholder, not a heading, so the real one starts
            // being written the moment the page opens rather than waiting for
            // a tap on Summarize. The body is untouched either way — this is
            // the heading, the type and the questions only.
            .task(id: analyzeOnOpen) {
                guard analyzeOnOpen else { return }
                refine(immediately: true, retitles: true)
            }
            // Asked once, on arrival from a recording, and never again for this
            // note. It runs alongside the re-read above rather than after it:
            // the two ask different models different questions about the same
            // words, neither needs the other's answer, and making the card wait
            // for the heading would put it on screen after the user has already
            // started reading.
            .task(id: proposeOnOpen) {
                guard proposeOnOpen else { return }
                propose()
            }
        }
        // Held back while the AI is writing: the body changes on every token,
        // and committing each one would be a few hundred saves for a result
        // that is written once at the end anyway. Nothing is at risk in the
        // gap — the transcript reached disk before this screen opened.
        .onChange(of: draft) { _, new in
            guard !isStreaming, !handedOff else { return }
            store.upsert(new)
        }
        // The shelf and the questions are the AI's read of the body, so they
        // keep up with the body as the body is written rather than waiting for
        // the caret to leave or for Summarize to be tapped. `refine()`
        // debounces, so a burst of typing is one request describing where the
        // person landed. The heading is left alone here — it is named once, on
        // arrival, and only Summarize rewrites it after that — and the body is
        // never touched, so Summarize still owns the rewrite.
        .onChange(of: draft.summary) { _, _ in
            refine()
            // The note the person is being asked about has just changed under
            // the question. Whatever is in flight describes a note that no
            // longer exists, and a card offering to split a paragraph they have
            // since rewritten is worse than no card at all — so the offer is
            // withdrawn rather than left standing over stale words.
            proposalTask?.cancel()
            if proposal != nil {
                withAnimation(.snappy(duration: 0.2)) { proposal = nil }
            }
        }
        .onDisappear {
            refineTask?.cancel()
            proposalTask?.cancel()
        }
        .onChange(of: hasDue) { _, on in draft.dueAt = on ? dueDate : nil }
        .onChange(of: dueDate) { _, date in if hasDue { draft.dueAt = date } }
        .onChange(of: hasFollowUp) { _, on in draft.followUpAt = on ? followUpDate : nil }
        .onChange(of: followUpDate) { _, date in if hasFollowUp { draft.followUpAt = date } }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                // Title and tag are one unit — the tag says what the title is,
                // so it sits tight under it, and the gap that separates the
                // pair from the body is the wider one below the tag.
                VStack(alignment: .leading, spacing: 0) {
                    // Serif, the same face Home's tabs are set in: this line is
                    // the capture's own title, so it belongs to the app's
                    // masthead voice rather than to the form under it. The
                    // serif carries more leading than the system face and reads
                    // loose at display size, so it takes a fuller line box and
                    // a proportional tracking pull, the same fraction the tabs
                    // use.
                    DSTightHeading(
                        draft.title.isEmpty ? "Untitled" : draft.title,
                        size: 34,
                        weight: .semibold,
                        lineHeightMultiple: 0.76,
                        tracking: 36 * -0.02,
                        face: .serif
                    )
                    .padding(.top, DSSpacing.xs)

                    // The day the capture was first made — fixed, unlike the
                    // ages under each section. Those say how long ago you last
                    // touched it; this one says when it started, and the two
                    // answers stop matching the moment you come back to a note,
                    // which is why both are on the page.
                    //
                    // Pulled up into the heading's own box: a tightened line
                    // box leaves the last line's descenders hanging outside it,
                    // and `DSTightHeading` pads for that spill at both ends. To
                    // the eye that padding *is* the gap, so the date has to
                    // borrow it back rather than stack on top of it. The
                    // asymmetry is the point — the date belongs to the title
                    // above it, not to the body below.
                    // Date and tag share one line: they are both answers about
                    // the same note — when it started, and what it turned out
                    // to be — and stacking them spent two lines of the
                    // masthead saying things that read as one. Baseline
                    // alignment keeps the chip sitting on the date's line
                    // rather than floating beside it.
                    HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                        Text(Self.originLabel(for: draft.createdAt))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(DSColor.textSecondary)

                        typeTag
                    }
                    .padding(.top, -DSSpacing.xxs)
                    // One line now, so this is the only gap carrying the
                    // masthead down to the body.
                    .padding(.bottom, DSSpacing.sm)
                }

                // Between the masthead and the body, because it is about the
                // note as a whole — what it should *be* — rather than about any
                // passage in it. Above the body rather than below because a
                // long note would bury it, and it is only worth offering while
                // the person is still deciding what they just said.
                if let proposal {
                    ProposalCard(
                        proposal: proposal,
                        mergeTarget: proposalTarget,
                        onAccept: { accept(proposal) },
                        onDismiss: {
                            withAnimation(.snappy(duration: 0.24)) { self.proposal = nil }
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if showsOriginal {
                    transcriptStack
                } else {
                    passageStack
                }

                // Under the body, on the body's own edge — a plain text button,
                // not a chip: it changes what you are reading, it is not a
                // property of the capture. It sits at the foot of the body
                // because checking the words as spoken is what you do *after*
                // reading the summary, not before.
                //
                // One button, never two. The page is only ever showing one of
                // the two versions, so there is only ever one thing worth
                // offering underneath it, and a row of two would make the
                // reader work out which one they are looking at from the labels
                // of the buttons offering to leave it.
                bodyAction
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DSSpacing.xs)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: DSSpacing.xxs, leading: DSSpacing.xs, bottom: DSSpacing.sm, trailing: DSSpacing.xs))
        // The scroll anchor lives on the *row*, not on the passage inside it.
        // `ScrollViewReader` in a `List` resolves ids of rows; an id on a view
        // nested in one is not a scroll target, so pointing at the live passage
        // was a silent no-op and the spoken text grew off the bottom of the
        // screen under the transport bar. The whole body is this one row and
        // the live passage is the last thing in it, so its bottom edge *is*
        // where the words are landing.
        .id(Self.liveAnchor)
    }

    /// Whether there is a shelf to print under the heading.
    ///
    /// Every capture carries a `type` from the moment it is made — the
    /// on-device triage guesses one so nothing is ever unfiled — and that guess
    /// is what goes on the page, immediately. It used to wait for `typedAt`, so
    /// the tag arrived only once a model had read the note: a debounce plus a
    /// round trip, several seconds of a masthead with a hole in it on a page
    /// the user is already reading. A shelf that is right most of the time and
    /// there instantly beats a shelf that is right always and arrives after you
    /// have stopped looking — and when the model's read lands it replaces this
    /// one in place, so the correction costs nothing.
    ///
    /// The one thing still worth waiting for is words: a note with nothing in
    /// it has no subject to be about, and triage's fallback shelf under an
    /// "Untitled" heading is the app talking to itself.
    private var hasTypeTag: Bool {
        draft.typedAt != nil
            || !draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The category, on the date's line under the heading: this is the second
    /// line of the masthead, not a control. It is a plain neutral chip —
    /// there is nothing to pick here, the shelf is the app's read of the note,
    /// and giving it a selected tone would make it look like a filter that
    /// happened to be on.
    ///
    /// It fades in rather than appearing, because it arrives while the user is
    /// already reading the page and a tag that pops into the middle of a
    /// sentence being read pulls the eye off the words.
    @ViewBuilder
    private var typeTag: some View {
        if hasTypeTag {
            DSChip(draft.type.label, systemImage: draft.type.symbol)
                .transition(.opacity)
        }
    }

    /// Whether there is a raw record to fall back to. A typed or pasted note
    /// has none — what is on the page *is* the original — so the toggle is not
    /// merely empty there, it is a question with no meaning. It appears the
    /// moment the note is first spoken into.
    private var hasOriginal: Bool { !draft.transcriptSegments.isEmpty }

    /// The raw record, one dated block per time you spoke into this capture.
    ///
    /// Eyebrowed the way the body's sections used to be, and this is now the
    /// only place on the page that carries ages: the summary is what the note
    /// *says* and reads as one piece of prose, while the original is a record
    /// of when things were said, and a record with the dates taken out is just
    /// a wall of text. Never editable — these are the words as spoken.
    private var transcriptStack: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            if draft.transcriptSegments.isEmpty {
                Text("No transcript for this capture.")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(draft.transcriptSegments) { segment in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(segment.text)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(DSColor.textSecondary)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DSEyebrow(Self.sectionLabel(for: segment.createdAt))
                }
            }
        }
    }

    // MARK: Body sections

    /// The body, one dated section per sitting. The eyebrow under each one is
    /// the whole point of the split: a capture you have come back to twice
    /// should read like a page of a notebook, where you can see which day each
    /// paragraph belongs to, rather than like one field that quietly changed.
    ///
    /// Every section stays editable by hand. The live one is the exception —
    /// while it is being spoken it is text, not a field, because a caret you
    /// can move and a caret the recognizer is pushing along are two different
    /// things and only one of them can be true at a time.
    @ViewBuilder
    private var passageStack: some View {
        if isStreaming {
            generatingPlaceholder
        } else {
            writtenPassages
        }
    }

    /// What stands on the page while the rewrite is out: one line, shimmering,
    /// and nothing else. The body it is replacing is still in `draft` — it is
    /// only hidden — so a failure puts the words straight back and a success
    /// fades the finished piece in over this.
    ///
    /// Deliberately *not* the tokens as they arrive. The rewrite works over
    /// sentences the user has already read, so streaming it in place shows them
    /// their own note being taken apart; a page that says it is busy and then
    /// hands back the finished thing is the same wait without the vandalism.
    private var generatingPlaceholder: some View {
        DSShimmerText("Generating…")
            .frame(maxWidth: .infinity, alignment: .leading)
            // The body's own top edge, and enough height that the page doesn't
            // collapse to a single line and snap back when the answer lands.
            .frame(minHeight: 96, alignment: .topLeading)
            .transition(.opacity)
            .accessibilityLabel("Generating a summary")
    }

    private var writtenPassages: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            ForEach($draft.passages) { $passage in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    // A caret you can move and a caret the recognizer is
                    // pushing along can't both be true at once — so while the
                    // section is being spoken into it is text, not a field.
                    if passage.id == livePassageID {
                        liveParagraph(passage.text)
                    } else {
                        // "Empty section" is the right word for a blank left in
                        // the middle of a note that already says things; on a
                        // note that says nothing at all it reads as a fault
                        // report rather than an invitation.
                        TextField(
                            draft.passages.count == 1 ? "Start typing, or paste" : "Empty section",
                            text: $passage.text,
                            axis: .vertical
                        )
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(DSColor.textSecondary)
                            .lineSpacing(4)
                            .focused($focusedPassage, equals: passage.id)
                    }

                    // No per-section date any more — the header's origin line
                    // is the one date the page carries. Nor an "adding now"
                    // status while dictating: the transport capsule at the foot
                    // of the page already says the mic is open, and saying it
                    // twice put a second red dot beside the words being spoken.
                    // Nor one for the rewrite: the whole body is replaced by
                    // the shimmering line while that runs, and a label under a
                    // placeholder that already says "Generating…" is the same
                    // sentence twice.
                }
                .id(passage.id.uuidString)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if draft.passages.isEmpty {
                Text("Nothing written yet — tap + and say it.")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(DSColor.textTertiary)
            }

            if Self.showsQuestions {
                questionsPanel
            }
        }
        // Pairs with the placeholder's own fade: the two swap in place when the
        // rewrite starts and again when it lands.
        .transition(.opacity)
    }

    /// Off for now — the questions are parked, not deleted. The panel below is
    /// finished and stays wired to the same data; flip this back to `true` to
    /// put it back on the page.
    private static let showsQuestions = false

    /// What the AI didn't get from what you said, asked back.
    ///
    /// Deliberately inert: no field, no tap target, no chip, no "answer"
    /// affordance of any kind. The questions are here to make you think one
    /// step further while you are already reading the page — answering them is
    /// something you do by talking, with `+`, like everything else. Giving them
    /// a control would turn the bottom of a note back into a form, which is the
    /// exact thing this app exists to avoid.
    ///
    /// They used to run together as one italic paragraph in the body's own size
    /// and colour, which put them on the page as prose you had already read —
    /// they blurred into the last section and, run together, they read as one
    /// long cramped sentence. So they get their own surface instead: a white
    /// panel on the page's gray, set well below the last section, with each
    /// question on its own line, a hairline between them, and room around every
    /// one. The panel is what separates them from the body; nothing inside it
    /// is a control, so it still isn't a form.
    @ViewBuilder
    private var questionsPanel: some View {
        let asked = draft.followUpQuestions
            .map { $0.question.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !asked.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                // Says what the panel is, once, so no question has to carry a
                // "we're asking you something" tone of its own.
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("still open")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.2)
                }
                .foregroundStyle(DSColor.textTertiary)

                ForEach(Array(asked.enumerated()), id: \.offset) { index, question in
                    if index > 0 {
                        Rectangle()
                            .fill(DSColor.borderSubtle)
                            .frame(height: 1)
                    }

                    // A notch smaller than the body and set in the primary ink
                    // rather than the body's gray: the size says "not the
                    // note", the weight says "read me". Loose leading, because
                    // a question you are meant to sit with should not be set
                    // tighter than the prose above it.
                    Text(question)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.md)
            .background(DSColor.surface, in: .rect(cornerRadius: DSRadius.lg))
            // The gap above is doing as much work as the panel itself — it is
            // what stops this reading as the note's last paragraph.
            .padding(.top, DSSpacing.md)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Still open. \(asked.joined(separator: " "))")
        }
    }

    /// The section being dictated into: the words so far, plus a caret that
    /// blinks at the end of them. The caret is doing the real work here — it
    /// is what makes this read as typing into a document rather than as a
    /// transcript being displayed somewhere.
    private func liveParagraph(_ text: String) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let lit = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            (
                Text(text)
                    + Text(text.isEmpty ? "" : " ")
                    // A hairline rule rather than the block glyph — the same
                    // caret Transcribing draws, and the same one the keyboard
                    // would put here.
                    + Text("\u{2502}").foregroundStyle(lit ? DSColor.textPrimary : Color.clear)
            )
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(DSColor.textPrimary)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Back, and nothing else. The type used to float up here in glass beside
    /// it, which put the answer to "what is this?" in the corner reserved for
    /// chrome; it reads as a kicker over the title instead, and the header is
    /// left doing the one job a header is for.
    private var header: some View {
        HStack(spacing: DSSpacing.xs) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    // A glyph size rather than a text token: this is ink on a
                    // disc, and at body size it read small inside it.
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.xxs)
    }

    /// Matches the capture button in `DSTabBar`'s bottom bar.
    private static let addButtonSize: CGFloat = 60

    /// Adds to the capture — always by voice, always as a new dated section.
    /// Floating at the bottom right, thumb-high, the same gesture as the
    /// capture button on Home but aimed at something that already exists.
    /// It is the page's one standing action, so it gets the one standing spot.
    private var addButton: some View {
        Button {
            startDictation()
        } label: {
            // Sized off Home's capture button — same diameter, same glyph
            // ratio. It is the same gesture aimed at a different target, so it
            // should be the same size target under the thumb; it stays plain
            // glass rather than tinted because the yellow one means "start
            // something new" and this one adds to what is already open.
            DSVectorIconView(
                .levels,
                size: Self.addButtonSize * DSCaptureButton.drawnGlyphRatio,
                lineWidth: 2.2
            )
                .foregroundStyle(DSColor.textPrimary)
                .frame(width: Self.addButtonSize, height: Self.addButtonSize)
                // Same reason as `DSCaptureButton`: the drawn glyph is a
                // stroked shape and hit-tests only on its own strokes, so the
                // disc has to declare the target.
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to this capture by voice")
    }

    /// The times set on this capture — and nothing at all when none are.
    ///
    /// This used to be a standing Timing section on every note: two switches, a
    /// picker and a priority wheel under an idea, a shopping list, a paragraph
    /// of thinking. A form under a page that is meant to read as a page. The
    /// question it was asking is now asked by `ReminderBanner`, only on the
    /// notes whose own words suggest it, and only over the page — so what is
    /// left here is not a question but a record: the reminder you set, where you
    /// can move it or take it off again.
    ///
    /// Which is why it is empty until something is set. There is nothing to say
    /// about the timing of a note that has none.
    ///
    /// Priority went with the switches. Nothing in the app reads it — no row, no
    /// sort, no filter — so it was a control whose only effect was to be there,
    /// on every note, asking.
    @ViewBuilder
    private var reminderSection: some View {
        if hasDue || hasFollowUp {
            Section("Reminder") {
                if hasDue {
                    DatePicker("Remind me", selection: $dueDate)
                        .datePickerStyle(.compact)
                    Toggle("Reminder on", isOn: $hasDue.animation())
                        .dsSwitchTint()
                }

                if hasFollowUp {
                    DatePicker("Follow up", selection: $followUpDate)
                        .datePickerStyle(.compact)
                    Toggle("Follow up on", isOn: $hasFollowUp.animation())
                        .dsSwitchTint()
                }
            }
            .font(DSFont.body)
            .listRowBackground(DSColor.surface)
        }
    }

    // MARK: The reminder offer

    /// One offer, over the page. A struct rather than a bare `Date?` because the
    /// two states worth telling apart are "no offer" and "an offer that carries
    /// no time" — a note that should be remembered but never said when.
    private struct ReminderOffer: Equatable, Identifiable {
        var suggestedAt: Date?
        /// Fresh on every offer, so an offer raised twice in one visit — which
        /// `hasOfferedReminder` already prevents — could never be mistaken by
        /// the auto-dismiss timer for the one it started counting on.
        var id = UUID()
    }

    /// How long the banner stands before it withdraws itself. Long enough to be
    /// read and answered without hurry, short enough that ignoring it is a real
    /// way to say no rather than a thing you have to sit through.
    private static let reminderOfferLifetime: Duration = .seconds(9)

    /// Where the banner sits: under the back button rather than over it. A real
    /// notification covers the top of the screen, but the top of this screen is
    /// the only way out of it, and a card that eats the back button for nine
    /// seconds is a card holding the user hostage while it asks a favour.
    private static let reminderOfferTopInset: CGFloat = 56

    @ViewBuilder
    private var reminderOverlay: some View {
        if let offer = reminderOffer {
            ReminderBanner(
                suggestedAt: offer.suggestedAt,
                onPick: { setReminder($0) },
                onCustom: {
                    pickerDate = offer.suggestedAt ?? Self.defaultSlot
                    dismissReminderOffer()
                    isPickingReminder = true
                },
                onDismiss: { dismissReminderOffer() }
            )
            .padding(.horizontal, DSSpacing.sm)
            .padding(.top, Self.reminderOfferTopInset)
            .transition(.move(edge: .top).combined(with: .opacity))
            // Tied to the offer's own id, so the countdown belongs to the banner
            // on screen and dies with it.
            .task(id: offer.id) {
                try? await Task.sleep(for: Self.reminderOfferLifetime)
                guard !Task.isCancelled else { return }
                dismissReminderOffer()
            }
        }
    }

    /// Puts the banner up, if this is a note and a moment worth putting it up
    /// for.
    ///
    /// Four things have to be true, and each rules out a way this could become
    /// nagging rather than useful: the model has to have read the note as
    /// something to act on; the note must not already carry a time, since the
    /// answer is then already yes; this visit must not have asked already; and
    /// the note must still exist, which it doesn't after a merge or a split.
    private func offerReminder(_ needed: Bool, at suggested: Date?) {
        guard needed, !hasDue, !hasOfferedReminder, !handedOff else { return }
        // A time the model resolved into the past — "this morning", read back
        // this evening — is a suggestion that has expired. The offer still
        // stands; it just falls back to the app's own slots.
        let usable = suggested.flatMap { $0 > .now ? $0 : nil }
        hasOfferedReminder = true
        pickerDate = usable ?? Self.defaultSlot
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            reminderOffer = ReminderOffer(suggestedAt: usable)
        }
    }

    private func dismissReminderOffer() {
        guard reminderOffer != nil else { return }
        withAnimation(.snappy(duration: 0.24)) { reminderOffer = nil }
    }

    /// Accepts a time. The order matters: `dueDate` is set first so that
    /// switching `hasDue` on commits the chosen time rather than the default
    /// slot the screen opened with.
    private func setReminder(_ date: Date) {
        dueDate = date
        withAnimation(.snappy(duration: 0.24)) {
            hasDue = true
            reminderOffer = nil
        }
    }

    // MARK: Floating action

    /// The foot of the page holds exactly one thing, and which one depends on
    /// whether you are talking: `+` when you aren't, the recording session when
    /// you are. They are the same gesture at two moments — the button starts
    /// the thing the bar then owns — so they take turns in one place rather
    /// than sitting side by side with one of them always inert.
    private var bottomBar: some View {
        Group {
            if isDictating {
                dictationBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                addButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.xs)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
    }

    /// The recording session, docked to the foot of the page the words are
    /// landing in — deliberately *not* the Transcribing screen's transport,
    /// which is a full-screen instrument for a capture that has no context yet.
    /// Here the content is the context, so the controls stay a single low
    /// capsule and the page above them is never covered.
    private var dictationBar: some View {
        GlassEffectContainer(spacing: 16) {
            // Discard and Keep are opposite answers to the same question, so
            // they get a real gap between them rather than sitting close enough
            // to read as one segmented control.
            HStack(spacing: DSSpacing.sm) {
                Button {
                    endDictation(keeping: false)
                } label: {
                    Image(systemName: "xmark")
                        .font(DSFont.bodyEmphasis)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(width: 48, height: 48)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Discard this addition")

                Button {
                    endDictation(keeping: true)
                } label: {
                    HStack(spacing: DSSpacing.sm) {
                        // The level, as one dot breathing rather than a
                        // waveform — this bar is furniture beside the text, not
                        // the main event.
                        Circle()
                            .fill(DSColor.danger)
                            .frame(width: 9, height: 9)
                            .scaleEffect(1 + (dictation?.level ?? 0) * 0.7)
                            .animation(.easeOut(duration: 0.12), value: dictation?.level ?? 0)

                        // The running time is the one thing on this bar that
                        // changes, so it is set at reading size rather than as
                        // metadata — legible at a glance without looking down.
                        Text(elapsedLabel)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(DSColor.textSecondary)
                            .monospacedDigit()

                        Rectangle()
                            .fill(DSColor.border)
                            .frame(width: 1, height: 18)

                        Text("Keep")
                            .font(DSFont.bodyEmphasis)
                            .foregroundStyle(DSColor.textPrimary)
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .frame(height: 48)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, DSSpacing.xs)
        .frame(maxWidth: .infinity)
    }

    // MARK: Dictation

    private static let liveAnchor = "live-passage"

    /// How much empty scroll to hold below the body while it is being written
    /// into. Roughly two lines of body text, so the words landing now sit above
    /// the transport bar rather than under its top edge.
    private static let liveHeadroom: CGFloat = 56

    private var isDictating: Bool { livePassageID != nil }

    /// Everything heard this session, joined — finalized sentences plus the one
    /// still being spoken, which is what makes the text grow word by word
    /// rather than sentence by sentence.
    private var liveText: String {
        dictation?.fullTranscript() ?? ""
    }

    private var elapsedLabel: String {
        let total = Int(dictation?.elapsed ?? 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Opens the new section first and starts listening second, so there is
    /// somewhere for the first word to land the instant it arrives.
    private func startDictation() {
        guard !isDictating else { return }
        focusedPassage = nil
        // Voice adds to the body, so if the raw transcript is what's on screen,
        // switch back to the thing being written into.
        showsOriginal = false

        withAnimation(.snappy(duration: 0.24)) {
            livePassageID = draft.openPassage()
        }
        // The append script is only ever reached on the simulated path; on a
        // device this is the real recognizer and the argument is ignored.
        let source = TranscriptSourceFactory.make(script: SimulatedTranscriptSource.appendScript)
        dictation = source
        source.start()
    }

    private func writeLive(_ text: String) {
        guard let id = livePassageID,
              let index = draft.passages.firstIndex(where: { $0.id == id }) else { return }
        draft.passages[index].text = text
    }

    /// Ends the session. Keeping commits the section as spoken and logs it onto
    /// the raw transcript; discarding takes the section back out again, leaving
    /// the capture exactly as it was — an addition is never a half-edit of what
    /// was already there.
    private func endDictation(keeping: Bool) {
        guard let id = livePassageID else { return }
        dictation?.stop()
        let spoken = (dictation?.fullTranscript() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        dictation = nil
        withAnimation(.snappy(duration: 0.24)) { livePassageID = nil }

        guard let index = draft.passages.firstIndex(where: { $0.id == id }) else { return }
        if keeping, !spoken.isEmpty {
            draft.passages[index].text = spoken
            // Logged as its own dated recording, sharing the section's date:
            // one sitting produced both, and "See Original" reads them back
            // side by side.
            draft.appendTranscript(spoken, at: draft.passages[index].createdAt)
            // A kept addition is a change to the note, so the note gets
            // re-read — the shelf, the questions and the action items catch up
            // with what was just said. What it is *not* is a retitle: the
            // heading is the name this note has been found by since it was
            // written, and a paragraph spoken onto the end of it is not a
            // request to rename it, so `refine` leaves the heading alone.
            refine()
        } else {
            withAnimation(.snappy(duration: 0.24)) {
                _ = draft.passages.remove(at: index)
            }
        }
    }

    // MARK: Analysis

    private var isStreaming: Bool { streamingPassageID != nil }

    /// Sends the transcript off to be rewritten. The tokens are collected off
    /// screen — the body is a shimmering "Generating…" line for the duration —
    /// and the finished piece fades in over it in one go.
    ///
    /// Only the body is touched — the transcript is never in play, so "See
    /// Original" holds what was actually said no matter how this goes. If it
    /// goes badly the words are put back exactly as they were and the capture
    /// stands; the one outcome that must never happen is a body left holding
    /// half a report.
    ///
    /// Every run of this is a tap on Summarize — nothing starts it on its own,
    /// so there is no stamp to check and no first-run flag to keep: the user
    /// asking twice is the user asking twice, and the only thing that has to
    /// hold is that two runs can't overlap.
    private func runAnalysis() async {
        // The *whole* body, every section of it. A note you came back to twice
        // is one note, and a summary written from only the first sitting is a
        // summary of a note that no longer exists — so what goes out is the
        // page as it currently reads, and what comes back replaces all of it.
        //
        // The transcript stands in only for the case where there is no body to
        // send, which is a capture whose sections are somehow all empty.
        let body = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = body.isEmpty
            ? draft.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            : body
        guard !isStreaming, !source.isEmpty else { return }

        guard GroqClient.configured.hasKey else {
            analysisFailure = "No API key — this capture is filed by the on-device read of it."
            return
        }

        guard let target = draft.passages.first else { return }
        let spokenWords = target.text
        analysisFailure = nil
        withAnimation(.snappy(duration: 0.24)) { streamingPassageID = target.id }

        do {
            let analysis = try await CaptureAnalyzer.analyze(
                note: source,
                onPartial: { title, reportSoFar in
                    writeStreamed(title: title, report: reportSoFar)
                }
            )
            // A shade slower than the rest of the page's animations: this is
            // the moment the answer arrives, and a crossfade you can see is
            // what makes it read as the page settling rather than as a flicker.
            withAnimation(.easeOut(duration: 0.35)) {
                streamingPassageID = nil
                draft = analysis.applied(to: draft)
            }
            // Asked once the page has settled on the finished report, so the
            // banner lands over a note the person can actually read rather than
            // over a shimmering placeholder.
            offerReminder(analysis.needsReminder, at: analysis.suggestedDueAt)
        } catch is CancellationError {
            // Left the screen mid-rewrite. Put the words back rather than
            // leaving a half-written report standing as the body.
            restore(spokenWords, in: target.id)
        } catch {
            restore(spokenWords, in: target.id)
            analysisFailure = error.localizedDescription
        }
        // One write, at the end. Saving on every token would put a few hundred
        // disk writes behind a single capture for no gain: the transcript was
        // already durable before this screen even opened.
        //
        // Skipped entirely if the note was split or merged away while the
        // rewrite was running — the report describes a capture that no longer
        // exists, and writing it would bring the capture back with it.
        guard !handedOff else { return }
        store.upsert(draft)
    }

    // MARK: Keeping the note's read of itself current

    /// Re-reads the whole note and refreshes what the app says about it — the
    /// heading, the type, the questions, the action items. The body is never
    /// touched: `CaptureRefinement` has no way to express a change to it.
    ///
    /// Called whenever the note actually changes, which is the point — a
    /// heading written for the first sentence stops being true by the third
    /// paragraph, and questions answered by an edit should stop being asked.
    /// The whole note goes to the model each time, so what comes back describes
    /// the note as a whole rather than the last thing typed into it.
    ///
    /// The delay is a debounce with a second job. Edits arrive in bursts — a
    /// sentence rewritten four times in twenty seconds is four commits — and
    /// waiting means one request describing where the person landed instead of
    /// four describing where they passed through.
    ///
    /// `immediately` skips the wait for the one call that isn't an edit: the
    /// read that runs as the page opens. Nothing is going to arrive a moment
    /// later to supersede it, so a debounce there is a second of dead air on
    /// the heading and the shelf for no gain.
    ///
    /// `retitles` is off for every call but that first one. The heading is the
    /// name the person has since been finding this note by, and adding a
    /// paragraph to a note is not asking for it to be renamed — so an append or
    /// an edit refreshes the shelf, the questions and the action items and
    /// leaves the heading exactly as it stands. A note that has no heading yet
    /// still gets one; there is nothing there to keep.
    private func refine(immediately: Bool = false, retitles: Bool = false) {
        // Something else is already writing the body a token at a time.
        // Re-reading a half-written page describes a note that never existed,
        // and both of those paths refresh the heading when they land anyway.
        guard !isStreaming, !isDictating else { return }
        refineTask?.cancel()
        let snapshot = draft
        refineTask = Task {
            if !immediately {
                try? await Task.sleep(for: .seconds(1.2))
            }
            guard !Task.isCancelled else { return }

            guard let refinement = await CaptureRefiner.refine(snapshot) else {
                // No key, or the model didn't answer usefully. The heading
                // still has to keep up with the body, so the on-device read
                // takes it — the same one a key-less build has always used.
                if retitles { await MainActor.run { retitleLocally() } }
                return
            }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                // The note may have moved on while the request was out — the
                // person kept typing, started dictating, or reached for the
                // type wheel themselves. A read of an older version of the note
                // is not worth overwriting any of that with.
                guard !isStreaming, !isDictating, !handedOff,
                      draft.summary == snapshot.summary else { return }
                withAnimation(.snappy(duration: 0.2)) {
                    draft = refinement.applied(to: draft, retitling: retitles)
                }
                store.upsert(draft)
                // The re-read is where the question actually gets asked most of
                // the time: it runs on arrival from a recording and again as the
                // note is written into, so a note that becomes a commitment
                // three sentences in still gets offered a reminder.
                offerReminder(refinement.needsReminder, at: refinement.suggestedDueAt)
            }
        }
    }

    // MARK: Asking whether this is really one note

    /// Works out whether the capture that just arrived should be split, folded
    /// into a note that already exists, or (almost always) left alone — and puts
    /// a card on the page if it is one of the first two.
    ///
    /// Guarded the same way `refine` is, and for the same reasons: a note being
    /// dictated into or rewritten is not finished being said, so asking what
    /// shape it should be is premature, and the answer would describe a version
    /// of the note that existed for half a second.
    ///
    /// Nothing here can fail visibly. Every unhappy path — no key, nothing
    /// similar, an unreadable reply, the note changing while the request was
    /// out — ends with no card, which is the same thing the user sees when the
    /// model says "keep". That is deliberate: this is work nobody asked for, so
    /// its worst outcome should be indistinguishable from it having decided
    /// there was nothing to say.
    private func propose() {
        guard !isStreaming, !isDictating else { return }
        proposalTask?.cancel()
        let snapshot = draft
        proposalTask = Task {
            guard let found = await CaptureProposer.propose(for: snapshot, store: store) else {
                return
            }
            guard !Task.isCancelled else { return }

            // Resolved before the card is shown rather than inside it: a merge
            // card that cannot name the note it would merge into is a card
            // asking the user to approve something they cannot see.
            var target: CaptureItem?
            if case let .merge(id, _) = found {
                target = store.items.first { $0.id == id }
                guard target != nil else { return }
            }

            await MainActor.run {
                // The note moved on while the question was out — the person kept
                // typing, or started another section. Same test `refine` uses.
                guard !isStreaming, !isDictating, draft.summary == snapshot.summary else { return }
                proposalTarget = target
                withAnimation(.snappy(duration: 0.28)) { proposal = found }
            }
        }
    }

    /// Hands the accepted proposal up to `RootView`, which owns both the store
    /// and the navigation stack — this screen owns neither, and both a merge and
    /// a split end with it looking at a different note than the one it opened.
    private func accept(_ proposal: CaptureProposal) {
        // Every background write this screen could still make is stopped before
        // the note goes away, and the door is locked behind them. A re-read that
        // has already returned and is waiting on the main actor would otherwise
        // commit a note that no longer exists.
        refineTask?.cancel()
        proposalTask?.cancel()

        // Committed first: the body may hold edits made in the seconds the card
        // was on screen, and both actions read the note from the store.
        store.upsert(draft)
        handedOff = true

        switch proposal {
        case .keep:
            break
        case let .merge(id, _):
            onMerge(draft, id)
        case let .split(_, parts):
            onSplit(draft, parts)
        }
    }

    /// The fallback heading: the first meaningful words of the body, chosen on
    /// device. Not as good as the model's, and instant, which is the trade the
    /// no-key path has always made.
    private func retitleLocally() {
        let heading = TriageEngine.title(forBody: draft.summary, transcript: draft.transcript)
        guard !heading.isEmpty, heading != draft.title else { return }
        withAnimation(.snappy(duration: 0.2)) { draft.title = heading }
    }

    /// The report as it arrives. The title is taken as soon as the model has
    /// closed it, which is well before the body finishes — so the masthead
    /// settles first and then the page fills underneath it, rather than the
    /// heading twitching all the way through.
    private func writeStreamed(title: String?, report: String) {
        if let title, !title.isEmpty, title != draft.title {
            withAnimation(.snappy(duration: 0.2)) { draft.title = title }
        }
        guard let id = streamingPassageID,
              let index = draft.passages.firstIndex(where: { $0.id == id }) else { return }
        draft.passages[index].text = report
    }

    private func restore(_ text: String, in id: UUID) {
        withAnimation(.snappy(duration: 0.24)) {
            streamingPassageID = nil
            if let index = draft.passages.firstIndex(where: { $0.id == id }) {
                draft.passages[index].text = text
            }
        }
    }

    /// The single control under the body, and which of the two jobs it is
    /// doing right now.
    ///
    /// The two used to sit side by side, which meant the page asked you to work
    /// out which version you were reading from the labels of the buttons
    /// offering to leave it. They are one control now, and it alternates:
    ///
    /// - Reading the summary, with a raw record underneath → **See Original**.
    ///   The words as spoken are one tap away and nothing is being replaced.
    /// - Reading the original → **Summarize**. It is the only thing left to do
    ///   from here, and it puts you back on the summary when it lands.
    /// - No summary yet → **Summarize**, whichever version is on screen. A note
    ///   the model has never read has nothing to fall back *to*, so the offer
    ///   is the only one worth making.
    /// - Summary on screen but the note has moved on since it was written →
    ///   **Summarize again**. This is the case the button exists for: you spoke
    ///   another section, or edited a paragraph, and what is above is now a
    ///   reading of a note that no longer exists. The offer comes back on its
    ///   own the moment that becomes true, and the run goes out with the whole
    ///   body in it.
    ///
    /// Nothing at all while the rewrite is running or the mic is open: the
    /// eyebrow already says "writing…", and both states end on their own.
    private enum BodyAction {
        case seeOriginal
        case seeSummary
        case summarize
    }

    private var bodyActionKind: BodyAction? {
        guard !isStreaming, !isDictating else { return nil }
        let hasWords = !draft.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasWords else { return nil }

        if showsOriginal {
            // Back to a summary that exists; make one where it doesn't.
            return draft.summarizedAt == nil ? .summarize : .seeSummary
        }
        // On the summary. A stale one is worth redoing before it is worth
        // checking against the original: the words above are a reading of an
        // older note, and the raw record is a tap further away than the button
        // that fixes that.
        guard !draft.isSummaryStale else { return .summarize }
        // The fallback is worth offering only once the model has actually
        // rewritten something — before that the "summary" *is* the original,
        // and the two views hold the same words — and only on a note that was
        // spoken, since a typed one has no raw record to fall back to.
        return draft.summarizedAt != nil && hasOriginal ? .seeOriginal : .summarize
    }

    /// Tinted only when it is the model's button. Switching which version you
    /// are reading is an ordinary navigation and wears the accent; handing the
    /// note to a model is the one thing on this page that comes back with the
    /// words changed, and it is the one thing that gets the gradient.
    @ViewBuilder
    private var bodyAction: some View {
        if let kind = bodyActionKind {
            Button {
                switch kind {
                case .seeOriginal, .seeSummary:
                    withAnimation(.snappy(duration: 0.2)) { showsOriginal.toggle() }
                case .summarize:
                    // The rewrite lands in the body, so the body is what you
                    // should be looking at when it does.
                    if showsOriginal {
                        withAnimation(.snappy(duration: 0.2)) { showsOriginal = false }
                    }
                    Task { await runAnalysis() }
                }
            } label: {
                Group {
                    switch kind {
                    case .seeOriginal:
                        Text("See Original").foregroundStyle(DSColor.accent)
                    case .seeSummary:
                        Text("See Summary").foregroundStyle(DSColor.accent)
                    case .summarize:
                        Text(summarizeLabel).foregroundStyle(DSColor.intelligenceGradient)
                    }
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }

    /// "Summarize" is an offer; "Summarize again" admits there is already a
    /// summary and this replaces it. After a failure the button says so and
    /// stays where it was, so the retry is the same button in the same place
    /// rather than a new one that appears only when things go wrong.
    private var summarizeLabel: String {
        if analysisFailure != nil { return "Summarize — try again" }
        return draft.summarizedAt == nil ? "Summarize" : "Summarize again"
    }

    // MARK: Formatting

    /// When the capture was first made — `21 Dec`, with the year appended
    /// (`21 Dec 24`) only when it isn't this one.
    ///
    /// Day before month, held there by an explicit format rather than left to
    /// `.dateTime`, which would flip it to `Dec 21` in some regions and not
    /// others. The month name still localizes; only the order is this app's
    /// own convention.
    private static func originLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = sameYear ? "d MMM" : "d MMM yy"
        return formatter.string(from: date)
    }

    /// The eyebrow: how long ago the sitting was, not when it was — `3h ago`,
    /// `3d ago`, `3mo ago`. What a reader wants from a section footer is its
    /// age relative to the rest of the page, and an age says that in two
    /// glyphs where a timestamp asks them to do the subtraction themselves.
    ///
    /// Deliberately one unit, never two: `1d 4h ago` is a measurement, and
    /// this is a label. The coarser the age the vaguer the unit, which is
    /// exactly how far back the reader's memory of the sitting is anyway.
    private static func sectionLabel(for date: Date) -> String {
        let seconds = Date.now.timeIntervalSince(date)
        // Anything inside the last minute — and anything the clock says is
        // ahead of now, which a device time change can do — reads as the
        // present rather than as a negative age.
        guard seconds >= 60 else { return "just now" }

        // Minutes and hours are wall-clock arithmetic; days and up are
        // calendar arithmetic, so that something written last night still
        // reads "1d ago" this morning rather than "14h ago".
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }

        let calendar = Calendar.current
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: .now)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        if days < 30 { return "\(max(days, 1))d ago" }

        let months = calendar.dateComponents([.month], from: from, to: to).month ?? 0
        if months < 12 { return "\(max(months, 1))mo ago" }

        let years = calendar.dateComponents([.year], from: from, to: to).year ?? 0
        return "\(max(years, 1))y ago"
    }

    /// Nine tomorrow morning — the slot a due date most often wants to be, so
    /// switching "Due" on lands somewhere sensible instead of on now.
    private static var defaultSlot: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

#endif
