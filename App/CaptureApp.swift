import SwiftUI
import CaptureKit

@main
struct CaptureApp: App {
    var body: some Scene {
        WindowGroup {
            // Appearance (light/dark) is applied inside `RootView`, alongside
            // the tint, so every entry point that mounts it agrees.
            RootView()
        }
    }
}
