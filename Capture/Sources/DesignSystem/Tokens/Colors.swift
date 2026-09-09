import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Color language: **one palette, two grounds**. Every token below is a
/// light/dark pair resolved by the system at draw time, so a screen written
/// against these names is correct in both schemes without ever branching on
/// `colorScheme` itself. The palette is Apple's own system palette rather than
/// a custom brand one, because Liquid Glass reads correctly only when what
/// sits *behind* it is a familiar system ground.
///
/// The rule, stated once and mirrored in dark: a soft neutral canvas (never
/// pure white, never pure black) with surfaces floating on top, separated by a
/// hairline rather than a shadow. Text is near-black on light and near-white
/// on dark, never the pure value. Glass supplies the depth; color stays out of
/// the way.
///
/// Dark is not an inversion. It is the same ladder rebuilt on the other side:
/// on light, surfaces sit *above* the canvas by getting brighter; on dark they
/// sit above it by getting brighter too, which is why `surface` is lighter
/// than `background` in both. The one token that genuinely flips is `accent`
/// — contrast is this app's accent, so it is near-black on light and
/// near-white on dark, and `onAccent` flips with it.
public enum DSColor {
    // MARK: Ground

    /// The base canvas — `systemGroupedBackground` in both schemes, the ground
    /// Apple Notes' own list sits on.
    public static let background = adaptive(
        light: (0.949, 0.949, 0.969),
        dark: (0.0, 0.0, 0.0)
    )

    /// Card/row surfaces — the thing that sits *on* the canvas. White on
    /// light; on dark, the elevated gray Apple uses for grouped rows, because
    /// a pure-black row on a pure-black canvas has no edge at all.
    public static let surface = adaptive(
        light: (1.0, 1.0, 1.0),
        dark: (0.110, 0.110, 0.118)
    )

    /// A step away from `surface` in the direction of the canvas' opposite —
    /// unselected chip fill, inset wells inside a card.
    public static let surfaceRaised = adaptive(
        light: (0.925, 0.925, 0.937),
        dark: (0.172, 0.172, 0.180)
    )

    // MARK: Content

    public static let textPrimary = adaptive(
        light: (0.07, 0.07, 0.07),
        dark: (0.949, 0.949, 0.969)
    )
    public static let textSecondary = adaptive(
        light: (0.443, 0.443, 0.467),
        dark: (0.639, 0.639, 0.663)
    )
    public static let textTertiary = adaptive(
        light: (0.68, 0.68, 0.7),
        dark: (0.463, 0.463, 0.502)
    )

    /// The color that sits *on top of* `accent` (e.g. the mic glyph on the
    /// tinted mic button). Flips with `accent`, so the pair always reads.
    public static let onAccent = adaptive(
        light: (1.0, 1.0, 1.0),
        dark: (0.07, 0.07, 0.07)
    )

    // MARK: Structure

    /// The only "shadow" this system uses — a 1px hairline, not elevation.
    public static let border = adaptive(
        light: (0.894, 0.894, 0.906),
        dark: (0.227, 0.227, 0.235)
    )
    public static let borderSubtle = adaptive(
        light: (0.93, 0.93, 0.94),
        dark: (0.172, 0.172, 0.180)
    )

    // MARK: Accent

    /// Flat near-black on light, flat near-white on dark — every
    /// primary/filled control uses this as an inverse fill, and it is also the
    /// tint poured into the mic button's glass. There is no colored brand hue;
    /// contrast *is* the accent, which is exactly why this token has to flip
    /// with the ground rather than stay put.
    public static let accent = adaptive(
        light: (0.07, 0.07, 0.07),
        dark: (0.949, 0.949, 0.969)
    )

    /// The one saturated color in the app, and it belongs to exactly one
    /// control: the floating capture button. Notes' own yellow, poured into
    /// glass rather than painted flat. Nudged brighter on dark, where the same
    /// yellow over a black ground reads muddier than it does over gray.
    public static let captureTint = adaptive(
        light: (1.0, 0.8, 0.0),
        dark: (1.0, 0.839, 0.039)
    )

    /// The fill of a switched-*on* system control — a toggle's track, and
    /// anything else the platform paints under a white knob it won't let us
    /// recolor.
    ///
    /// Not `accent`, and this is the one place the two have to part company.
    /// `accent` inverts with the ground, which is right everywhere it is ink
    /// or a fill we draw ourselves — but under an always-white knob it turns
    /// an "on" switch into a white pill on white. So dark gets a mid gray
    /// instead: bright enough to read as on against the off track, dark enough
    /// that the knob still reads against it, which is the same balance the
    /// system's own colored track strikes.
    public static let controlAccent = adaptive(
        light: (0.07, 0.07, 0.07),
        dark: (0.541, 0.541, 0.573)
    )

    /// The ink drawn *on* `captureTint`, and the one token here that does not
    /// change between schemes. The disc under it is yellow in both, so the
    /// glyph's contrast is a question about the yellow, not about the ground:
    /// letting this follow `textPrimary` would put a near-white glyph on a
    /// light tint the moment the app went dark.
    public static let onCaptureTint = Color(red: 0.07, green: 0.07, blue: 0.07)

    // MARK: Semantic (kept minimal — used only where meaning must be unambiguous)

    public static let success = adaptive(
        light: (0.16, 0.6, 0.32),
        dark: (0.188, 0.82, 0.345)
    )
    public static let warning = adaptive(
        light: (0.75, 0.5, 0.05),
        dark: (1.0, 0.839, 0.039)
    )
    public static let danger = adaptive(
        light: (0.75, 0.15, 0.15),
        dark: (1.0, 0.271, 0.227)
    )

    /// The one place multicolor is allowed: a wordmark or a rare delight
    /// moment — never everyday UI, which stays strictly monochrome. The same
    /// three hues in both schemes; they were picked to sit on either ground.
    public static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.42, blue: 0.35),
            Color(red: 0.95, green: 0.55, blue: 0.22),
            Color(red: 0.55, green: 0.38, blue: 0.98)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// The mark of "the model did this" — pink into orange, the family of hues
    /// Apple Intelligence uses for the same job. Reserved for the controls that
    /// hand work to the model (today: Summarize), so a tinted word on the page
    /// always means the same thing. Everything else stays monochrome.
    ///
    /// Deliberately desaturated off the pure hues: this sits at 14pt in a
    /// column of near-black body text, where a full-chroma pink reads as a
    /// warning rather than as a quiet offer. Muted, it stays legibly tinted at
    /// text size without pulling the eye off the note.
    public static let intelligenceGradient = LinearGradient(
        colors: [
            Color(red: 0.83, green: 0.40, blue: 0.56),
            Color(red: 0.87, green: 0.48, blue: 0.44),
            Color(red: 0.87, green: 0.57, blue: 0.33)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    // MARK: Resolution

    /// One token, two literals, resolved by the platform at draw time.
    ///
    /// Deliberately *not* `Color(light:dark:)`-by-`@Environment` — a token is
    /// read from static context all over this package (inside `UIColor`
    /// bridges, inside shape styles built outside a view's body), where there
    /// is no environment to read a scheme from. A dynamic platform color
    /// carries its own answer wherever it is drawn, which is the only version
    /// of this that is correct everywhere it is used.
    private static func adaptive(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #elseif canImport(AppKit)
        return Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        return Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }
}
