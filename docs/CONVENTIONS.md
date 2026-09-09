# Conventions

Short on purpose. If a rule here is wrong, change the rule.

## Where a new file goes

The app compiles from **two** SPM targets inside `DesignSystem/`, plus a three-file Xcode
target. Which directory a file sits in *is* which module it belongs to — there is no
project file to update.

| What you are adding | Where it goes |
|---|---|
| A screen the user navigates to | `Sources/CaptureKit/Features/<Feature>/` |
| A type only that one feature uses | the same feature folder, beside the screen |
| A type a second feature references | `Sources/CaptureKit/Core/…` — the moment it has two consumers, it is Core |
| A domain type (describes a capture) | `Core/Models/` |
| Anything that reads or writes stored state | `Core/Persistence/` |
| Anything that talks to the network, mic, or disk beyond the store | `Core/Services/` |
| A UIKit bridge SwiftUI can't express | `Core/Support/` |
| A reusable visual component, token, or modifier | `Sources/DesignSystem/Components/` or `/Tokens/` — **and it gets a `DS` prefix** |
| A new user-facing feature | a new `Features/<Name>/` folder |
| Anything else | ask whether it is really Core before inventing a folder |

Two rules that keep this honest:

- **Nothing in `Core/Models/` may import SwiftUI.** Currently true of every file there.
- **No view may import SwiftData.** Screens go through `CaptureStore`. Currently true of
  all six screens and `RootView`.

Both are one `grep` away from being checked, and both are load-bearing — they are the
reason this codebase restructured cleanly.

## Naming

- One primary type per file, and **the file is named after it**: `HomeView.swift` declares
  `HomeView`. Private helper types may share the file; a second public type may not, unless
  it is meaningless alone (`DSVectorShape` beside `DSVectorIcon`).
- Design system types are prefixed `DS`. App types are not.
- Folders are singular where they name a layer (`Core/Persistence`), plural where they hold
  a collection of peers (`Core/Models`, `Components`).

## Access control

- **`Sources/CaptureKit/`** — default to `internal`, i.e. write no modifier. Mark `public`
  only for what `App/CaptureApp.swift` or `CapturePreviewIOS` actually needs, which today
  is `RootView` and the model types its previews touch.
- **`Sources/DesignSystem/`** — `public` is the point; it is a library. Everything a
  consumer needs, including the memberwise init, must be explicitly `public`.
- Never widen access to make a test or a preview compile. Move the file instead.

## Section ordering inside a type

```swift
struct Thing: View {
    // MARK: Input          // let / var passed in by the caller
    // MARK: State          // @State, @Environment, @Namespace
    // MARK: Body           // var body
    // MARK: Subviews       // private @ViewBuilder vars, in the order body uses them
    // MARK: Actions        // private funcs that mutate or call out
    // MARK: Formatting     // private computed strings and helpers
}
```

Existing files vary; match the file you are in rather than reformatting it in passing.

## Tests

There are none yet. When the first one is written it goes in a `.testTarget` in
`Package.swift`, under `Capture/Tests/CaptureKitTests/`, mirroring the source tree
one folder at a time — `Core/Persistence/CaptureStoreTests.swift` for
`Core/Persistence/CaptureStore.swift`. Start with `Core/`; the screens have no view models
to test against.

## Things that are pinned and must not move

`project.yml`, `Secrets.xcconfig`, `App/Resources/Info.plist`, `Capture/scripts/`.
Each is referenced by an absolute or self-relative path that breaks silently.
`Capture.xcodeproj` is **generated** — never edit it; edit `project.yml` and run
`xcodegen generate`.
