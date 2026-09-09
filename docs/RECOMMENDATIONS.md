# Recommendations — noticed, deliberately not done

Follow-up work, ordered by payoff against risk. Items resolved since the first draft are
marked and kept, so the list stays a record rather than a moving target.

## 1. The API keys ship inside the app — unresolved, and the most serious item here

**Payoff: highest. Risk: this is an architecture decision, not a refactor.**

`GROQ_API_KEY` and `DEEPGRAM_API_KEY` are expanded from `Secrets.xcconfig` into
`App/Resources/Info.plist` at build time and read back at runtime by `GroqClient.swift:55`
and `DeepgramTranscriptSource.swift:568`. That means both keys sit in plaintext inside
every copy of the app. Anyone can unzip an `.ipa` and read them, and the usage bills to
you. Shipping to the App Store publishes them to everyone who downloads it.

There is no fix that is only a code move. The three real options:

1. **A backend proxy.** The app calls your server; your server holds the keys and talks to
   Groq and Deepgram. The only option that actually protects the keys, and the only one
   that needs infrastructure that does not exist yet.
2. **Ephemeral keys.** Deepgram supports short-lived keys minted by a server; Groq does
   not, so this is a half-measure that still needs a server.
3. **Bring-your-own-key.** The user pastes their own keys into Settings, stored in the
   Keychain. No server, no exposure, but it makes the app unshippable to a general
   audience — which may be fine, since `docs/PLAN.md` describes a personal tool.

Until one is chosen, do not submit to the App Store.

## 2. There is no test target — add one

**Payoff: very high. Risk: none.** `Package.swift` declares six targets and not one
`.testTarget`; no file matches `*Tests*`. The restructure had exactly one regression gate,
the build.

Start with `Core/`, where the logic is and where nothing needs a simulator: `TriageEngine`
(pure functions), `StreamingAnalysisParser` (parses partial JSON off a live stream — the
most breakable thing in the codebase), `CaptureEmbedder`/`CaptureIndex` (vector maths),
`ScheduleCadence` date arithmetic.

## 3. No shared Xcode scheme is committed

**Payoff: high. Risk: none.** `Capture.xcodeproj/xcshareddata/` is empty, so
`xcodebuild -list` reports zero schemes — the scheme exists only in local `xcuserdata`.
A fresh clone or a CI runner cannot build this project. XcodeGen emits a shared scheme
from one line in `project.yml`.

## 4. Two ways to run the app, installing two different bundle ids

**Payoff: high. Risk: low, but it is a decision.** The Xcode target ships
`com.kiransreminderapp.app`. `Capture/scripts/run-ios-app.sh` builds the
`CapturePreviewIOS` SwiftPM executable and hardcodes `BUNDLE_ID="com.reminderapp.app"` —
still the old prefix, now aligned with nothing. They install as separate apps with separate
SwiftData stores, so "it worked when I ran it" can mean two different things. Pick one, or
have the script read the id from `project.yml`.

## 5. Date formatting is reimplemented in four screens

**Payoff: good. Risk: low.** `HomeView.swift:268-273`, `ScheduleView.swift:316,329-352`,
`EditingView.swift:1249-1294`, `SettingsView.swift:89-90`, `Schedule.swift:83` each roll
their own relative/short date strings, and they do not all agree. One
`Core/Support/DateFormatting.swift` collapses them.

## 6. `EditingView.swift` is 1,300 lines

**Payoff: good. Risk: medium — it is the app's most complex screen.** It drives analysis,
refinement, proposals and editing from one type. The seams are visible: proposal handling
(`CaptureProposer`, `CaptureRefiner`, `ProposalCard`) is one, transcript editing another.

## 7. `CaptureAnalysis.swift` is 990 lines holding five types

**Payoff: good. Risk: low.** Splitting it along the existing type boundaries is mechanical
and would let `StreamingAnalysisParser` be tested alone (see #2). The clearest violation of
the one-primary-type-per-file convention.

## 8. `CaptureStore` is the god object

**Payoff: moderate. Risk: high — everything depends on it.** 500 lines, referenced by 10
files, extended again in `Features/Schedule/Schedule.swift`. It fronts SwiftData, owns the
vector index and the embedder, and answers every screen's queries. Do #2 first.

## 9. Deprecation warnings on iOS 26

**Payoff: low. Risk: none.** Pre-existing and unchanged by the restructure: `Text` `+`
concatenation in `TranscribingView.swift:195,199` and `EditingView.swift:637,641`, and
`UIScreen.main` in `NavigationGestures.swift:84`.

## 10. `ProfileAvatar` is now an orphaned resource

**Payoff: low. Risk: none.** `Avatar.swift` was the only code loading it and now sits in
`_Review/`. The imageset is still compiled into the package's resource bundle and no longer
read. Resolve it with the `_Review/` verdict.

## 11. The repository directory is still called `Reminder App`

**Payoff: cosmetic. Risk: low, but it is outside the project.** Everything inside is now
named `Capture`; the folder holding it is not. Renaming it is a `mv` in Finder plus
reopening the project — not done here, because it changes paths outside the repository.

---

## Resolved

- **~~The package is called `DesignSystem` but contains the whole app~~** — fixed. The
  package is now `Capture/`, the app module is `CaptureKit`, and `DesignSystem` names only
  the design system target.
- **~~No privacy manifest~~** — added at `App/Resources/PrivacyInfo.xcprivacy`.
- **~~`CODE_SIGN_IDENTITY` pinned to a development certificate~~** — removed, automatic
  signing now picks the right identity per action.
- **~~App named `Notes`~~** — renamed to `Capture`.
