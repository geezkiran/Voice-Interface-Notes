import SwiftUI

/// Which ground the app draws on, and where that choice is kept.
///
/// Held here rather than in the screens because the app has several entry
/// points — the shipping app, the Simulator host, the gallery — and every one
/// of them has to apply the same answer at its root. One key, one modifier,
/// read from wherever a scene is built.
///
/// A plain boolean rather than a system/light/dark triple: the palette is a
/// deliberate pair, and the setting that drives it is a switch the user flips
/// when they want the dark one. There is nothing a third "match system" state
/// would express that the switch doesn't already.
public enum DSAppearance {
    /// `@AppStorage` key. Public so a screen can bind a toggle straight to it
    /// without re-declaring the string and drifting from this one.
    public static let storageKey = "darkModeEnabled"
}

public extension View {
    /// Pins the scheme the app's palette is drawn against. Applied once, at a
    /// scene's root — never per screen, which would leave a pushed view
    /// disagreeing with the bar above it.
    func dsAppearance() -> some View {
        modifier(DSAppearanceModifier())
    }
}

public extension View {
    /// The tint every switch in the app wears. Applied to the toggle rather
    /// than to the list around it, because the accent a `Picker` or a button
    /// in the same list should use is the ordinary one — only the switch has
    /// an always-white knob to stay clear of. See `DSColor.controlAccent`.
    func dsSwitchTint() -> some View {
        tint(DSColor.controlAccent)
    }
}

private struct DSAppearanceModifier: ViewModifier {
    @AppStorage(DSAppearance.storageKey) private var isDark = false

    func body(content: Content) -> some View {
        content.preferredColorScheme(isDark ? .dark : .light)
    }
}
