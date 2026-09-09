import SwiftUI
#if canImport(CoreText)
import CoreText
#endif

/// Sorts Mill Goudy — the one non-system family in the app, and it has exactly
/// one job: Home's tab titles, where a serif does the work a second font
/// weight can't. Everything else stays on the system font (see `DSFont`).
///
/// The family ships as a single static face (`SortsMillGoudy-Regular`) with no
/// weight axis, so a requested weight is applied as a synthetic (faux) bold on
/// top of that one face rather than by picking a different face.
///
/// Registration is done in code from the package's own resource bundle, not
/// through the app's `UIAppFonts` — the file lives in this package, and an
/// `Info.plist` key in the app target would silently stop working the moment
/// the package is used anywhere else.
public extension DSFont {
    /// The single PostScript name the family ships under. Public because the
    /// UIKit-drawn heading has to build its own `UIFont` from it — SwiftUI's
    /// `Font` can't cross into a `UILabel`.
    static let serifName = "SortsMillGoudy-Regular"

    /// The serif face at a given size and weight. The family has only a
    /// regular face, so anything past `.regular` is synthesized.
    static func serif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        _ = serifIsRegistered
        return .custom(serifName, fixedSize: size).weight(weight)
    }

    /// Registers the face if it isn't already, and reports whether it is
    /// available. Call before asking UIKit for `serifName` by string — a
    /// `UIFont(name:size:)` for an unregistered family silently returns nil.
    @discardableResult
    static func registerSerif() -> Bool { serifIsRegistered }

    /// Tab titles: the serif is optically smaller than the system font at the
    /// same point size (smaller x-height, lighter stems), so it is set a touch
    /// larger to hold the same weight on the page.
    static let serifTabSize: CGFloat = 26

    /// Registered once, lazily, on first use of `serif(size:weight:)`. Process
    /// scope: the face exists for this app only, never installed system-wide.
    private static let serifIsRegistered: Bool = {
        #if canImport(CoreText)
        guard let url = Bundle.module.url(forResource: "SortsMillGoudy-Regular", withExtension: "ttf") else {
            return false
        }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        #else
        return false
        #endif
    }()
}
