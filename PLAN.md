# Personal Capture & Reminder App — Master Plan

## Contents
| Section | Contents |
|---|---|
| [User & Problem](#user--problem) | Who this is for, the real problem, why existing tools fail you specifically |
| [Experience Principles](#experience-principles) | The design rules everything else must obey |
| [Core Flows](#core-flows) | Capture, triage, resurfacing, and completion flows, walked through with real scenarios |
| [Feature Spec (MVP / V1 / V2)](#feature-spec-mvp--v1--v2) | Concrete feature list, split by MVP / V1 / V2 |
| [Information Architecture](#information-architecture) | Screens, navigation, item lifecycle/states |
| [System Architecture](#system-architecture) | Client, backend, AI pipeline, and how data flows end to end |
| [Data Model](#data-model) | Entities, fields, relationships |
| [Roadmap](#roadmap) | Phased build plan and what "done" looks like at each phase |
| [Risks & Open Questions](#risks--open-questions) | Things that can break this idea, and decisions only you can make |
| [Sessions: Long-Form Narration, Auto-Titling & Scheduling Suggestions](#sessions-long-form-narration-auto-titling--scheduling-suggestions) | Long-form narration → auto-title/summary (Claude-style) → extracted items → non-hardcoded scheduling suggestions |
| [Calendar (and Other Cross-App) Integration](#calendar-and-other-cross-app-integration) | What calendar data is used, how, and what's deliberately out of scope for now |
| [Tech Stack](#tech-stack) | The concrete stack, one page, plus what's still an open decision |
| [Design System](#design-system) | The Grok-inspired SwiftUI design system — tokens, components, and where the code lives |


### The one-sentence problem
You have a constant stream of things to do, but capturing them today requires
manual typing (slow, effortful, breaks flow) — so most of them stay in your
head, get jumbled together, and get forgotten or remembered too late to act on.

### The one-sentence solution
An app whose entire job is to make **getting a thought out of your head take
under 3 seconds**, and whose **AI does the work of sorting, labeling, and
timing** those thoughts — so review, not entry, is the only thing left for you
to do.

### Why this is a different app, not just another reminder app
Traditional reminder apps (Apple Reminders, Todoist, Google Tasks, etc.) all
assume:
1. You know what the thing is before you open the app.
2. You're willing to type it out.
3. You're willing to categorize it / set a list / set a due date at the
   moment of capture.
4. You will remember to open the app and look at your list.

Every one of those assumptions is exactly where you're failing today. This
plan flips all four:
1. Capture is ambient and voice-first — you don't compose a sentence, you just
   talk or tap.
2. No typing required for 90% of captures.
3. Categorization, due dates, and priority are inferred after the fact by the
   system, not decided by you at capture time.
4. The app pushes relevant items back to you at the right moment (time,
   place, or context), rather than waiting for you to check a list.

### Guiding metaphor
Think of this less as a "to-do list app" and more as **a second short-term
memory with an assistant attached** — a fast, judgment-free inbox for
anything in your head, plus a triage clerk that files it, and an assistant
that taps you on the shoulder at the right moment.

Scope note: this document is planning only — no app code or scaffolding is
included here, per your original request. The one exception is the
[design system](#design-system), which lives as real, buildable Swift
code at [`/DesignSystem`](DesignSystem) since a visual language is easier
to validate in code than in a spec — the app itself still starts from
this document as its spec.

---

## User & Problem

### The user
Single user (you), personal use only. No multi-tenant, no sharing/collab
requirements, no onboarding funnel to design for. This matters a lot — it
means we can optimize purely for daily-use speed and personal quirks instead
of generalizing for a broad audience.

### The real problem, decomposed
You described two distinct failure modes — they need different fixes:

1. **"All I think of doing in a day are mixed up"**
   This is a *capture and organization* problem. Thoughts arrive
   throughout the day in a jumbled, unstructured stream — a task, an idea, an
   errand, a "don't forget to tell X" — all mixed together with no natural
   separation. By the time you'd sit down to sort them, they've already
   blurred together or vanished.

2. **"Brain fails to catch up with these" / traditional apps require manual
   typing which is tiring**
   This is a *friction and resurfacing* problem. Even the things that do get
   captured don't get acted on, because (a) writing them down was effortful
   enough that you often skip it, and (b) even when captured, nothing
   proactively reminds you at a moment you can actually act — so you have to
   remember to check a list, which is the same failure mode you started with.

### Why existing reminder apps fail you specifically
- **Entry cost is too high.** Opening an app, tapping "new", typing a
  sentence, picking a list, picking a date — that's 5+ decisions and 10+
  seconds for a thought that took you half a second to have. Under any kind
  of load (walking, driving, mid-conversation, tired) you skip it.
- **They demand structure up front.** You're asked "which list?" and "when?"
  before you've even fully formed the thought. That's the opposite of how
  thoughts arrive.
- **They're pull, not push, for anything beyond a hard due-time alarm.**
  A list sitting in an app is invisible unless you deliberately go look —
  which requires you to *remember to remember*, the exact thing that's
  broken.
- **No help disentangling mixed thoughts.** If three unrelated things land in
  your head in the same 10 seconds, existing apps store them as three
  isolated, flat rows. There's no "these two are actually the same errand"
  or "this one is a someday-idea, not a today-task" — you're expected to
  know and encode that yourself, at capture time, which is exactly the
  cognitive work you don't have spare capacity for.

### Jobs to be done
Framed as jobs you're "hiring" this app to do:

1. **"When a thought pops into my head, get it out of my head immediately,
   with near-zero effort, without making me decide anything about it."**
2. **"Figure out, without me telling you, what kind of thing this is, when
   it needs to happen, and how urgent it is."**
3. **"Notice when two things I said are actually the same thing or related,
   without me having to organize them myself."**
4. **"Tell me the right things at the right moment — don't make me
   remember to check a list."**
5. **"When I do have a spare moment to review, make that review fast and
   low-guilt — not an intimidating backlog."**

### Non-goals (explicitly out of scope)
- Team/shared task management, delegation, assignees.
- Full project management (Gantt charts, dependencies, subtask trees) —
  unless a lightweight version emerges naturally from clustering.
- Being a calendar replacement — it should complement, not replace, your
  calendar for hard-scheduled events.
- Cross-platform parity beyond what you personally need (e.g. if you're
  iOS + web, Android and desktop-native are not required).

---

## Experience Principles

These are the rules every feature decision gets checked against. If a
proposed feature violates one of these, it's wrong for this app even if it's
a good idea in general.

### 1. Capture is a reflex, not a task
Getting a thought in must be faster than the thought fading. Target: **under
3 seconds from impulse to "it's safely captured."** No required fields, no
mandatory category picker, no keyboard by default.

Practical implications:
- Voice is the primary input, not a nice-to-have.
- Capture must be reachable from outside the app: lock screen, widget, watch,
  share sheet, voice assistant — not "open app, then capture."
- A capture is *never rejected or blocked* by the app (no "please select a
  list before saving").

### 2. Zero-decision entry
At the moment of capture, you should make exactly **one decision: to
capture, or not.** Everything else — category, due date, priority, list — is
inferred after the fact. You can correct the system's guess later, during a
cheap review pass, but you're never blocked by it up front.

### 3. The system organizes; you review
Organizing is reframed from "a thing you do" to "a thing you check." The
app's AI pass does first-draft categorization, date/time extraction, and
duplicate/related-item detection immediately after capture. Your only
remaining job is a fast confirm/correct pass, and even skipping that pass
entirely should leave the app usable.

### 4. Push, don't rely on pull
A list that only shows up when you go looking for it doesn't fix the "brain
fails to catch up" problem — it just moves the forgetting one level up (now
you have to remember to check the list). The app must proactively resurface
things:
- Time-based nudges for anything with a deadline.
- A **daily digest** (not a live badge count) so today's shape is visible
  once, calmly, rather than as a constant nagging number.
- Context-based resurfacing (location, or "you're near a hardware store" /
  "you just opened your laptop at your desk") for anything tagged with a
  place or context rather than a time.

### 5. Trust is the whole game
If you ever suspect the app dropped a thought, you'll go back to just
remembering things in your head — and the app has failed at its one job.
Every capture gets **immediate, unambiguous confirmation** (haptic + visual,
optionally audio), and captures must survive flaky network / being said
while walking into a dead zone (local-first, sync when possible).

### 6. Low-guilt review, not an infinite backlog
Long flat lists create shame and avoidance. Review surfaces should be small,
bounded, and framed positively ("here's what matters today"), with an easy,
frictionless way to defer or dismiss things that turn out not to matter,
rather than letting them silently pile up as visible failure.

### 7. Correctable, not perfect, AI
The AI's categorization/parsing will sometimes be wrong. That's fine as long
as: (a) it's never wrong in a way that *loses* the item, and (b) correcting
it is a single tap/swipe, not a full re-edit. Optimize for "AI's first guess
is directionally useful," not "AI's first guess is always right."

### 8. Respect the user's attention
Notification fatigue defeats principle 4. Prefer fewer, well-timed,
higher-signal interruptions (digest + true deadlines + explicit
context-triggers) over frequent low-value pings. It should be trivially easy
to mute/snooze a whole category of nudges.

---

## Core Flows

### Flow A — Capture (the most important flow in the whole app)

**Trigger points** (any of these must work without fully opening the app):
- Lock screen widget / long-press app icon shortcut → opens straight to a
  mic or blank text field, already recording or ready to type.
- Home screen widget with a single big "+" / mic button.
- Voice assistant integration (e.g. "Hey Siri/Google, add a reminder [via
  AppName]") — works with phone in pocket, hands full, driving.
- Share sheet — share a link, photo, or text snippet from any other app
  straight into the inbox.
- Photo capture — snap a picture of a flyer, whiteboard, product, business
  card; OCR extracts text later, asynchronously.
- (Stretch) Apple Watch / wearable complication for voice capture without
  the phone.

**Steps:**
1. User has a thought.
2. User triggers capture through whichever channel is fastest in the moment
   (voice while walking, tap-and-type while sitting, photo of a poster).
3. Raw input (audio, text, or image) is saved **immediately and locally**,
   before any processing — this is the "safety net" write. A confirmation
   (haptic buzz + subtle sound + brief visual check-mark) fires the instant
   this local save succeeds, independent of network or AI processing.
4. Input is queued for background processing (transcription if audio, OCR if
   image, then AI parsing — see Flow B).
5. User resumes whatever they were doing. No further interaction required.

**Design constraint:** step 3's confirmation must never wait on steps 4/5. A
raw, unparsed, "uncategorized blob" sitting in the inbox is an entirely
acceptable end state — much better than a lost thought.

### Flow B — AI Triage (automatic, invisible by default)

Runs shortly after capture, in the background:

1. **Transcribe** (if voice) / **OCR** (if photo).
2. **Classify type**: task, event, idea/note, shopping-list item, or
   "someday/maybe."
3. **Extract structure**: due date/time if one is implied ("tomorrow",
   "before Friday", "after work"), location if implied ("pick up X from
   [store]"), people mentioned, recurrence if implied ("every Monday").
4. **Relate**: check the recent inbox and active items for likely duplicates
   or related items ("this sounds like the same errand as the thing you
   added yesterday") and offer to merge/link rather than silently
   duplicating or silently merging.
5. **File**: assign to a default list/category and, if a date/time was
   confidently extracted, schedule it; otherwise it lands in an
   "unscheduled / someday" holding area rather than blocking on you.

All of this happens without a notification or interruption — the result is
just waiting, correctly filed, next time you look.

### Flow C — Review (low-guilt, bounded)

Two review surfaces, deliberately small:

1. **Daily digest** (once each morning, or at a time you choose): a short,
   calm summary — "today: 3 things with times, 2 errands near you, 1 new
   idea captured yesterday you haven't looked at." Not a full list dump —
   a *briefing*.
2. **Inbox triage pass** (whenever you choose to do it, no pressure): quick
   swipe-based review of anything the AI filed with low confidence or
   flagged as ambiguous. Each item: confirm the AI's guess (swipe one way),
   correct it (tap to adjust category/date), or dismiss it (swipe the other
   way). Designed to be doable in under a minute for 10+ items.

### Flow D — Resurfacing (push)

- **Time-based**: standard reminder-style notification at/near the due
  time, but bundled/deduped so you don't get 5 separate ones for 5 things
  due "this evening" — one nudge that expands to a short list.
- **Context-based**: geofence or Wi-Fi-network trigger for
  location-tagged items ("near grocery store" → surfaces shopping list
  items tagged for that store), or app-open-context triggers ("you just
  opened your laptop" → surfaces "someday" items tagged as
  computer-related).
- **Digest-based**: the daily digest itself is a resurfacing mechanism for
  anything that doesn't have a hard time/place trigger — ensuring
  undated ideas don't vanish into a black hole.

### Flow E — Completion / Dismissal
- Mark done (swipe/tap) — logged, removed from active surfaces.
- Snooze — reschedule with a lightweight relative picker ("later today",
  "tomorrow", "this weekend") rather than a full date/time picker, since
  most snoozes are relative, not absolute.
- Dismiss/delete — for things captured that turned out not to matter; kept
  briefly in a recoverable trash rather than hard-deleted immediately.

### Flow F — Session (long-form narration / brainstorming)

See [10-sessions-and-scheduling.md](#sessions-long-form-narration-auto-titling--scheduling-suggestions) for the
full detail. In brief: when you talk for longer than a quick one-off
thought — brainstorming, thinking out loud, working through something with
several moving parts — the app treats it differently from Flow A:

1. Full narration is transcribed and kept, same as any capture.
2. Instead of just triage-classifying, an LLM pass generates a short,
   specific **title** (the way a Claude conversation gets auto-titled from
   its content), a brief **summary**, and **extracted action items** (each
   of which then flows through the normal Flow B triage).
3. Each extracted action item gets a rough **time estimate**, and — using
   your actual calendar free/busy data — a **non-hardcoded scheduling
   suggestion** ("looks like ~30 min, you've got room Thursday afternoon or
   Saturday morning") that you can accept or ignore.
4. The same widget trigger used for quick capture can be used here
   too — the backend infers "quick capture" vs. "session" from how much
   you actually said, so there's no separate button/mode to remember.

### Example walkthrough (tying it together)
> While walking to lunch you think, out loud into your phone: "gotta call
> the dentist to reschedule, also don't forget mom's birthday is coming up,
> also we're out of coffee."
>
> - One voice capture, three sentences, said in one breath. It's saved as
>   one raw entry instantly (buzz confirms it).
> - In the background: AI splits it into three items — (1) task "call
>   dentist to reschedule," no date extracted, flagged low-confidence on
>   timing → lands in unscheduled; (2) event/reminder "mom's birthday,"
>   recognized as an annual recurring date pattern → cross-checked against
>   calendar/contacts if available, else asks once for the date during next
>   review; (3) shopping item "coffee" → auto-filed into your standing
>   "Shopping" list, tagged for grocery-store geofence.
> - Later that day, walking past a grocery store, you get a single nudge:
>   "Near a grocery store — pick up: coffee."
> - Next morning's digest mentions "1 task needs a time: call dentist."
> - You never opened the app to do any of this filing yourself.

---

## Feature Spec (MVP / V1 / V2)

Organized by the pipeline stage each feature belongs to. "MVP" = the minimum
that already fixes the core problem; without it the app isn't worth using
day to day. "V1" = makes it genuinely good. "V2" = polish/expansion.

### Capture
| Feature | Phase |
|---|---|
| Quick-add text field, no required fields | MVP |
| Voice capture (record → transcribe) | MVP |
| Home Screen icon / Shortcuts-widget capture entry point (tap → dictate → POST to backend, no native code, in place of a custom native widget) | MVP |
| Local-first save with instant confirmation (haptic/sound) before any AI processing | MVP |
| Share-sheet capture (text/link from other apps) | V1 |
| Native lock/home-screen widget (WidgetKit) — requires a small native extension, deferred until proven necessary | V2 |
| Photo capture + OCR | V1 |
| Multi-item split from one capture ("three things in one breath") | V1 |
| Watch / wearable capture | V2 |
| Ambient/always-on listening capture (opt-in, privacy-gated) | V2 (only if genuinely wanted — see risks doc) |

### AI Triage / Processing
| Feature | Phase |
|---|---|
| Type classification (task / event / idea / shopping / someday) | MVP |
| Due date/time extraction from natural language | MVP |
| Confidence scoring (drives whether item needs review or can auto-file) | MVP |
| Default category/list auto-assignment | MVP |
| Duplicate / related-item detection | V1 |
| Location extraction + tagging | V1 |
| Recurrence pattern detection ("every Monday") | V1 |
| Auto-clustering of related items into a lightweight "project" | V2 |
| Learning your personal patterns over time (e.g. "call dentist" always means weekday mornings) | V2 |
| **Session mode**: long-form narration → auto-generated title + summary + multi-item extraction (Claude-style auto-titling) | V1 |
| Per-action-item time estimate | V1 |
| Calendar-aware, non-hardcoded scheduling suggestions per action item | V1 |
| Relative date resolution against real calendar events ("after work," "before my dentist appt") | V1 |

### Organization / Storage
| Feature | Phase |
|---|---|
| Single unified inbox (all raw + unprocessed captures) | MVP |
| A small set of default lists (Tasks, Shopping, Ideas, Someday) | MVP |
| Manual override of AI's category/date | MVP |
| Custom lists/tags | V1 |
| Lightweight "project" grouping (linked related items) | V1 |
| Search across all items (including raw transcripts) | V1 |
| Archive / history of completed items | V1 |

### Resurfacing / Notifications
| Feature | Phase |
|---|---|
| Standard time-based reminder notification | MVP |
| Daily digest (morning briefing) | MVP |
| Notification bundling (avoid multiple pings for same time window) | V1 |
| Location-based (geofence) resurfacing | V1 |
| Snooze with relative quick-options | MVP |
| Context-based triggers (Wi-Fi network, app-open context) | V2 |
| Per-category notification muting/quiet hours | V1 |

### Review / Triage UI
| Feature | Phase |
|---|---|
| Swipe-based confirm/correct/dismiss triage list | MVP |
| Bounded "needs your attention" queue (not an infinite backlog) | MVP |
| Recoverable trash for dismissed items | V1 |
| Weekly review surface (bigger-picture "someday" review) | V2 |

### Platform / Cross-cutting
| Feature | Phase |
|---|---|
| iOS app (cross-platform framework, App Store distribution) | MVP |
| Offline-first capture, sync when back online | MVP |
| Companion web view for review on desktop | V1 |
| Backup/export of raw data (own your data) | V1 |
| Calendar read (device calendars, via EventKit) | V1 |
| Conflict-aware date suggestions (explicit-time capture collides with existing event) | V2 |
| Calendar write (app creates events on your behalf) | V3 (only after read-only version is trusted) |

---

## Information Architecture

### Screens (mobile app) — exactly three, no tab bar

1. **Home** — the only landing screen. An Apple-Notes-style card grid/list
   of every past capture (quick tasks and longer brainstorm sessions alike),
   newest first: title, one-line summary preview, category tag, date, and a
   due/follow-up badge if one is set. Quick tasks (priority + due today) are
   just cards here too, sorted/filtered in place — not a separate list
   screen. A floating mic button sits on top of this screen at all times and
   is the entry point into Transcribing. Tapping any card opens Editing for
   that item.
2. **Transcribing** — opened by the floating mic button. Full-screen,
   live transcript as you talk (chat-bubble style, à la a Claude
   conversation). A "Done" action ends the recording and hands off straight
   to Editing, pre-filled with the AI's summary, category, extracted action
   items, and any detected date/timeline.
3. **Editing** — the detail/edit screen for one capture ("page"). Shows the
   raw transcript, the AI-generated summary, category, extracted action
   items, any detected date/timeline (editable — this is where a time slot
   gets allotted), an optional follow-up date/time field, and — for quick
   tasks — a priority field. The AI's optional follow-up questions (to fill
   gaps it noticed) also surface here, answerable inline to add more detail
   before saving. This is also where a Home-screen card lands you.

Everything else that used to be its own tab — reviewing low-confidence
items, browsing by list/category, search, calendar/timeline view, settings
— is a filter, sort order, or panel *within* Home or Editing, not a fourth
screen. (Search, if needed, is a search bar at the top of Home; settings can
be a gear icon off Home; a calendar/timeline view, if it earns its keep
later, would be a filtered view of Home's cards by date, not a new tab.)

### Item lifecycle / states

```
captured (raw)
   → processing (transcribing/OCR/parsing)
       → filed (auto, high-confidence)              → active → done/dismissed
       → needs review (low-confidence / ambiguous)   → (user confirms/corrects) → active → done/dismissed
active items can also be: snoozed → active (later), or archived after done
```

Key rule: **"processing" and "needs review" are never dead ends that lose
data** — worst case an item sits as a raw, unfiled card on Home
indefinitely (flagged "needs review"), still fully searchable and visible,
never silently dropped.

### Navigation shape
No bottom tab bar. Home is the default screen; the floating mic button
opens Transcribing; tapping a card opens Editing; back from either returns
to Home. Capture is globally accessible (widget, floating button) — it is
not "a screen you go to," it's an instant reflex from wherever you are.

---

## System Architecture

### High-level shape

```
[Client: mobile app]
   capture (voice/text/photo/share) 
        │
        ▼
   local store (instant write, offline-first)  ──► instant confirmation to user
        │
        ▼ (background sync when online)
[Backend]
   Ingestion API 
        │
        ▼
   Transcription (voice→text) / OCR (photo→text)
        │
        ▼
   AI Parsing & Classification (LLM-based NLU)
        │  - type classification
        │  - date/time & location extraction
        │  - dedup/relation detection against existing items
        │
        ▼
   Structured item written to DB, confidence-scored
        │
        ├─► high confidence → auto-filed, scheduled
        └─► low confidence  → queued into "needs review"
        │
        ▼
   Notification/Resurfacing Engine
        - scheduled time-based pushes
        - geofence-triggered pushes (needs device-side geofence registration)
        - daily digest generation (batch job, once/day)
        │
        ▼
   Push Notification Service → back to client
        │
        ▼
[Client] sync pulls latest state, updates Today/Inbox/Lists views
```

### Client

#### Platform decision (settled)
- **iOS only**, distributed through the **App Store** (not sideloaded/
  TestFlight-forever — a real listing, even if unlisted/private, so it
  updates and installs like any other app).
- **Native — Swift + SwiftUI**, built and shipped with Xcode. This trades
  the cross-platform-framework convenience of React Native/Expo for:
  - Direct, first-class access to every iOS API (EventKit, Speech,
    CoreLocation geofencing, App Intents, WidgetKit, share extensions) with
    no wrapper-package layer, no framework version lag behind new iOS
    releases, and no bridge-related bugs or performance overhead.
  - A native look/feel and performance ceiling that matches Apple's own
    apps out of the box, since the UI *is* SwiftUI rather than a
    JS-rendered approximation of it.
  - Full control over App Store build/release (Xcode + `xcodebuild`/
    Xcode Cloud), rather than depending on a third-party managed build
    service.
  - The tradeoff, made deliberately: no Android door left open (a Swift
    app is iOS-only, full stop — a future Android app would be a separate
    codebase), and app-shell code (navigation, list views, forms) has to be
    hand-written in SwiftUI rather than reused from a JS ecosystem. Given
    this is a personal, iOS-only app, that tradeoff is acceptable in
    exchange for native quality and full API access.
- **Native widgets are now in scope directly**, not worked around. Because
  the app is already a native Xcode project, adding a **WidgetKit**
  extension (home/lock-screen widget) is just adding another target to the
  same project — not a separate bolt-on decision the way it would be for a
  cross-platform app. This plan still starts with the Shortcuts-app widget
  approach below for Phase 1 (it's faster to stand up before the app itself
  exists), but a first-party WidgetKit widget is a natural, low-friction
  Phase-3 upgrade once the app exists, since it's the same Swift codebase,
  not a new discipline.

#### The capture widget, without writing Swift
Your requested UX — tap a widget, it starts listening, you talk, it
captures — is achievable with **zero custom native code**, using Apple's
built-in **Shortcuts** app as the glue:
1. Build a Shortcut, once, no-code, in the Shortcuts app.
2. That Shortcut's steps: **Dictate Text** (Apple's built-in
   speech-to-text action, starts listening immediately when run) →
   **Get Contents of URL** (an HTTP POST straight to your backend's
   Ingestion API, sending the dictated text as the raw capture).
3. Pin that Shortcut to the home screen or lock screen via Apple's own
   **Shortcuts widget** (no widget code required — it's Apple's widget,
   configured to run *your* shortcut) or as a Home Screen icon.
4. Result: tap the widget → phone starts listening immediately → you talk →
   text is transcribed and POSTed to your backend within the same Shortcut
   run, indistinguishable in feel from a native "tap to record" button, and
   requiring nothing beyond a URL your backend exposes.
5. This can be built and tested in about **15–20 minutes** in the
   Shortcuts app once the Ingestion API endpoint exists — it has no
   dependency on the main app's build/release cycle, so it's worth setting
   up early (Phase 1) purely because it's so cheap.

This is a good Phase 1 shortcut *even in a native app* — it can be stood up
before the Xcode project exists at all, purely against the Ingestion API.
Once the native app exists, this plan's Phase 3 upgrade path replaces it
with a first-party **WidgetKit** widget that does the same job without
leaving the app's own binary, and can additionally show richer in-app UI
(e.g. a live transcript) during capture if wanted.

- **Local storage**: on-device database (**SwiftData**, or **Core Data** if
  finer control is needed) as the source of truth for "did my capture
  save," so capture confirmation from inside the app never depends on
  network latency. (Captures coming in via the widget-triggered Shortcut go
  straight to the backend rather than through this local store — see the
  data-flow note in the Sessions doc for why that's an acceptable
  trade-off.)
- **Speech-to-text**: two paths, deliberately kept simple —
  (a) in-app captures use Apple's native **Speech** framework
  (`SFSpeechRecognizer`) for on-device dictation, falling back to a cloud
  transcription API for longer or messier audio; (b) widget-triggered
  captures use Apple's own **Dictate Text** action (or, later, the same
  Speech framework via a WidgetKit-adjacent App Intent), so transcription
  for that path is entirely Apple's, off-device from your backend's
  perspective, and free.
- **Calendar access**: directly via Apple's **EventKit** framework — no
  wrapper package needed, since this is now first-party native code. See
  [11-calendar-integration.md](#calendar-and-other-cross-app-integration) for what this is
  used for.
- **Companion web app (V1)**: a lightweight read/review interface — useful
  for the "sit down and triage" moments where a keyboard and bigger screen
  beat a phone. Since the backend is a normal HTTP API regardless of
  client, this is a fairly small additional frontend, not a second backend.

### Backend
- **Ingestion API**: thin, fast endpoint whose only job is to accept a raw
  capture and durably store it — deliberately decoupled from the AI parsing
  step so parsing failures/latency never risk losing the capture.
- **Transcription/OCR**: either a managed API (fast to integrate, ongoing
  per-use cost) or on-device only if that's sufficient — for a personal app,
  starting with a managed API and optimizing later is reasonable.
- **AI parsing/classification**: an LLM-based pipeline is the natural fit
  here since the task is exactly "understand loosely structured natural
  language and extract structure" — classification, date/time extraction,
  and relation detection are all things a modern LLM does well with a
  focused prompt, without needing custom ML model training for a
  personal-scale app.
- **Scheduler / notification engine**: a background job system for
  time-based triggers (due reminders, daily digest generation at a
  configured time) plus a geofencing approach — geofencing itself is
  typically registered client-side (OS geofence APIs) with the backend just
  supplying which locations/tags to watch for.
- **Database**: a single relational or document store is plenty at personal
  scale — no need for specialized infra. The interesting modeling is in the
  schema (see data model doc), not the storage technology.
- **Sync**: since this is single-user/multi-device (phone + maybe web), a
  straightforward "last write wins with timestamps" sync model is
  sufficient — no need for complex multi-user conflict resolution (CRDTs
  etc.) given there's exactly one editor.

### Why this shape
- **Local-first capture + async backend processing** directly serves
  Experience Principle 5 (trust) — a capture is never lost to a flaky
  network or a slow AI call, because the "it's saved" moment happens purely
  on-device before anything leaves the phone.
- **Decoupling ingestion from parsing** means the AI can be slow, wrong, or
  temporarily down without ever affecting whether a thought gets captured —
  worst case, items just sit as raw unparsed entries a little longer.
- **LLM-based parsing over hand-built NLP rules** is the right call here
  because the input (rambling spoken thoughts, mixed together, said in
  imperfect sentences) is exactly the messy, contextual language modern LLMs
  handle far better than rule-based date-parsers or keyword classifiers.
- **No multi-user complexity anywhere** (auth is just "it's you", sync is
  simple, no permissions model) — keeps the whole system small and
  maintainable for a personal project.

### Cost/complexity control
Since this is for personal use, the biggest architecture risk is over-
building. Start with: one thin backend service, one managed transcription
API, one LLM API call per capture for parsing, and a simple scheduled-job
system for notifications/digests. That's a small, cheap, and fully
sufficient system for single-user scale — resist adding infrastructure
(message queues, microservices, custom ML models) until an actual bottleneck
appears.

---

## Data Model

Conceptual entities and relationships (not a schema/DDL — this is planning,
not implementation).

### Entities

#### Capture (the raw, immutable record)
The append-only source of truth for "what did the user actually say/type."
Never edited, only referenced.
- id
- created_at
- source (voice / text / photo / share-sheet)
- raw_content (text, or reference to stored audio/image file)
- transcript (if voice — the speech-to-text output; kept separate from
  raw audio so audio can be discarded later if desired for storage/privacy)
- processing_status (pending / processing / processed / failed)

#### Item (the structured, working record)
What the user actually sees and interacts with day to day. One Capture can
produce multiple Items (the "three things in one breath" case).
- id
- capture_id (origin reference — always traceable back to raw wording)
- type (task / event / idea / shopping / someday)
- title (short, AI-generated or user-edited summary)
- due_at (nullable — datetime if extracted/set)
- location (nullable — place name/geofence tag if extracted/set)
- recurrence_rule (nullable)
- list_id (which list/category it's filed under)
- confidence_score (how sure the AI was about type/date/etc — drives
  whether it auto-files or lands in "needs review")
- state (needs_review / active / snoozed / done / dismissed)
- related_item_ids (links to other Items the system or user flagged as
  related/duplicate)
- created_at / updated_at / completed_at

#### List
User-facing grouping. Includes the default set (Tasks, Shopping, Ideas,
Someday) plus any custom ones.
- id, name, is_default, color/icon (optional), notification_settings
  (per-list quiet hours / muting)

#### Correction log
Every time the user overrides an AI-made decision (category, date,
dedup suggestion) — kept as a log rather than just overwriting silently.
- id, item_id, field_changed, ai_value, user_value, timestamp

Purpose: (a) builds a visible trust record ("here's what the AI got
right/wrong over time," supporting Principle 5 and 7), and (b) is the raw
material for any future personalization/learning feature (V2) — you don't
need to design the learning system now, just make sure you're capturing the
signal from day one.

#### Session
A long-form narration/brainstorm recording — distinct from Capture because
it carries generated summary fields a quick capture doesn't need. See
[10-sessions-and-scheduling.md](#sessions-long-form-narration-auto-titling--scheduling-suggestions).
- id
- capture_id (the raw full transcript this session is built from)
- title (AI-generated, Claude-conversation-style; user-editable)
- summary (2–4 sentence AI-generated summary)
- item_ids (the action items extracted from this session — same Item
  entity as everywhere else, just originating from a Session instead of a
  single quick Capture)
- processing_status (transcribing / summarizing / ready / failed)
- created_at

#### Item — additional fields for scheduling suggestions
Two fields extend the Item entity from above, populated only when relevant
(mainly for Session-derived items, though nothing prevents a quick-capture
item from getting an estimate too):
- estimated_duration_minutes (nullable — AI's rough guess)
- suggested_slot (nullable — a proposed start/end time, derived from
  calendar free/busy + estimated_duration_minutes; distinct from due_at,
  which is only set once *you* accept a suggestion or set a time yourself)

#### CalendarEvent (read-only reference, not owned data)
Not a table you populate — a conceptual pass-through representing what's
fetched live from the device calendar for a given check (see
[11-calendar-integration.md](#calendar-and-other-cross-app-integration)). Modeled here
only so its shape is explicit:
- start_at / end_at
- title (fetched selectively, only when needed for matching, e.g. "after my
  dentist appointment")
- source_calendar (which on-device calendar it came from — informational)

This is intentionally *not* synced into the backend database wholesale —
it's queried on demand at parse-time or suggestion-time, per the
privacy/simplicity notes in the calendar integration doc.

#### Digest
A generated daily snapshot, stored so "what did today's briefing say" is
reviewable/history, not just a transient push notification.
- id, date, item_ids_included, generated_at, opened_at (nullable)

### Relationships
```
Capture 1 ──< Item          (one capture can yield multiple items)
Capture 1 ──1 Session        (a session's raw transcript is a capture)
Session  1 ──< Item          (a session's extracted action items)
Item     N ──< N Item        (related/duplicate links, self-referential)
List     1 ──< N Item
Item     1 ──< N CorrectionLogEntry
Digest   N ──< N Item        (a digest references, doesn't own, items)
Item     N ──< (0/1) CalendarEvent   (loose match, not a stored FK — resolved live)
```

### Notes on design intent
- **Capture is immutable and always kept.** Even if an Item is deleted or
  merged, the originating Capture (and its raw transcript/photo) stays
  retrievable via search — this is the concrete implementation of "never
  silently lose a thought."
- **Confidence score is a first-class field**, not an afterthought — it's
  what drives the entire "auto-file vs needs-review" branching in Flow B,
  so it needs to be visible/queryable, not buried inside an opaque AI call.
- **Correction log exists from day one** even though personalization/
  learning is a V2 feature — capturing the signal early costs almost
  nothing and means V2 doesn't need a "wait and collect data" phase.

---

## Roadmap

Phased by *value delivered*, not by calendar time — each phase should be
something you can actually start using daily before moving to the next.

### Phase 0 — Prove the core loop, cheaply
Goal: validate that "voice-first capture + AI triage + push resurfacing"
actually fixes your problem, before investing in a full custom app.
- Could be prototyped almost entirely with existing tools (e.g. a voice
  shortcut that appends to a note/sheet + a scheduled script that runs an
  LLM pass over new entries + a scripted daily digest notification) rather
  than a from-scratch app.
- Success check: for one to two weeks, do captured thoughts actually turn
  into completed actions more often than your current habits? Does the
  digest actually get read?
- This phase is explicitly about *learning*, not about building the real
  product — expect to throw the prototype away.

### Phase 1 — MVP app (iOS, native Swift/SwiftUI)
Goal: the minimum real app that already beats your current situation.
- Platform: native iOS app in Swift/SwiftUI, App Store distribution — see
  [06-system-architecture.md](#system-architecture).
- Capture: text quick-add, in-app voice capture.
- **Home Screen/Shortcuts-widget capture entry point** (Dictate Text →
  POST to Ingestion API) — worth building early since it's ~15–20 minutes
  of no-code setup once the Ingestion API exists, and gives you the exact
  "tap, listen, talk" experience you described without waiting for later
  phases.
- Processing: type classification, date/time extraction, confidence
  scoring.
- Organization: unified inbox, default lists, manual override.
- Resurfacing: time-based notifications, daily digest.
- Review: swipe-based inbox triage.
- Explicitly deferred: photo/OCR, geofencing, dedup/clustering, web
  companion, Sessions, calendar integration, native widget.

### Phase 2 — V1: make it actually smart
Goal: the features that make the AI feel like a real assistant rather than
a fancy text field.
- Duplicate/related-item detection.
- Location extraction + geofence-based resurfacing.
- Recurrence detection.
- Notification bundling + per-list quiet hours.
- Photo capture + OCR.
- Share-sheet capture.
- Companion web view for desktop review.
- Search across raw transcripts.
- **Sessions**: long-form narration → auto-generated title + summary +
  multi-item extraction (see
  [10-sessions-and-scheduling.md](#sessions-long-form-narration-auto-titling--scheduling-suggestions)).
- **Calendar read integration**: device free/busy + selective event-title
  matching, powering both smarter relative-date resolution and (paired with
  Sessions) non-hardcoded scheduling suggestions (see
  [11-calendar-integration.md](#calendar-and-other-cross-app-integration)).

### Phase 3 — V2: personalization & polish
Goal: the app adapts to your specific patterns over time.
- Use the correction log to bias future classification (e.g. you always
  recategorize "call X" as high-priority-today → the AI starts doing that
  by default).
- Lightweight auto-clustering of related items into ad hoc "projects."
- Weekly bigger-picture review surface for someday/maybe items.
- Conflict-aware quick capture (flag collisions with existing calendar
  events).
- Native lock/home-screen widget (WidgetKit) — a low-friction addition now
  that the app is already a native Xcode project, worth doing once the
  Shortcuts-based entry point from Phase 1 shows which UX refinements are
  actually wanted.
- Wearable capture.
- Revisit ambient/always-listening capture only if Phases 1–2 show the
  friction is still in *initiating* capture rather than in the act of
  tapping a button — don't build it speculatively (see risks doc).

### Phase 4 — V3: calendar write (only if earned)
- Calendar write (app creates real calendar events from accepted
  scheduling suggestions) — deliberately last, and only after the
  read-only version (Phase 2) has been lived with long enough to trust its
  suggestions. See the caution in
  [11-calendar-integration.md](#calendar-and-other-cross-app-integration).

### What "done" looks like, overall
The measure of success isn't feature completeness — it's this: a week from
now, did fewer things fall through the cracks than before, and did
capturing a thought stop feeling tiring? Everything in this roadmap is in
service of that, and any phase can be re-ordered or cut if it's not moving
that needle.

---

## Risks & Open Questions

### Risks to watch

1. **AI misclassification erodes trust faster than it builds it.**
   If the AI confidently files something wrong (wrong date, wrong list,
   worse — silently merges two unrelated things as "duplicates"), you'll
   start double-checking everything, which reintroduces the exact
   overhead this app exists to remove. Mitigation: bias the confidence
   threshold conservatively — when in doubt, route to "needs review" rather
   than silently auto-filing; never auto-merge duplicates, only suggest.

2. **Notification fatigue.**
   It's tempting to add more triggers (time, place, digest, "needs review"
   badge...) — but every added notification channel erodes the value of the
   others. Mitigation: keep the "one badge, one digest" discipline from the
   IA doc; treat every new notification type as a cost that must earn its
   place.

3. **Over-building before validating the core loop.**
   The full architecture (custom mobile app, backend, LLM pipeline,
   geofencing) is a real project. It's worth deliberately doing Phase 0
   (a scrappy prototype with existing tools) before investing in the real
   build, so the core "voice → AI triage → push" loop is proven on your
   actual daily life first.

4. **Privacy/always-on capture.**
   Ambient/always-listening capture (mentioned as a V2 stretch) has real
   privacy and battery implications, and may not even be the right fix —
   the friction might really be in "opening the app," not in "actively
   speaking a sentence." Treat it as something to revisit only if a widget/
   shortcut/voice-assistant capture still isn't fast enough in practice.

5. **Single point of failure: you.**
   Since this is single-user with no fallback reviewer, if the app itself
   goes down or a sync bug loses data, there's no one else to catch it.
   Mitigation: local-first storage (data lives on your device, not only in
   the cloud) and a straightforward export/backup feature, even in MVP.

6. **Scope creep into full project management.**
   Once clustering/"lightweight projects" exist, there's a natural pull
   toward subtasks, dependencies, Gantt-style views — which is a different,
   heavier product. Keep re-checking against the Non-goals section in the
   problem doc.

### Decisions already made (no longer open)

- **Platform**: iOS only, App Store distribution, built native in Swift/
  SwiftUI. See [06-system-architecture.md](#system-architecture).
- **Capture entry point**: solved via a Shortcuts-app widget (Dictate Text →
  POST to backend), not a custom native extension — keeps the "no Swift"
  preference intact for this specific request.
- **Session auto-titling & scheduling suggestions**: added as a distinct
  mode from quick capture — see
  [10-sessions-and-scheduling.md](#sessions-long-form-narration-auto-titling--scheduling-suggestions).
- **Calendar integration**: read-only to start (device calendars via an
  installed native-module package, not a custom per-provider integration);
  writes deferred to a later, earned phase — see
  [11-calendar-integration.md](#calendar-and-other-cross-app-integration).

### New risk: native-extension creep
Because the app is cross-platform to avoid Swift, there's a temptation
later to reach for "just a small native widget" or "a custom Siri intent"
once you're used to the app — each of those reintroduces exactly the native
code you wanted to avoid, in a small but real way (a separate build target,
Xcode involvement, provisioning). Mitigation: treat the Shortcuts-based
entry points as the real answer, not a stopgap, and only revisit native
extensions if they prove genuinely insufficient in daily use (this is
already reflected as a Phase 3, "only if earned" item in the roadmap).

### Open questions — decisions only you can make

1. **Where should raw voice audio live long-term** — kept forever
   (useful for re-listening / correcting bad transcripts), or discarded
   after transcription to save space/privacy, keeping only the text?
   (Note: widget-triggered captures never involve app-side audio at all —
   Apple's Dictate Text action transcribes before it ever reaches your
   backend — so this question mainly concerns in-app voice capture.)
2. **How much are you willing to spend on ongoing AI/transcription API
   costs** for a personal-scale app? This shapes whether Phase 0's
   prototype uses a paid LLM API from day one or something free/local
   first, and how heavily Sessions (a heavier LLM call than quick capture)
   get used day to day.
3. **Is a companion web app actually valuable to you**, or is this
   strictly a phone-only habit? (Affects whether Phase 2's web view is
   worth building at all.)
4. **How do you want the daily digest delivered** — a push notification,
   an email, a Shortcuts-widget glance, or some combination?
5. **Existing tools you already use** (notes app, task app) — should this
   new app try to integrate with/import from them, or be a clean break?
   (Calendar is already addressed — see decisions above.)

Recommend resolving #1–#2 before committing to Phase 1's architecture,
since they affect cost/complexity early; #3–#5 can be decided later
without much rework.

---

## Sessions: Long-Form Narration, Auto-Titling & Scheduling Suggestions

This is a distinct mode from quick capture (Flow A in
[03-core-flows.md](#core-flows)). Quick capture is "get one thought out
fast." A **Session** is "think out loud for a while, and let the app turn
that into a labeled, summarized, actionable record" — modeled on the way a
Claude conversation gets an automatic, concise title once there's enough
content to know what it's about.

### What triggers a Session vs. a quick Capture
Not a decision you should have to make consciously — the app infers it:
- A single short utterance (a few seconds, one idea) → **Capture** (Flow A).
- Extended narration/brainstorming (you keep talking, multiple related or
  loosely related thoughts, pauses and continues, more than roughly 30–45
  seconds of speech or several distinct sentences) → **Session**.
- The widget-triggered Shortcut can be used for either — the backend
  decides which pipeline to run based on the length/shape of what came in,
  so you don't need a separate trigger for "quick" vs. "brainstorm" mode.

### The flow
1. You tap the widget (or open the app's dedicated "start
   narrating" screen) and talk freely for as long as you want — thinking
   out loud, circling back, going on tangents, the way you'd talk to
   yourself while walking or driving.
2. Full transcript is captured and stored, exactly as said (same
   immutability principle as a Capture's raw record).
3. An LLM pass runs over the full transcript and produces:
   - **A short, concrete title** (like a Claude chat title) — e.g. not
     "Session on 2026-09-06" but something like *"Kitchen reno budget +
     contractor follow-ups"*. Target: glanceable in a list, specific enough
     you know what it was without replaying it, short enough to read in
     under two seconds.
   - **A brief summary** (2–4 sentences) of what was actually discussed/
     thought through — this is the thing you tap into when you see the
     title and think "wait, what was that about again?"
   - **Extracted action items**, run through the same triage pipeline as
     any other Capture (type classification, confidence scoring, etc. —
     see Flow B) — so a 5-minute ramble that contains "and I really need to
     call the contractor" produces a normal, properly-filed task, not just
     a paragraph you have to re-read to extract that from yourself.
   - **A time estimate per action item** — the LLM's best-guess of how long
     the task actually takes (e.g. "call contractor" → ~10 min; "plan out
     the whole kitchen layout" → 1–2 hrs) — used only as an input to
     scheduling suggestions, never shown as a false-precision guarantee.
4. The Session appears in a **Sessions list** (title + date + summary
   preview), with its extracted action items also appearing normally in
   Inbox/Lists like any other item — a Session is a *view onto* a rich
   originating narration, not a separate task system.

### Scheduling suggestions — explicitly not hardcoded
You asked for this correctly: the app should not hardcode "always suggest
Tuesday evening." Instead, it should reason, per action item, from three
inputs, and re-derive a suggestion each time rather than following a fixed
rule:

1. **The estimated duration** of the task (from step 3 above).
2. **Your actual calendar free/busy data** (see
   [11-calendar-integration.md](#calendar-and-other-cross-app-integration)) — genuinely
   open slots of at least that duration, not just "any day."
3. **Loose contextual fit**, inferred by the LLM from the task's nature —
   e.g. a phone call to a business fits better in daytime/business hours;
   an errand fits better near existing "out of the house" calendar events
   or the weekend; deep-thinking/planning work fits better in a longer,
   unbroken free block rather than a 15-minute gap between meetings.

The output is a **suggestion, not a scheduled event** — e.g. "this looks
like it needs about 30 minutes; you've got a free block Thursday 2–4pm or
Saturday morning — want me to hold one?" You either accept (which creates a
real due-time item, or optionally a calendar event — see the calendar doc
for the read-vs-write distinction) or ignore it and the item just stays as
a normal, undated item in your lists.

This keeps the principle from the original plan intact: **the system
proposes, you decide** — it never silently books your time.

### Why this is a separate doc from the core flows
Sessions introduce two things quick Capture doesn't need: a *summarization*
step (distinct from *classification*) and a *scheduling reasoning* step
(distinct from simple date/time *extraction*). Both are heavier LLM calls
than a quick capture's triage pass, which has architectural implications
(see below) and product implications (a Session's processing will
noticeably take longer than a quick capture's — seconds to low tens-of-
seconds rather than near-instant — so the UI should treat "Session is being
summarized" as its own, clearly-communicated background state, not silently
reuse the instant-confirmation pattern from Flow A).

### Architecture note
- The Ingestion API needs a lightweight length/shape check to route input
  to the **quick-capture pipeline** vs. the **session pipeline** — this can
  be as simple as a word-count/duration threshold, refined later if it
  misfires in either direction (a long ramble that's really three unrelated
  quick items should probably still get split, not force-summarized into
  one artificial "session").
- The session-summarization LLM call is a **second, distinct prompt** from
  the quick-capture classification prompt — different task (summarize +
  title + multi-item extraction + duration-estimate) — not a variant of the
  same call.
- Sessions and their extracted Items are linked (a Session "owns" the raw
  transcript; Items reference back to it, the same
  Capture-produces-multiple-Items relationship already in the data model,
  just at session scale) — see the updated
  [07-data-model.md](#data-model).

### Phase placement
This is meaningfully more complex than MVP quick-capture and depends on the
Ingestion API already existing, so it belongs in **Phase 2 (V1)** —
title/summary/extraction can ship before the scheduling-suggestion piece,
which depends on calendar integration also being in place. See
[08-roadmap.md](#roadmap) for the updated phase breakdown.

---

## Calendar (and Other Cross-App) Integration

### Why this exists
Two separate needs pull on calendar data:
1. **Better date/time extraction** (Flow B, quick capture) — resolving
   relative language ("before Friday," "after my meeting with X") requires
   knowing what's actually on your calendar, not just today's date.
2. **Scheduling suggestions** (Sessions doc) — proposing a realistic time
   slot for a task requires knowing your actual free/busy pattern, not a
   generic assumption like "evenings are free."

Both are **read-only** uses to start. Writing events (the app creating
calendar entries on your behalf) is a separate, later capability — kept
distinct because writing to your calendar is a higher-trust, higher-blast-
radius action than reading it (see Principle-driven caution: a wrong
auto-created event is much worse than a wrong suggestion you can ignore).

### What data is fetched
- **Free/busy blocks** for a rolling near-term window (e.g. next 14 days) —
  start/end times only, not necessarily full event details, for anything
  where just knowing "you're busy then" is sufficient (this also happens to
  be the more privacy-conservative option where it's enough).
- **Event titles/details**, more selectively, when they're actually useful
  signal — e.g. resolving "after my meeting with the contractor" requires
  matching against actual event titles, not just busy blocks.
- Read access is via the OS calendar (EventKit, accessed through an
  installed cross-platform package rather than custom Swift — see
  [06-system-architecture.md](#system-architecture)), which means it
  covers **whatever calendars are already on your phone** — iCloud, Google,
  Outlook, etc. — without the app needing separate integrations per
  provider. This is the pragmatic default: one integration point (the
  device's unified calendar), not N separate OAuth flows per calendar
  provider.

### How it's used

#### 1. Smarter date parsing (quick capture)
When the AI parsing step (Flow B) extracts a relative date/time, it
cross-checks against calendar context before finalizing:
- "after work" → look at today's/that day's last calendar event, infer an
  end-of-workday time from your actual pattern rather than a hardcoded
  5pm/6pm guess.
- "before my dentist appointment" → search calendar events matching
  "dentist" and resolve the actual date rather than asking you to specify
  it.
- Ambiguous cases still fall back to "needs review" (per Principle 7 —
  correctable, not perfect) rather than guessing confidently and silently.

#### 2. Scheduling suggestions (Sessions)
As detailed in [10-sessions-and-scheduling.md](#sessions-long-form-narration-auto-titling--scheduling-suggestions):
combine a task's estimated duration with actual free blocks to propose
realistic windows, and use loose contextual fit (business-hours tasks,
errand-shaped tasks, deep-work-shaped tasks) to prefer *which* free block
among several.

#### 3. (Later) Conflict-aware quick capture
If you capture something with an explicit time that collides with an
existing event, flag the conflict at review time rather than silently
double-booking your mental model of the day — this is a small, natural
extension once free/busy data is already flowing in, but not required for
the first calendar-integration pass.

### What this does NOT do (initially)
- **No calendar writes.** Accepting a scheduling suggestion updates the
  item's own due time inside this app; it does not create a calendar event
  unless you later decide you want that (a plausible V2/V3 addition once
  the read-only version has proven useful and trustworthy).
- **No always-on background calendar sync/polling** beyond what's needed
  to serve the two use cases above — fetch on-demand (at parse time, at
  session-summarization time) rather than continuously syncing your whole
  calendar into the backend, both for privacy and simplicity.
- **No cross-calendar merging/dedup logic** — reading "whatever's on the
  device" already unifies providers at the OS level; the app doesn't need
  its own merge logic on top.

### Privacy note
Calendar data is more sensitive than your own captured thoughts — it can
include other people (meeting attendees, event details you didn't type
yourself). Treat calendar reads as **on-device-first where possible**: if a
given check (like "am I free Thursday afternoon") can be answered on-device
without sending calendar contents to the backend/LLM, prefer that. Only
send the minimal necessary context (e.g. "busy 2–3pm Thursday," not full
event details with attendee lists) to any cloud LLM call, unless a specific
feature genuinely needs event titles (per the "after my dentist
appointment" example above) — and even then, prefer sending just the
matched title, not the full event.

### Phase placement
Read-only free/busy + relative-date resolution can land in **Phase 2**,
alongside Sessions, since the two features are designed to need each other.
Calendar writes, if ever pursued, belong in **Phase 3+** and should be
revisited only after the read-only version has been lived with for a while
— see the updated [08-roadmap.md](#roadmap) and the existing
Non-goals note in [01-user-and-problem.md](#user--problem) (this
app complements, not replaces, your calendar).

---

## Tech Stack

Concrete pull-together of the choices scattered across
[06-system-architecture.md](#system-architecture),
[10-sessions-and-scheduling.md](#sessions-long-form-narration-auto-titling--scheduling-suggestions), and
[11-calendar-integration.md](#calendar-and-other-cross-app-integration). Nothing here is
new — this is the "if you had to write it on one page" version. Items
marked (open) still need a decision from you before Phase 1 starts.

### Client (iOS app)
| Layer | Choice | Why |
|---|---|---|
| Framework | **Swift + SwiftUI**, native Xcode project | Full, direct access to every iOS API (EventKit, Speech, CoreLocation, App Intents, WidgetKit) with no wrapper/bridge layer; native performance and look/feel |
| Build/ship | **Xcode + App Store Connect** (optionally **Xcode Cloud** for CI builds/TestFlight) | Standard native release path; no third-party managed build service dependency |
| Local storage | **SwiftData** (Core Data under the hood; drop to raw Core Data if finer control is ever needed) | Source of truth for "did my capture save" independent of network |
| In-app speech-to-text | Apple's **Speech** framework (`SFSpeechRecognizer`), on-device dictation; cloud transcription API as fallback for long/messy audio | Fast + free + offline-capable first, accuracy fallback second |
| Calendar access | Apple **EventKit**, directly | First-party framework — no wrapper package needed |
| Push notifications | **APNs**, directly via `UserNotifications`/`PushKit` | Standard native path; no intermediary push-relay service |
| Widget capture entry point | **Phase 1**: iOS Shortcuts app (Dictate Text → Get Contents of URL) pinned via Apple's Shortcuts widget, zero native code, stood up before the app exists. **Phase 3 upgrade**: a first-party **WidgetKit** widget in the same Xcode project, once the app exists | Shortcuts gets the UX working immediately; the native widget is a natural later upgrade since it's the same native codebase, not a new discipline |
| Native widget (Phase 3, optional) | **WidgetKit** extension target in the same Xcode project | No longer a "separate native detour" — just another target, since the app is already native |
| Companion web app (Phase 2, optional) | Same API, a lightweight web frontend — **(open)**: React/Next.js is the default-reasonable pick if you want one | Reuses the backend as-is; the web companion is a separate, non-native codebase regardless of the mobile client's language |

### Backend
| Layer | Choice | Why |
|---|---|---|
| Ingestion API | Thin HTTP API — **(open)**: Node.js or Python are both fine defaults; pick whichever you're more comfortable maintaining solo | Deliberately simple; not a complexity-critical choice |
| Transcription (server-side path) | A managed speech-to-text API (only needed for in-app long/messy audio; widget-triggered audio is already transcribed by Apple before it arrives) | Avoids building/training your own ASR model |
| OCR (Phase 2, photo capture) | A managed OCR API, or an LLM with vision input | Personal scale — not worth self-hosting |
| AI parsing / classification / summarization | **Groq free tier running Llama 3.3 70B / 3.1 8B (open-weight)** for both the quick-capture triage prompt and the Session prompt (title + summary + multi-item extraction + duration estimates + scheduling reasoning) | Free at personal-scale volume, open-weight, and Groq's inference speed keeps quick-capture triage feeling near-instant. Fallback if quality/rate-limits are ever an issue: **DeepSeek API** (open-weight, fractions of a cent per call) or **Google Gemini free tier** (not open-weight, but free and capable). Longer-term option once on an Apple-Intelligence-capable iPhone (15 Pro+/iOS 18+): on-device Foundation Models for the quick-capture call specifically — zero server cost, fully private, no network round-trip |
| Scheduler / background jobs | A simple scheduled-job mechanism (cron-style) for due-time notifications and once-daily digest generation | No need for a full queueing system at single-user scale |
| Database | A single relational store — **(open)**: Postgres is the default-reasonable pick | Personal scale; schema is what matters, not the engine |
| Push delivery | **APNs**, direct integration (server holds device tokens, sends via APNs HTTP/2 API) | Matches the native client stack; no intermediary push-relay service needed |
| Hosting | **(open)** — any small managed host works (this is intentionally not pinned down; revisit once Phase 1 code exists) | Avoid picking infra before there's a workload to size it against |

### Cross-cutting
| Concern | Choice |
|---|---|
| Auth | None needed beyond "it's you" — no multi-user auth system |
| Sync model | Last-write-wins with timestamps (single editor, phone + optional web) |
| Calendar data flow | Read-only, fetched on demand (not continuously synced into the backend) — device calendars via EventKit, covering iCloud/Google/Outlook already added to the phone |
| Calendar writes | Not built (see roadmap Phase 4 — only if earned) |

### What's deliberately not in the stack (for now)
- No Action Button integration and no native WidgetKit extension in Phase 1 — a Shortcuts-app widget (Dictate Text → POST) covers the capture entry point until Phase 3, even though the native project makes adding a real widget straightforward whenever it's warranted.
- No microservices, message queues, or custom ML model training — one thin backend service + LLM API calls is sufficient at personal scale.
- No per-calendar-provider OAuth integrations — the OS-level unified calendar (via EventKit) covers that.
- No Android build — a Swift/SwiftUI app is iOS-only; an Android app would be a separate codebase built later, not a door this stack keeps open.

### Open decisions before Phase 1 starts
1. Backend language: Node.js vs. Python (or another you're comfortable with).
2. Database: Postgres vs. an alternative — low-stakes, easy to change early.
3. Hosting provider for the backend.
4. Transcription/OCR provider — the LLM choice itself (Groq/Llama, above)
   is settled; transcription and OCR vendors are still open and worth
   revisiting once Phase 0 usage patterns are known (see
   [09-risks-and-open-questions.md](#risks--open-questions)).
   Note transcription is largely a non-issue anyway: widget-triggered
   captures are already transcribed for free by Apple's on-device Dictate
   Text action before anything reaches your backend (see
   [06-system-architecture.md](#system-architecture)) — a paid/managed
   transcription API is only needed as a fallback for in-app voice capture
   on longer or messier audio.

---

## Design System

A SwiftUI design system, closely inspired by **Grok**'s app aesthetic:
near-black canvas, high-contrast type, hairline borders instead of shadows,
pill-shaped controls, a restrained single accent, and multicolor reserved
for exactly one place (the wordmark / a "thinking" moment). It lives as a
standalone, buildable Swift package at [`/DesignSystem`](../DesignSystem),
separate from the future app target so it can be developed and previewed
on its own.

### Where it lives
```
DesignSystem/
  Package.swift
  Sources/
    DesignSystem/           ← the library: tokens + components, no app code
      Tokens/
        Colors.swift        ← DSColor — background/surface/text/border/accent
        DynamicColor.swift  ← light/dark color helper, no asset catalog needed
        Typography.swift    ← DSFont — display/title/body/mono type roles
        Spacing.swift        ← DSSpacing — 4pt-rooted scale (xxs…xxl)
        Radius.swift         ← DSRadius — sm/md/lg + a true pill radius
      Components/
        Buttons.swift        ← DSPrimaryButtonStyle / Secondary / Ghost / Icon
        Card.swift            ← DSCard — hairline-bordered surface, no shadow
        Chip.swift            ← DSChip — pill tag, plain or selected
        CaptureField.swift    ← DSCaptureField — the composer/prompt bar
        ThinkingIndicator.swift ← DSThinkingIndicator — pulsing 3-dot "AI working" state
        GradientText.swift    ← DSGradientText — the one multicolor treatment
        InboxRow.swift        ← DSInboxRow — dense list row for captured items
    DesignSystemDemo/
      GalleryView.swift      ← DSGalleryView — every token/component assembled
                                on one screen, with #Preview for Xcode's canvas
```

### Design language
- **Ground, not chrome.** Dark mode is true black (`#000`), not dark gray —
  matches Grok's OLED-friendly canvas. Elevation is expressed by a single
  hairline border (`DSColor.border`), never a drop shadow.
- **One accent, used sparingly.** `DSColor.accent` drives every primary/
  filled control via an *inverse* fill (white-on-black in dark mode, black-
  on-white in light mode) rather than a branded hue — the interface reads
  as monochrome until something needs to be unmistakably tappable.
- **Multicolor is a special occasion.** `DSColor.brandGradient` /
  `DSGradientText` exist for exactly one job — the wordmark or a rare
  delight moment (e.g. "All caught up") — never for everyday UI.
- **Two shapes only.** Rectangles get a small, consistent radius
  (`DSRadius.sm/md/lg`, always a touch tighter than iOS's own default);
  everything else — buttons, chips, the composer bar — is a true pill
  (`DSRadius.pill`). Nothing in between.
- **Type via weight, not variety.** Everything is the system font; density
  and hierarchy come from size/weight steps (`DSFont.display` →
  `DSFont.footnote`), with one monospaced role (`DSFont.mono`) reserved for
  anything numeric — timestamps, durations, counts — the same "this is
  data" signal Grok's own UI uses mono for.
- **Density over decoration.** Rows (`DSInboxRow`) are left-aligned and
  compact, with hairline dividers supplying the list's structure instead of
  card chrome around every item — a running list reads like Grok's own
  message/result lists, not a stack of cards.

### Using it in the app target
Once the native Xcode app project exists (Phase 1, see
[08-roadmap.md](#roadmap)), add `DesignSystem` as a local Swift
Package dependency (File → Add Package Dependencies → Add Local…, point at
`DesignSystem/`) and `import DesignSystem` wherever a screen is built.
Nothing in the app target should hand-roll a color, font size, or corner
radius that already has a token here — if a screen needs something the
system doesn't yet cover, extend the package first, then consume it, so the
system stays the single source of truth rather than drifting screen by
screen.

### Verifying it builds
The package has no app-target dependency, so it can be sanity-checked from
the command line at any time:
```
cd DesignSystem
swift build                                                  # macOS, fast
xcodebuild -scheme DesignSystem -destination 'generic/platform=iOS Simulator' build
```
Both currently pass clean. Open `DesignSystem/Package.swift` directly in
Xcode to use `DSGalleryView`'s `#Preview`s on the canvas.
