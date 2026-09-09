// The app is iOS-only (per the plan: native SwiftUI, App Store, iOS APIs
// throughout). The screens are fenced off so `swift build` on macOS still
// checks the design system and the model layer, which are portable.
#if os(iOS)
import SwiftUI
import DesignSystem

/// The whole navigation shape, in one file, because there isn't much of it:
/// three root destinations behind a floating bottom bar — Home (everything
/// you've said), Schedule (the week those things land in) and Settings — the mic opens
/// Transcribing as a full-screen cover, and Editing is the only push, shared
/// by both roots.
///
/// The bar carries the capture button rather than a third tab: capture is an
/// action, not a place, and it stays reachable from either root.
///
/// Owns the single `CaptureStore`. Public so the thin `CapturePreviewIOS`
/// executable (and `scripts/run-ios-app.sh`) can mount it without the screens
/// themselves having to leak out of this module.
///
/// The color scheme is pinned app-wide from one switch in Settings (see
/// `dsAppearance()`), rather than left to the phone's: the palette is a
/// deliberate light/dark pair, and both grounds are tuned here.
public struct RootView: View {
    /// The root destinations. Editing isn't here — it's a push from Home or
    /// Schedule, not a place you can land in cold.
    enum Tab: Hashable {
        case home, schedule, settings
    }

    /// Built here rather than injected through the environment: the store owns
    /// its container and does its own fetching, so there is nothing for a view
    /// below to read. If the container can't be opened — a corrupt store, a
    /// migration that didn't survive — the app falls back to a memory-only
    /// store rather than refusing to launch. Losing history is bad; being
    /// unable to capture the thought in your head right now is worse, and that
    /// is the one thing this app promises always to work.
    @State private var store: CaptureStore = {
        do {
            return CaptureStore(modelContainer: try CaptureSchema.container())
        } catch {
            print("[CaptureStore] on-disk store unavailable, running in memory: \(error)")
            return CaptureStore(modelContainer: nil)
        }
    }()
    @State private var path: [UUID] = []
    @State private var isTranscribing = false
    @State private var tab: Tab = .home
    /// The capture that just came off a recording and hasn't been rewritten
    /// yet. Editing runs the rewrite itself rather than the store doing it in
    /// the background, because the words have to land *in the open draft* to be
    /// watchable — a background write would go to disk behind a screen holding
    /// its own copy. Opening an old capture from Home leaves this nil, so
    /// re-reading something never silently re-writes it.
    @State private var pendingAnalysisID: UUID?
    /// The blank note that was just made with Home's plus and hasn't been
    /// written in yet — it opens with the keyboard already up. Kept apart from
    /// `pendingAnalysisID` for the same reason that one exists at all: it
    /// belongs to one trip into Editing, so re-opening the note later puts you
    /// on the page reading it rather than in a caret.
    @State private var pendingTypingID: UUID?
    /// The capture that should be asked "is this really one note?" — set only
    /// for something just spoken. Kept apart from `pendingAnalysisID` for the
    /// same reason that one is kept apart from `pendingTypingID`: they answer
    /// different questions about the same arrival, and one of them will
    /// eventually want to be true when the other isn't.
    @State private var pendingProposalID: UUID?
    /// What a back swipe (or the back button) just took off the stack, newest
    /// last, so the right-edge swipe can put it back. Cleared the moment the
    /// user navigates somewhere new — a forward step into a screen you didn't
    /// come from would be a different app's history, not yours.
    @State private var forwardStack: [UUID] = []
    /// Set while a forward swipe is doing the re-push, so the `onChange` below
    /// reads that push as replaying history rather than as new navigation.
    @State private var isRestoringForward = false

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: UUID.self) { id in
                    EditingView(
                        store: store,
                        itemID: id,
                        analyzeOnOpen: id == pendingAnalysisID,
                        typeOnOpen: id == pendingTypingID,
                        proposeOnOpen: id == pendingProposalID,
                        onMerge: applyMerge,
                        onSplit: applySplit
                    )
                }
                // Left edge back, right edge forward. Mounted on the root, not
                // on Editing: the bridge has to outlive the pushes it drives.
                .navigationEdgeGestures(
                    canGoForward: { forwardCandidate != nil },
                    goForward: goForward
                )
        }
        // The pending id belongs to one trip into Editing. Left standing, it
        // still matches the next time that same capture is opened from Home,
        // which is how re-reading a note turned into re-writing it.
        .onChange(of: path) { old, stack in
            if stack.count < old.count {
                forwardStack.append(contentsOf: old.suffix(old.count - stack.count))
            } else if isRestoringForward {
                isRestoringForward = false
            } else {
                forwardStack.removeAll()
            }
            if stack.isEmpty {
                pendingAnalysisID = nil
                pendingProposalID = nil
                // A note made with the plus and then backed straight out of
                // without a word typed into it is not a note. Nothing was said,
                // nothing was written, and leaving it would put a blank row at
                // the top of Home for every mistaken tap.
                if let id = pendingTypingID {
                    pendingTypingID = nil
                    discardIfEmpty(id)
                }
            }
        }
        .fullScreenCover(isPresented: $isTranscribing) {
            TranscribingView(
                onDone: { draft in
                    // Saved first, and to disk, before anything else happens —
                    // before the push, and long before the network. From here
                    // on a crash, a dead connection or a rejected API key can
                    // cost you the rewrite and never the words.
                    store.upsert(draft)
                    isTranscribing = false
                    pendingAnalysisID = draft.id
                    pendingProposalID = draft.id
                    // Land the user straight in Editing on the thing they just
                    // said — the capture is already saved by this point, so
                    // backing out of Editing loses nothing.
                    path.append(draft.id)
                },
                onCancel: { isTranscribing = false }
            )
        }
        .tint(DSColor.accent)
        .dsAppearance()
    }

    /// The screen a forward swipe would put back, or nil when there is none.
    /// A capture deleted while it was off the stack takes its history with it,
    /// so the swipe can't push a screen with nothing behind it.
    private var forwardCandidate: UUID? {
        guard let id = forwardStack.last else { return nil }
        return store.items.contains(where: { $0.id == id }) ? id : nil
    }

    /// Home's plus: a blank note, saved before the screen opens, opened with
    /// the keyboard up. Saved first for the same reason a recording is — the
    /// note has to exist on disk before anything can be written into it — and
    /// dropped again on the way out if nothing ever was.
    ///
    /// It takes the kind from the tab the user is standing on. A note has to be
    /// *some* type, and filing it under the list it was made from is the only
    /// answer that doesn't make it disappear the moment you back out. The
    /// re-read that runs after the first edit is free to disagree.
    private func startTypedNote(kind: ItemType?) {
        var draft = CaptureItem(title: "", type: kind ?? .task)
        draft.openPassage()
        store.upsert(draft)
        pendingTypingID = draft.id
        path.append(draft.id)
    }

    /// Deletes a just-made note that was never written in. Anything with a
    /// character in it — body or heading — is the user's and stays.
    private func discardIfEmpty(_ id: UUID) {
        guard let item = store.items.first(where: { $0.id == id }) else { return }
        let written = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let titled = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard written.isEmpty, titled.isEmpty, item.transcript.isEmpty else { return }
        store.delete(item)
    }

    // MARK: Acting on a proposal

    /// Folds a just-spoken capture into the note it turned out to be another
    /// sitting of, and puts the user on that note.
    ///
    /// This is the operation the data model was already shaped for. A capture's
    /// body is a log of dated sittings and its transcript is a log of dated
    /// recordings (`CaptureItem.passages`, `transcriptSegments`) — so "the same
    /// thing, said again a week later" is not a merge in the destructive sense
    /// at all. Nothing is rewritten, nothing is reconciled, nothing is lost:
    /// both logs simply grow by one entry, dated when it was actually said.
    ///
    /// The new words are dated from the source capture rather than from now,
    /// because the person said them when they said them — and a section stamped
    /// with the moment they happened to tap a button would be the one date on
    /// the page that isn't true.
    private func applyMerge(source: CaptureItem, into targetID: UUID) {
        guard var target = store.items.first(where: { $0.id == targetID }) else { return }

        let addition = source.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !addition.isEmpty {
            target.passages.append(
                CapturePassage(text: addition, createdAt: source.createdAt)
            )
        }
        // Appended sitting by sitting rather than as one flattened blob: the
        // source may itself have been spoken into more than once, and "See
        // Original" is exactly where the difference shows.
        for segment in source.transcriptSegments {
            target.appendTranscript(segment.text, at: segment.createdAt)
        }

        // Anything the source picked up that the target hasn't got. Additive
        // only — a merge must never clear a date or a shelf the user set on the
        // note they are merging *into*.
        if target.dueAt == nil { target.dueAt = source.dueAt }
        let existing = Set(target.actionItems.map { $0.text.lowercased() })
        target.actionItems += source.actionItems.filter {
            !existing.contains($0.text.lowercased())
        }

        store.upsert(target)
        store.delete(source)

        // `isSummaryStale` flips true on its own now that the body has grown
        // past `summarizedBody`, so the target opens offering "Summarize again"
        // with nothing here having to say so.
        pendingAnalysisID = nil
        pendingProposalID = nil
        // Replace rather than push: the note just merged away no longer exists,
        // so leaving it in the stack would put a back button onto a deleted
        // capture.
        path = path.dropLast() + [targetID]
    }

    /// Turns one capture into the several notes it turned out to be, and puts
    /// the user on the first of them.
    ///
    /// Every child keeps the **whole** original recording, not a share of it.
    /// The bodies were written by a model and can be wrong; the transcript is
    /// the record you check them against, and a model that divides it can drop a
    /// sentence or quietly reword one. Copying it whole costs a few kilobytes
    /// and means no spoken word can be lost or misattributed by this operation —
    /// which is the one thing the app promises about the raw record.
    ///
    /// `summarizedAt` is deliberately left nil on the children. The bodies came
    /// from a model, but no model has yet read any child *as a note* — so
    /// Summarize stays on offer, and "See Original" correctly shows the full
    /// recording as the thing the body has not yet been checked against.
    private func applySplit(source: CaptureItem, parts: [CaptureProposal.Part]) {
        guard parts.count >= 2 else { return }

        let children = parts.map { part in
            CaptureItem(
                title: part.title,
                passages: [CapturePassage(text: part.body, createdAt: source.createdAt)],
                transcriptSegments: source.transcriptSegments,
                type: part.type ?? source.type,
                // The parts have not been examined individually, so the parent's
                // confidence is the only honest number to give them — and a
                // low-confidence capture stays flagged after being split rather
                // than laundering itself into two confident ones.
                confidence: source.confidence,
                createdAt: source.createdAt
            )
        }

        for child in children { store.upsert(child) }
        store.delete(source)

        pendingAnalysisID = nil
        pendingProposalID = nil
        guard let first = children.first else { return }
        path = path.dropLast() + [first.id]
    }

    private func goForward() {
        guard let id = forwardCandidate else { return }
        forwardStack.removeLast()
        isRestoringForward = true
        path.append(id)
    }

    /// The bar is an inset on the root content only, so it neither follows the
    /// user into Editing nor covers the last row of either list.
    private var root: some View {
        Group {
            switch tab {
            case .home: HomeView(store: store, onNewNote: startTypedNote)
            case .schedule: ScheduleView(store: store, onCapture: { isTranscribing = true })
            case .settings: SettingsView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            DSTabBar(
                items: [
                    .init(value: Tab.home, icon: .drawn(.home), label: "Home"),
                    .init(
                        value: Tab.schedule,
                        symbol: "calendar",
                        selectedSymbol: "calendar",
                        label: "Schedule"
                    ),
                    .init(
                        value: Tab.settings,
                        symbol: "gearshape",
                        selectedSymbol: "gearshape.fill",
                        label: "Settings"
                    )
                ],
                selection: $tab,
                onCapture: { isTranscribing = true }
            )
        }
    }
}

#Preview {
    RootView()
}

#endif
