import Foundation
import Observation
import SwiftData

/// The app's single source of truth for captures: an observable array of value
/// types, backed — when a container is supplied — by SwiftData on disk.
///
/// The array is a mirror, not a cache to be invalidated. It is loaded once at
/// init and updated by the same mutations that write through to the store, so
/// reads are synchronous and allocation-free and the screens never wait on a
/// fetch mid-render. That matters more than it sounds: `visibleItems` is called
/// during layout on every keystroke and every filter tap, and a `@Query` or a
/// computed fetch there would put disk I/O inside the render loop.
///
/// Keeping the mirror in structs is also what lets Editing hold a draft: it
/// copies a `CaptureItem`, edits it freely, and commits with `upsert`. With
/// live SwiftData objects the draft and the list would be the same object and
/// every keystroke would already be saved.
@MainActor
@Observable
public final class CaptureStore {
    public private(set) var items: [CaptureItem]

    /// Nil means memory-only: nothing is written, nothing is read back on the
    /// next launch. That is the mode SwiftUI previews and the macOS `swift
    /// build` host run in, and it has to stay a first-class path rather than a
    /// degraded one — a preview that can't construct a store is a preview
    /// nobody runs.
    private let modelContainer: ModelContainer?

    private var context: ModelContext? { modelContainer?.mainContext }

    /// What every note means, for the "have I said this before?" lookup.
    ///
    /// Owned here rather than built where it is used, because it has to be kept
    /// current by the same mutations that write to disk — a vector store that
    /// anything can write around is a vector store that is quietly wrong.
    private let index = CaptureIndex()

    /// The embedding sweep over notes that don't have a current vector, if one
    /// is running. Held so a second one can't be started on top of it.
    private var backfillTask: Task<Void, Never>?

    /// The persistent store. Loads whatever is on disk; seeds the samples only
    /// into a container that has never been seeded before.
    public init(modelContainer: ModelContainer?) {
        self.modelContainer = modelContainer
        self.items = []
        guard let context else { return }
        seedIfNeeded(in: context)
        self.items = Self.fetchAll(from: context)
        startIndexing(from: context)
    }

    /// Settles which embedding producer this launch uses, loads the vectors that
    /// match it, then sweeps up whatever is left.
    ///
    /// Asynchronous, and nothing waits for it. Hydrating cannot happen until the
    /// producer is known — a vector of the wrong kind is not worth loading — and
    /// asking the OS whether the contextual model is present is not instant. The
    /// alternative would be blocking `init` on it, which would put a model
    /// availability check in front of the app launching.
    private func startIndexing(from context: ModelContext) {
        Task { [weak self] in
            let kind = await CaptureEmbedder.preferredKind()
            guard let self else { return }
            index.adopt(kind)
            hydrateIndex(from: context)
            startBackfill()
        }
    }

    /// The ephemeral store, for previews and for callers that want a specific
    /// fixed list. Nothing here reaches disk — and nothing is embedded either: a
    /// preview that spins up a language model to draw a list is a preview that
    /// takes a second to appear.
    public init(items: [CaptureItem] = CaptureStore.sampleItems) {
        self.modelContainer = nil
        self.items = items
    }

    // MARK: Mutation

    public func upsert(_ item: CaptureItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }

        guard let context else { return }
        if let stored = fetchStored(id: item.id, in: context) {
            stored.apply(item)
        } else {
            context.insert(StoredCapture(from: item))
        }
        save(context, "upsert \(item.id)")

        // After the save, not before, and not awaited. The words are on disk the
        // instant this method returns — the vector is derived and can be
        // recomputed from them forever, so it must never be something the user
        // waits on to have their thought stored.
        reindex(item)
    }

    public func delete(_ item: CaptureItem) {
        items.removeAll { $0.id == item.id }
        index.remove(item.id)

        guard let context else { return }
        guard let stored = fetchStored(id: item.id, in: context) else { return }
        context.delete(stored)
        save(context, "delete \(item.id)")
    }

    public func markDone(_ item: CaptureItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].state = items[index].state == .done ? .active : .done

        guard let context else { return }
        let updated = items[index]
        guard let stored = fetchStored(id: updated.id, in: context) else { return }
        stored.stateRaw = updated.state.rawValue
        save(context, "markDone \(updated.id)")
    }

    // MARK: Persistence

    /// Fetched by id rather than searched in a preloaded array: the predicate
    /// runs in the store, and it is the one lookup that has to agree with the
    /// `#Unique` constraint on `StoredCapture.id` for `upsert` to be an upsert.
    private func fetchStored(id: UUID, in context: ModelContext) -> StoredCapture? {
        var descriptor = FetchDescriptor<StoredCapture>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            print("CaptureStore: fetch by id failed — \(error)")
            return nil
        }
    }

    private static func fetchAll(from context: ModelContext) -> [CaptureItem] {
        let descriptor = FetchDescriptor<StoredCapture>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor).map(\.asValue)
        } catch {
            print("CaptureStore: load failed — \(error)")
            return []
        }
    }

    /// Saves eagerly after every mutation. At single-user, single-device scale
    /// a capture is a few hundred bytes and mutations arrive at human speed, so
    /// batching would trade a real guarantee — nothing is lost if the app is
    /// killed from the multitasking switcher mid-thought — for an unmeasurable
    /// saving. Failures are printed rather than swallowed: a store that has
    /// silently stopped writing is the worst possible failure mode here.
    private func save(_ context: ModelContext, _ what: String) {
        do {
            try context.save()
        } catch {
            print("CaptureStore: save failed after \(what) — \(error)")
        }
    }

    /// Seeds the sample content exactly once in a container's lifetime.
    ///
    /// The condition is the marker row, not emptiness. "Seed when empty" reads
    /// the same on a fresh install and on a store the user has deliberately
    /// cleared out, and re-filling a list somebody just emptied is the kind of
    /// bug that makes an app feel like it isn't listening. Empty-and-unmarked
    /// is a first launch; empty-and-marked is a decision.
    private func seedIfNeeded(in context: ModelContext) {
        let metadata: StoreMetadata
        do {
            var descriptor = FetchDescriptor<StoreMetadata>(
                predicate: #Predicate { $0.key == "captureStore" }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                metadata = existing
            } else {
                metadata = StoreMetadata()
                context.insert(metadata)
            }
        } catch {
            print("CaptureStore: seed check failed — \(error)")
            return
        }

        guard !metadata.didSeed else { return }
        for item in Self.sampleItems {
            context.insert(StoredCapture(from: item))
        }
        metadata.didSeed = true
        save(context, "seed")
    }

    // MARK: The note index

    /// Loads the vectors written on previous launches. Cheap — a few hundred
    /// blobs of a couple of kilobytes each — and it happens before the first
    /// capture can possibly finish recording.
    private func hydrateIndex(from context: ModelContext) {
        let descriptor = FetchDescriptor<StoredCapture>()
        guard let rows = try? context.fetch(descriptor) else { return }
        for row in rows {
            guard
                let data = row.embedding,
                let source = row.embeddedBody,
                let vector = CaptureVector(data: data)
            else { continue }
            index.store(vector, source: source, for: row.id)
        }
    }

    /// Re-embeds one note if the words it was embedded from have changed.
    ///
    /// Detached from the caller's turn: embedding takes a few milliseconds and
    /// runs on every save, which on a note being dictated into means every
    /// sentence. Nothing waits for it, and nothing breaks if it never finishes —
    /// a missing vector means one note is invisible to the similarity search
    /// until the next launch's backfill picks it up.
    private func reindex(_ item: CaptureItem) {
        let source = CaptureIndex.embeddableText(of: item)
        guard !source.isEmpty, !index.isCurrent(item, source: source) else { return }
        Task { [weak self] in
            guard let vector = await CaptureEmbedder.vector(for: source) else { return }
            self?.commit(vector, source: source, for: item.id)
        }
    }

    /// Writes a vector to both halves of the store — the in-memory index the
    /// search reads, and the column that survives a relaunch.
    private func commit(_ vector: CaptureVector, source: String, for id: UUID) {
        // The note may have been deleted while the embedding was being computed.
        // Writing its vector back would put a row in the index with nothing
        // behind it, which the search would then offer as a merge target.
        guard items.contains(where: { $0.id == id }) else { return }
        index.store(vector, source: source, for: id)

        guard let context, let stored = fetchStored(id: id, in: context) else { return }
        stored.embedding = vector.data
        stored.embeddedBody = source
        save(context, "embed \(id)")
    }

    /// Embeds everything that has no current vector — notes from before the
    /// index existed, and notes whose text changed while the app was closed.
    ///
    /// Sequential and unhurried on purpose. This runs at launch behind whatever
    /// the user is doing, and the whole point of it is to be invisible: a
    /// parallel sweep would contend with the capture that is about to start for
    /// the same model.
    private func startBackfill() {
        guard backfillTask == nil else { return }
        backfillTask = Task { [weak self] in
            guard let self else { return }
            for item in index.stale(in: items) {
                guard !Task.isCancelled else { break }
                let source = CaptureIndex.embeddableText(of: item)
                guard !source.isEmpty else { continue }
                guard let vector = await CaptureEmbedder.vector(for: source) else {
                    // No producer on this device could make one, so it will fail
                    // for every other note too. Stopping beats grinding through
                    // the whole store to learn the same thing each time.
                    break
                }
                commit(vector, source: source, for: item.id)
            }
            backfillTask = nil

            // Last, and for next time. If this device hasn't got the better
            // embedding model, ask for it now that the useful work is done —
            // this launch is already committed to the producer it chose, so
            // there is nothing here waiting on the answer. The next launch
            // picks it up and re-embeds everything, because a vector of the
            // old kind reads as stale.
            await CaptureEmbedder.prepareAssets()
        }
    }

    /// The handful of existing notes a new capture might belong to.
    ///
    /// Async because the new note has to be embedded before it can be compared,
    /// and that is the one embedding somebody is waiting on. Everything after it
    /// is arithmetic over memory.
    ///
    /// The fallback matters as much as the search: when no vector can be made —
    /// no ML assets on the device, or a note with no usable words — this hands
    /// back the most recent notes instead of nothing. The model can still spot a
    /// continuation of something captured an hour ago, which is when duplicates
    /// actually happen.
    public func candidates(for item: CaptureItem, limit: Int = 5) async -> [CaptureItem] {
        let source = CaptureIndex.embeddableText(of: item)
        guard !source.isEmpty else { return [] }

        guard let vector = await CaptureEmbedder.vector(for: source) else {
            return recent(excluding: item.id, limit: limit)
        }
        // Free, since it was just computed and the note is about to be searched
        // against everything else anyway.
        commit(vector, source: source, for: item.id)

        let dismissed = Set(items.filter { $0.state == .dismissed }.map(\.id))
        let matches = index.nearest(
            to: vector,
            excluding: dismissed.union([item.id]),
            limit: limit
        )
        return matches.compactMap { match in
            items.first { $0.id == match.id }
        }
    }

    /// The most recently touched notes — the shortlist when there are no vectors
    /// to search. Ordered by when they last grew rather than when they were
    /// made: a note added to yesterday is a likelier continuation than one
    /// created a year ago and never reopened.
    private func recent(excluding id: UUID, limit: Int) -> [CaptureItem] {
        items
            .filter { $0.id != id && $0.state != .dismissed }
            .sorted { $0.lastAddedAt > $1.lastAddedAt }
            .prefix(limit)
            .map { $0 }
    }

    /// Whether a note still exists — checked before a proposal that names one is
    /// shown, since the request it came from was out for a second or two.
    public func contains(_ id: UUID) -> Bool {
        items.contains { $0.id == id }
    }

    // MARK: Reading

    /// Home's list: newest first, optionally narrowed by a type filter and a
    /// search query. Search deliberately spans the transcript too — the plan's
    /// promise is that a raw thought stays findable even if the AI titled it
    /// badly. Home currently passes no query (it has no search field); the
    /// matching stays here because that promise outlives this screen's chrome.
    public func visibleItems(filter: ItemType?, query: String = "") -> [CaptureItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return items
            .filter { $0.state != .dismissed }
            .filter { filter == nil || $0.type == filter }
            .filter {
                trimmed.isEmpty
                    || $0.title.lowercased().contains(trimmed)
                    || $0.summary.lowercased().contains(trimmed)
                    || $0.transcript.lowercased().contains(trimmed)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

}

// MARK: - Sample content

public extension CaptureStore {
    /// Realistic-shaped seed data. Mixed deliberately: quick one-line captures
    /// sit in the same list as long sessions, one item is low-confidence so the
    /// "needs review" flag is visible, and dates span the section boundaries.
    static var sampleItems: [CaptureItem] {
        let now = Date.now
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

        /// Due dates land on a real hour, not on "now plus n days" — the
        /// Schedule timeline places a capture by the hour it's due, so a seed
        /// with only day precision would pile everything onto whatever hour
        /// the app happened to launch at.
        func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let calendar = Calendar.current
            let day = calendar.date(byAdding: .day, value: days, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        return [
            CaptureItem(
                title: "Book the dentist for a cleaning",
                summary: "Call the dental office about the six-month cleaning, ideally a morning slot.",
                transcript: "Remind me to book the dentist for a cleaning, I think I'm overdue, try for a morning slot because afternoons are wrecked this month.",
                type: .task,
                actionItems: [ActionItem(text: "Call the dental office")],
                dueAt: at(0, 9, 30),
                priority: .medium,
                confidence: 0.94,
                followUpQuestions: [FollowUpQuestion(question: "Which office — the one on Bell Street?")],
                createdAt: ago(1.5)
            ),
            // The one capture that has been come back to. Its body is three
            // sittings across a week, which is what the dated sections in
            // Editing exist for — and what a capture looks like once it has
            // been lived with rather than filed.
            CaptureItem(
                title: "Rethinking how onboarding should feel",
                passages: [
                    CapturePassage(
                        text: "A long think about cutting onboarding to a single screen: drop the tour, defer permissions until the first real use, and let the empty state teach instead of a carousel.",
                        createdAt: ago(6 * 24)
                    ),
                    CapturePassage(
                        text: "Came back to this after watching two people install it. Nobody read a word of the tour — both of them tapped straight through it to get to the thing. So the tour isn't underperforming, it's actively in the way.",
                        createdAt: ago(2 * 24 + 3)
                    ),
                    CapturePassage(
                        text: "One more: the permission prompt has to arrive attached to the action that needs it, otherwise it reads as the app asking for something rather than the app doing something.",
                        createdAt: ago(20)
                    )
                ],
                transcript: "Okay so I keep coming back to onboarding. The tour is doing nothing, people skip it. What if the first screen is just the thing itself and we defer every permission prompt until the moment it's actually needed — mic permission when you first hit record, notifications after the first capture lands. And the empty state does the teaching, one line, not a carousel. I want to sketch this properly this week.\n\nCame back to this after watching two people install it. Nobody read a word of the tour, both of them tapped straight through it to get to the thing. So the tour isn't underperforming, it's actively in the way.\n\nOne more, the permission prompt has to arrive attached to the action that needs it, otherwise it reads as the app asking for something rather than the app doing something.",
                type: .idea,
                actionItems: [
                    ActionItem(text: "Sketch the single-screen onboarding"),
                    ActionItem(text: "List every permission prompt and when it's actually needed"),
                    ActionItem(text: "Rewrite the empty state copy", isDone: true)
                ],
                confidence: 0.88,
                followUpQuestions: [
                    FollowUpQuestion(question: "Should this block the next release, or is it a follow-up?")
                ],
                // The day it was first said, not the day it last grew — Home is
                // a record of when you thought of things.
                createdAt: ago(6 * 24)
            ),
            CaptureItem(
                title: "Olive oil, coffee beans, dish soap",
                summary: "Three things for the next grocery run.",
                transcript: "Olive oil, coffee beans, dish soap.",
                type: .shopping,
                actionItems: [
                    ActionItem(text: "Olive oil"),
                    ActionItem(text: "Coffee beans"),
                    ActionItem(text: "Dish soap")
                ],
                dueAt: at(0, 18, 0),
                confidence: 0.97,
                createdAt: ago(9)
            ),
            CaptureItem(
                title: "That thing about the thing on Tuesday",
                summary: "Unclear — the recording trails off before the subject is named.",
                transcript: "Uh, the thing on Tuesday, I need to — hang on — yeah the Tuesday thing, don't forget.",
                type: .task,
                dueAt: nil,
                confidence: 0.31,
                followUpQuestions: [
                    FollowUpQuestion(question: "What's happening on Tuesday?"),
                    FollowUpQuestion(question: "Is this a meeting, an errand, or something else?")
                ],
                createdAt: ago(26)
            ),
            CaptureItem(
                title: "Dinner with Priya, Thursday 7pm",
                summary: "Dinner booked with Priya on Thursday at 7pm, at the place near the station.",
                transcript: "Dinner with Priya Thursday at seven, the place near the station, book a table.",
                type: .event,
                actionItems: [ActionItem(text: "Book a table")],
                dueAt: at(3, 19, 0),
                confidence: 0.91,
                createdAt: ago(34)
            ),
            CaptureItem(
                title: "Learn to actually read a balance sheet",
                summary: "A someday-list item: get properly literate on financial statements rather than skimming them.",
                transcript: "At some point I should actually learn to read a balance sheet properly instead of nodding along.",
                type: .someday,
                confidence: 0.85,
                createdAt: ago(80)
            ),
            CaptureItem(
                title: "Renew the car insurance before it lapses",
                passages: [
                    CapturePassage(
                        text: "The policy renews at the end of the month; compare two quotes before auto-renewing.",
                        createdAt: ago(200)
                    ),
                    CapturePassage(
                        text: "Got one quote back, it's about forty quid cheaper but the excess is higher, so check what the excess actually is before switching on price alone.",
                        createdAt: ago(30)
                    )
                ],
                transcript: "Car insurance renews end of the month, don't just let it auto-renew, get two quotes first.\n\nGot one quote back, it's about forty quid cheaper but the excess is higher, so check what the excess actually is before switching on price alone.",
                type: .task,
                actionItems: [
                    ActionItem(text: "Get two comparison quotes"),
                    ActionItem(text: "Cancel auto-renew if switching")
                ],
                dueAt: at(11, 17, 0),
                priority: .high,
                confidence: 0.93,
                createdAt: ago(200)
            )
        ]
    }
}
