import CoreGraphics

/// A tight, geometric spacing scale — Grok-style layouts read as dense and
/// deliberate, not airy, so this scale skips generous "marketing site"
/// gaps in favor of a compact 4pt-rooted rhythm.
public enum DSSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
}
