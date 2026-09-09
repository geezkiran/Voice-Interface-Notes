import SwiftUI
#if os(iOS)
import CaptureKit
#endif

/// iOS Simulator host for the real app — built as a bare executable and
/// wrapped into a throwaway .app bundle by `scripts/run-ios-app.sh`, the
/// same trick `DesignSystemPreviewIOS` uses for the gallery.
#if os(iOS)
@main
struct CapturePreviewIOSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

#else
/// `swift build` on macOS builds every target in the package; this keeps the
/// iOS host linkable there without pretending the app runs on the Mac.
@main
struct CapturePreviewIOSApp {
    static func main() {
        print("CapturePreviewIOS is an iOS Simulator host — run scripts/run-ios-app.sh.")
    }
}
#endif
