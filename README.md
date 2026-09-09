# Notes

A capture-first reminders app for iOS. You talk; it transcribes, works out what you meant,
and files it. Ships as `Notes` (`com.kiransreminderapp.app`), built from the `Reminder`
target.

Requires **iOS 26** — the interface is built on the native Liquid Glass APIs
(`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`), which have no earlier
equivalent.

## Build and run

```bash
cp Secrets.example.xcconfig Secrets.xcconfig    # first time only; empty keys are fine
xcodegen generate                               # regenerates ReminderApp.xcodeproj
xcodebuild -project ReminderApp.xcodeproj -scheme Reminder \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

`Secrets.xcconfig` supplies `GROQ_API_KEY` and `DEEPGRAM_API_KEY`, which reach the app
through `App/Resources/Info.plist`. It is gitignored. With an empty Groq key the app falls
back to heuristics; with an empty Deepgram key transcription is simulated.

`ReminderApp.xcodeproj` is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) — edit the YAML, never the project file.

There is **no test target yet**. See `docs/RECOMMENDATIONS.md`.

There is a second way to launch the app, `DesignSystem/scripts/run-ios-app.sh`, which
builds the `ReminderAppIOS` SwiftPM executable and wraps it in a throwaway bundle. It
installs a *different* bundle id (`com.reminderapp.app`) and is not the shipping path.

## Structure

```
App/                        the Xcode target: @main, Info.plist, app icon
├── ReminderAppApp.swift
└── Resources/
DesignSystem/               one local SPM package, several targets
└── Sources/
    ├── DesignSystem/       the design system library — DS-prefixed components and tokens
    │   ├── Tokens/         colour, type, spacing, radius, appearance
    │   ├── Components/     reusable views and button styles
    │   └── Resources/      Sorts Mill Goudy, logo and avatar assets
    ├── ReminderApp/        the app itself, as a library so it stays previewable
    │   ├── RootView.swift  tab bar, app state, appearance
    │   ├── Features/       Capture · Home · Schedule · Settings
    │   └── Core/           Models · Persistence · Services · Support
    ├── DesignSystemDemo/   component gallery
    ├── DesignSystemPreviewIOS/, DesignSystemPreviewMac/   hosts for the gallery
    └── ReminderAppIOS/     SwiftPM host for the real app
Tools/                      standalone script that draws the app icon
docs/                       PLAN.md and the architecture documents
_Review/                    quarantined, uncompiled — see _Review/REVIEW.md
```

The app target links the `ReminderApp` product; `DesignSystem` comes in transitively.
Nothing depends on anything above it.

## Documents

| File | What it is |
|---|---|
| `docs/PLAN.md` | the product plan: flows, IA, data model |
| `docs/CONVENTIONS.md` | where a new file goes — read this first |
| `docs/ARCHITECTURE.md` | the structure and why each folder exists |
| `docs/ARCHITECTURE_AUDIT.md` | the pre-restructure audit, with reference counts |
| `docs/RECOMMENDATIONS.md` | known problems, deliberately not fixed |
| `_Review/REVIEW.md` | files with no caller, awaiting your verdict |
