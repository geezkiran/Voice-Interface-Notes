# Proposed structure

> **Names have changed since this document was written.** The app was renamed
> from `Notes` to `Capture` afterwards: target `Reminder` → `Capture`, project
> `ReminderApp.xcodeproj` → `Capture.xcodeproj`, package `DesignSystem/` →
> `Capture/`, module `ReminderApp` → `CaptureKit`, `ReminderAppIOS` →
> `CapturePreviewIOS`, `App/ReminderAppApp.swift` → `App/CaptureApp.swift`.
> Paths and names below are left as they were, because this is a record of what
> the project looked like at the time.

Derived from `ARCHITECTURE_AUDIT.md`. **Nothing has been moved.** Every folder below is
justified against files that actually exist, with the audit's reference counts as the
evidence. Open questions are collected in §6 rather than decided silently.

## 0. Two constraints that shape everything

1. **The module boundary is the directory.** `DesignSystem/Sources/<Target>/` decides
   which Swift module a file compiles into. Every move proposed here stays inside one
   `Sources/<Target>/` tree, so no `import` and no access modifier changes. The only
   exception is the repo-root housekeeping in §4, which touches no Swift file.
2. **`project.yml` is the project.** `ReminderApp.xcodeproj/project.pbxproj` is XcodeGen
   output. Where a move affects the Xcode target, the commit edits `project.yml` and
   regenerates.

Because of (1), the proposed tree lives at `DesignSystem/Sources/ReminderApp/`, not at the
repo root — your Phase 0 decision. The `DesignSystem` target's own
`Tokens/` + `Components/` split is already correct and is **not touched**.

## 1. Target tree

```
DesignSystem/Sources/ReminderApp/
├── RootView.swift              # the module's entry view — stays at the root
├── Features/
│   ├── Capture/                # TranscribingView, EditingView, ProposalCard
│   ├── Home/                   # HomeView
│   ├── Schedule/               # ScheduleView, Schedule
│   └── Settings/               # SettingsView
└── Core/
    ├── Models/                 # Item, CaptureAnalysis, CaptureProposal
    ├── Persistence/            # Persistence, CaptureStore, CaptureIndex, CaptureEmbedder
    ├── Services/               # GroqClient, DeepgramTranscriptSource, TranscriptSource,
    │                           #   TranscriptSourceFactory, TriageEngine
    └── Support/                # KeyboardDismiss, NavigationGestures
```

Folders from your baseline shape that are **not** created, and why:

| Not created | Reason |
|---|---|
| `Features/*/ViewModels/` | There is not one view model in the codebase. Every screen holds its own `@State` and talks to `CaptureStore`. An empty tier would be pure ceremony |
| `Features/*/Views/`, `Features/*/Models/` | With one to three files per feature, a sub-tier under each feature nests three deep to hold a single file |
| `Core/Extensions/` | The two files that would qualify (`KeyboardDismiss`, `NavigationGestures`) declare `UIViewRepresentable`/`UIViewControllerRepresentable` as their primary types and only trail a `View` extension. "Extensions" would misname them; they keep the existing name `Support/` |
| `DesignSystem/` (app-level) | Already exists as a separate SPM target, correctly |
| `Resources/` (app-level) | The package's resources are pinned to `DesignSystem/Sources/DesignSystem/Resources/` by `.process("Resources")` in `Package.swift`. The app's are three files in `App/` — see §4 |
| `Supporting/` | Would hold `project.yml` and `Secrets.xcconfig`, both of which are path-pinned to the repo root. See §4 |
| `Tests/` | No test target exists. Two empty folders, which your own "fewer than two files" rule forbids |

## 2. What each folder holds, and what it does not

### `RootView.swift` (target root)
**Holds:** the single view that composes the tab bar, owns app-level state, and applies
appearance. **Does not hold:** anything else — if a second app-level file ever appears,
that is the moment to create `App/`, not before.
*Evidence:* referenced from `App/ReminderAppApp.swift` (the `@main`) and from 4 screens.

### `Features/<Name>/`
**Holds:** views a user navigates to, plus types used by that feature and nothing else.
**Does not hold:** anything a second feature references — that is `Core/` by definition.
The test is mechanical: if `grep -ow <Type>` names files under two different features, it
does not belong to either.

### `Core/Models/`
**Holds:** the domain vocabulary — the types that describe a capture and the parsers that
produce them. **Does not hold:** anything that performs I/O, and nothing that imports
SwiftUI (verified: no file under the old `Model/` imports SwiftUI, and this must stay true).

### `Core/Persistence/`
**Holds:** state that outlives a screen — the SwiftData schema, the store that fronts it,
and the vector index and embedder the store maintains alongside it.
**Does not hold:** views. *Evidence:* `Persistence.swift` and `CaptureStore.swift` are the
only two files in the module importing SwiftData; `CaptureIndex` is referenced only from
`CaptureStore` (×4) and `CaptureProposal` (×1); `CaptureEmbedder` only from `CaptureStore`
(×5); and `CaptureVector` is persisted directly in `Persistence.swift` (×2).

### `Core/Services/`
**Holds:** everything that talks to the outside world — the network client, the microphone
and transcription backends, the factory that picks between them — plus the stateless triage
engine. **Does not hold:** anything holding app state (that is `Persistence/`) or view code.

### `Core/Support/`
**Holds:** UIKit bridges that exist only because SwiftUI lacks the behaviour.
**Does not hold:** anything with domain knowledge. Both files are pure plumbing.

## 3. Old path → new path

All paths relative to `DesignSystem/Sources/ReminderApp/`. Every move is a `git mv` within
one SPM target: **no module change, no import change, no access-modifier change.**

| # | Old | New | Lines |
|---:|---|---|---:|
| 1 | `RootView.swift` | *(unchanged)* | 323 |
| 2 | `Screens/TranscribingView.swift` | `Features/Capture/TranscribingView.swift` | 334 |
| 3 | `Screens/EditingView.swift` | `Features/Capture/EditingView.swift` | 1300 |
| 4 | `Screens/ProposalCard.swift` | `Features/Capture/ProposalCard.swift` | 190 |
| 5 | `Screens/HomeView.swift` | `Features/Home/HomeView.swift` | 282 |
| 6 | `Screens/ScheduleView.swift` | `Features/Schedule/ScheduleView.swift` | 379 |
| 7 | `Model/Schedule.swift` | `Features/Schedule/Schedule.swift` | 137 |
| 8 | `Screens/SettingsView.swift` | `Features/Settings/SettingsView.swift` | 94 |
| 9 | `Model/Item.swift` | `Core/Models/Item.swift` | 342 |
| 10 | `Model/CaptureAnalysis.swift` | `Core/Models/CaptureAnalysis.swift` | 990 |
| 11 | `Model/CaptureProposal.swift` | `Core/Models/CaptureProposal.swift` | 383 |
| 12 | `Model/Persistence.swift` | `Core/Persistence/Persistence.swift` | 369 |
| 13 | `Model/CaptureStore.swift` | `Core/Persistence/CaptureStore.swift` | 500 |
| 14 | `Model/CaptureIndex.swift` | `Core/Persistence/CaptureIndex.swift` | 143 |
| 15 | `Model/CaptureEmbedder.swift` | `Core/Persistence/CaptureEmbedder.swift` | 274 |
| 16 | `Model/GroqClient.swift` | `Core/Services/GroqClient.swift` | 204 |
| 17 | `Model/DeepgramTranscriptSource.swift` | `Core/Services/DeepgramTranscriptSource.swift` | 781 |
| 18 | `Model/TranscriptSource.swift` | `Core/Services/TranscriptSource.swift` | 190 |
| 19 | `Model/TranscriptSourceFactory.swift` | `Core/Services/TranscriptSourceFactory.swift` | 122 |
| 20 | `Model/TriageEngine.swift` | `Core/Services/TriageEngine.swift` | 117 |
| 21 | `Support/KeyboardDismiss.swift` | `Core/Support/KeyboardDismiss.swift` | 117 |
| 22 | `Support/NavigationGestures.swift` | `Core/Support/NavigationGestures.swift` | 157 |

Untouched: all 29 files of the `DesignSystem` target, all 5 files of the non-shipping
targets (`DesignSystemDemo`, both previews, `ReminderAppIOS`), and `Tools/`.

## 4. Repo root

| Old | New | Note |
|---|---|---|
| `App/Info.plist` | `App/Resources/Info.plist` | Needs `project.yml: info.path` updated in the same commit |
| `App/Assets.xcassets/` | `App/Resources/Assets.xcassets/` | `sources: - path: App` already covers subfolders |
| `PLAN.md` | `docs/PLAN.md` | 72 KB spec, zero references anywhere |
| `CF0E8393-…_Original.jpg` | `_Review/` | md5-identical to `ProfileAvatar.jpg` |
| `fabric_icon.png` | `_Review/` | zero references |
| `logo.svg`, `logodown.svg` | `_Review/` | zero references; distinct from `Tools/*.svg` |

Staying exactly where they are, because moving them breaks something concrete:

- `project.yml` — XcodeGen resolves every path in it relative to itself.
- `Secrets.xcconfig` / `Secrets.example.xcconfig` — `configFiles:` pins the root path, and
  the real file is gitignored, so a move silently breaks anyone who already copied it.
- `Tools/`, `DesignSystem/scripts/` — the scripts resolve their own directory and build
  into `$DS_DIR/.build`.
- `.gitignore`, `ReminderApp.xcodeproj`.

## 5. Commit plan

One folder per commit, each verified with

```
xcodebuild -project ReminderApp.xcodeproj -scheme Reminder \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

| # | Commit | Rows |
|---:|---|---|
| 1 | `App/Resources/` + `project.yml` | root table |
| 2 | `docs/PLAN.md` | root table |
| 3 | `Core/Support/` | 21–22 |
| 4 | `Core/Models/` | 9–11 |
| 5 | `Core/Persistence/` | 12–15 |
| 6 | `Core/Services/` | 16–20 |
| 7 | `Features/Capture/` | 2–4 |
| 8 | `Features/Home/` + `Features/Schedule/` + `Features/Settings/` | 5–8 |
| 9 | `_Review/` + `REVIEW.md` | Phase 3 |

Commit 1 is the only one that can break the build, and it is first so that a failure is
unambiguous. Commits 3–8 are pure `git mv` inside one SPM target; SwiftPM recompiles the
same file set regardless of subfolder, so the risk is close to zero and the build after
each is the proof.

## 6. Open questions — I need your call before Phase 2

### Q1. `Features/Home/` and `Features/Settings/` hold one file each

Your baseline shape asks for one folder per user-facing feature; your rule says a folder
holding fewer than two files should not exist. With this file set the two collide.
Options: **(a)** four feature folders as proposed, accepting two single-file folders;
**(b)** a flat `Screens/` for all six views and no `Features/` at all, which obeys the rule
but loses the vertical slice; **(c)** `Features/Capture/` only, everything else flat.

### Q2. `Schedule.swift` — feature-local or Core?

`ScheduleCadence` is referenced only by `ScheduleView` (×5) and the file itself (×3), and
`WeekWindow` by nothing at all, which argues feature-local. But the file also declares
`public extension CaptureStore` — store query helpers, which argues `Core/Persistence/`.
Splitting the file to satisfy both is out of scope. Proposed: `Features/Schedule/`.

### Q3. `CaptureAnalysis.swift` and `CaptureProposal.swift` — Models or Services?

Both are placed in `Core/Models/` because their dominant type names the file. But
`CaptureAnalysis.swift` (990 lines) also contains `CaptureAnalyzer` and `CaptureRefiner`,
which call `GroqClient`, and `CaptureProposal.swift` contains `CaptureProposer`. By the
"performs I/O" rule they belong in `Services/`. Either placement is defensible; splitting
them is not permitted here.

### Q4. `CaptureIndex` + `CaptureEmbedder` under `Persistence/`?

Placed there because the store is their only consumer. The alternative is a
`Core/Retrieval/` folder holding exactly those two files.

### Q5. The nine unused `public` design-system components

`DSAvatar`, `DSGradientText`, `DSThinkingIndicator`, `DSInboxRow`, `DSFlowLayout`,
`DSWheelPicker`, `DSDayStrip`/`DSMeter`, `DSGlassBar`, `WeekWindow`. My recommendation is
to list all of them in `_Review/REVIEW.md` as `unclear` and **move none of them**, because
a design system's public API is meant to have no in-repo caller, and the green-build test
cannot distinguish an unused component from a used one. Say the word if you would rather
see them physically quarantined.
