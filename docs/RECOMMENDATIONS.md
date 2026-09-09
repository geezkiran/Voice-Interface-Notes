# Recommendations — noticed, deliberately not done

None of this was touched during the restructure. It is follow-up work, ordered by
payoff against risk: the top of the list is high value and low blast radius.

## 1. There is no test target — add one

**Payoff: highest. Risk: none.** The restructure had exactly one regression gate, the
build, because nothing else exists. `Package.swift` declares six targets and not one
`.testTarget`; no file in the repo matches `*Tests*`.

Start with `Core/`, which is where the logic actually is and where nothing needs a
simulator: `TriageEngine` (117 lines, pure functions), `StreamingAnalysisParser` (parses
partial JSON off a stream — the single most breakable thing in the codebase),
`CaptureEmbedder`/`CaptureIndex` (vector maths), `ScheduleCadence` date arithmetic. The
screens can wait; they have no view models to test against.

## 2. No shared Xcode scheme is committed

**Payoff: high. Risk: none.** `ReminderApp.xcodeproj/xcshareddata/` is empty, so
`xcodebuild -list` reports zero schemes — the `Reminder` scheme exists only in the local
`xcuserdata`. Any fresh clone, any CI runner, cannot build. XcodeGen can emit a shared
scheme from `project.yml` (`scheme:` on the target). One line.

## 3. Two ways to run the app, installing two different bundle ids

**Payoff: high. Risk: low, but it is a decision, not a refactor.** The Xcode target
`Reminder` ships `com.kiransreminderapp.app`. `DesignSystem/scripts/run-ios-app.sh` builds
the `ReminderAppIOS` SwiftPM executable and hardcodes `BUNDLE_ID="com.reminderapp.app"`.
They install as *separate apps* with separate SwiftData stores, so "it worked when I ran
it" can mean two different things. Per the single-path rule I did not unify them — pick
one, or at least make the script read the id from `project.yml`.

## 4. Date formatting is reimplemented in four screens

**Payoff: good. Risk: low.** `HomeView.swift:268-273`, `ScheduleView.swift:316,329-352`,
`EditingView.swift:1249-1294`, `SettingsView.swift:89-90`, `Schedule.swift:83` each roll
their own relative/short date strings from `Calendar.current` and `.formatted(...)`. They
do not all agree. One `Core/Support/DateFormatting.swift` would collapse them, at the cost
of a new shared type — which is why it was out of scope here.

## 5. `EditingView.swift` is 1,300 lines

**Payoff: good. Risk: medium — it is the app's most complex screen.** It is the largest
file in the repo by a factor of 1.3, and it drives analysis, refinement, proposals and
editing from one type. The natural seams are already visible: the proposal handling
(`CaptureProposer`, `CaptureRefiner`, `ProposalCard`) is one, the transcript editing
another. Its neighbour `ProposalCard.swift` shows the pattern works.

## 6. `CaptureAnalysis.swift` is 990 lines holding five types

**Payoff: good. Risk: low.** `CaptureAnalysis`, `StreamingAnalysisParser`,
`CaptureAnalyzer`, `CaptureRefinement`, `CaptureRefiner`. Splitting it four ways along the
existing type boundaries is mechanical and would let the parser be tested on its own
(see #1). This is the clearest violation of the one-primary-type-per-file convention.

## 7. `CaptureStore` is the god object

**Payoff: moderate. Risk: high — everything depends on it.** 500 lines, referenced by 10
files, and extended a second time in `Features/Schedule/Schedule.swift`. It fronts
SwiftData, owns the vector index, owns the embedder, and answers every screen's queries.
Nothing is *wrong* with it; it is simply where all the gravity is. Do #1 before touching it.

## 8. The package is called `DesignSystem` but contains the whole app

**Payoff: clarity only. Risk: low, but it churns every import.** `DesignSystem/` holds
six targets, of which one is the design system and one is the entire application
(`Sources/ReminderApp/`, ~5,900 lines). Renaming the package directory to something honest,
or splitting `ReminderApp` into its own package, would say what is true. Deferred because
it is a rename, and renames were out of scope.

## 9. Deprecation warnings on iOS 26

**Payoff: low. Risk: none.** Pre-existing, present at the Phase 0 baseline and unchanged
by the restructure: `Text` `+` concatenation in `TranscribingView.swift:195,199` and
`EditingView.swift:637,641`, and `UIScreen.main` in `NavigationGestures.swift:84`.

## 10. `ProfileAvatar` is now an orphaned resource

**Payoff: low. Risk: none.** `Avatar.swift` was the only code loading it, and that file is
now in `_Review/`. The imageset is still compiled into the package's resource bundle and no
longer read. Resolve it together with the `_Review/` verdict, not before.
