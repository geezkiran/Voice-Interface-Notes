# Quarantine — for review, not deleted

The paths below are the ones these files had when they were quarantined, before
the package was renamed from `DesignSystem/` to `Capture/`. Restoring a component
means putting it back under `Capture/Sources/DesignSystem/Components/`.

Nothing here has been deleted. Each file keeps its original relative path under
`_Review/`, so restoring one is `git mv` back along the same path.

**Why the build passing is not the whole proof.** `_Review/` sits outside both
`DesignSystem/Sources/` (which is how SwiftPM decides target membership) and `App/`
(the Xcode target's source root), so nothing here is compiled — verified by
`** BUILD SUCCEEDED **` with every file below already moved. But for the seven design
system components that is a weak signal: they are `public` API of a *library* target, and
a library's public API is expected to have no in-repo caller. The strong evidence is the
occurrence count in the right-hand column — `grep -ow <Type>` across all 56 Swift files
returning **1** means the name appears at its own declaration and nowhere else, including
`#Preview` blocks and the demo gallery.

Sorted by confidence, highest first.

| File | Original path | Reason flagged | Evidence | Risk if deleted | Recommendation |
|---|---|---|---|---|---|
| `CF0E8393-…_Original.jpg` | repo root | duplicate-of `DesignSystem/Sources/DesignSystem/Resources/Assets.xcassets/ProfileAvatar.imageset/ProfileAvatar.jpg` | md5 of both is `fc2b49f7d9b130de6cd5385f815c84fe`; zero references in any `.swift`, `.sh`, `.yml`, `.json` | None — the catalog copy is the one the app loads | Delete |
| `fabric_icon.png` | repo root | unreferenced | No reference anywhere. The single grep hit for "fabric" is prose inside `CaptureAnalysis.swift`, not a filename | None | Delete unless you recognise it as a source asset |
| `Avatar.swift` (`DSAvatar`) | `DesignSystem/Sources/DesignSystem/Components/` | unreferenced | 1 occurrence, its own declaration at line 4 | Loses the only consumer of the `ProfileAvatar` image asset — see note below | Keep if you want an avatar component later; the file is 24 lines |
| `GradientText.swift` (`DSGradientText`) | `DesignSystem/Sources/DesignSystem/Components/` | unreferenced | 1 occurrence, line 6 | Public API of the design system disappears | Judgement call |
| `ThinkingIndicator.swift` (`DSThinkingIndicator`) | `DesignSystem/Sources/DesignSystem/Components/` | unreferenced | 1 occurrence, line 7 | Same | Judgement call — plausibly wanted by the transcribing screen later |
| `InboxRow.swift` (`DSInboxRow`) | `DesignSystem/Sources/DesignSystem/Components/` | unreferenced, superseded | 1 occurrence, line 8. `DSNoteRow` fills a similar role and *is* used, by `HomeView` | Same | Likely superseded by `DSNoteRow`; confirm before deleting |
| `FlowLayout.swift` (`DSFlowLayout`) | `DesignSystem/Sources/DesignSystem/Components/` | unreferenced | 1 occurrence, line 6 | A custom `Layout` implementation would have to be rewritten | Keep — 71 lines of non-trivial layout maths |
| `WheelPicker.swift` (`DSWheelPicker`) | `DesignSystem/Sources/DesignSystem/Components/` | unreferenced | 1 occurrence, line 13 | 107 lines of generic picker gone | Keep — plausibly intended for the schedule screen |
| `DayStrip.swift` (`DSDayStrip`, `DSMeter`) | `DesignSystem/Sources/DesignSystem/Components/` | unreferenced | 1 occurrence each, lines 12 and 98 | Two public components, 138 lines | Keep — a day strip is an obvious fit for the schedule screen |
| `logo.svg` | repo root | unclear | Zero references. **Not** identical to `Tools/Logo.svg` (md5 `d34b877…` vs `9822774…`) | Could be the newer artwork revision | **Do not delete without comparing against `Tools/Logo.svg` by eye** |
| `logodown.svg` | repo root | unclear | Zero references. Not identical to `Tools/LogoDown.svg` (md5 `9d96926…` vs `3113495…`) | Same | Same |

## Consequences worth knowing before you delete anything

- **`ProfileAvatar` is now an orphaned asset.** `Avatar.swift:9` was the only code loading
  `Image("ProfileAvatar", bundle: .module)`. The imageset is still in the package's
  resource bundle and is still compiled into it — it is just no longer read. It was left
  in place because deleting a resource is not a move.
- **The design system's public API shrank by 8 types.** Nothing in this repo consumed them,
  so no build breaks, but if anything outside this repo ever links `DesignSystem`, this is
  a source-breaking change.
- **Two files were deliberately *not* quarantined.** `DSGlassBar` (inside `Glass.swift`)
  and `WeekWindow` (inside `Schedule.swift`) are equally unreferenced, but their files also
  hold types that *are* used — `DSCaptureButton`, `DSGlassIconButtonStyle`,
  `ScheduleCadence`, and a `CaptureStore` extension. Extracting them would mean splitting a
  file, which is a code change rather than a move.
