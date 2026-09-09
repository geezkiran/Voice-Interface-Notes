import SwiftUI
import DesignSystem
import DesignSystemDemo

/// A throwaway macOS window host for `DSGalleryView`, so the design system
/// can be screenshotted from the CLI (`swift run DesignSystemPreviewMac`)
/// without needing the iOS Simulator or Xcode's canvas — not shipped as
/// part of the app, just a dev-time viewer.
@main
struct DesignSystemPreviewMacApp: App {
    var body: some Scene {
        WindowGroup {
            DSGalleryView()
                .frame(width: 420, height: 860)
                .dsAppearance()
        }
        .windowResizability(.contentSize)
    }
}
