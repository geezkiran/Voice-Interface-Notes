// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [
        // iOS 26 is the floor because the whole visual language is built on the
        // native Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`,
        // `.buttonStyle(.glass)`), which have no pre-26 equivalent worth faking.
        .iOS(.v26),
        .macOS(.v26) // enables `swift build` from the CLI without Xcode; the app itself ships iOS-only
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "DesignSystemDemo", targets: ["DesignSystemDemo"]),
        .library(name: "ReminderApp", targets: ["ReminderApp"]),
        .executable(name: "DesignSystemPreviewMac", targets: ["DesignSystemPreviewMac"]),
        .executable(name: "DesignSystemPreviewIOS", targets: ["DesignSystemPreviewIOS"]),
        .executable(name: "ReminderAppIOS", targets: ["ReminderAppIOS"])
    ],
    targets: [
        // Carries Sorts Mill Goudy (OFL, see Resources/Fonts/OFL.txt) as a bundled
        // resource — registered at runtime by `DSFont.serif`, not via the app
        // target's Info.plist, so the family travels with the package.
        .target(name: "DesignSystem", resources: [.process("Resources")]),
        .target(name: "DesignSystemDemo", dependencies: ["DesignSystem"]),
        // The app itself: the three screens (Home / Transcribing / Editing) plus
        // their in-memory store. Kept as a library so it stays previewable and
        // testable without an Xcode app project existing yet.
        .target(name: "ReminderApp", dependencies: ["DesignSystem"]),
        // macOS-only window host for `DSGalleryView`, so the system can be screenshotted
        // from the CLI without needing the iOS Simulator or Xcode's canvas open.
        .executableTarget(name: "DesignSystemPreviewMac", dependencies: ["DesignSystem", "DesignSystemDemo"]),
        // iOS Simulator host, wrapped into a throwaway .app bundle by scripts/run-ios-preview.sh
        // so the gallery can be seen on an actual device silhouette (e.g. iPhone 17).
        .executableTarget(name: "DesignSystemPreviewIOS", dependencies: ["DesignSystem", "DesignSystemDemo"]),
        // Same trick, but hosting the real app instead of the gallery — see
        // scripts/run-ios-app.sh.
        .executableTarget(name: "ReminderAppIOS", dependencies: ["ReminderApp"])
    ]
)
