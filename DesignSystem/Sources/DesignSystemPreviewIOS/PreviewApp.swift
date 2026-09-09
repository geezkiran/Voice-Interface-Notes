import SwiftUI
import DesignSystem
import DesignSystemDemo

/// iOS Simulator host for `DSGalleryView` — built as a bare executable and
/// wrapped into a throwaway .app bundle by `scripts/run-ios-preview.sh`,
/// so the gallery can be viewed on a real device silhouette (e.g. iPhone
/// 17) without a full Xcode project existing yet.
@main
struct DesignSystemPreviewIOSApp: App {
    var body: some Scene {
        WindowGroup {
            DSGalleryView()
                .dsAppearance()
        }
    }
}
