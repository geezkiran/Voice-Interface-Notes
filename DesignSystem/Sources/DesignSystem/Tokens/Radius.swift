import CoreGraphics

/// Corner language: small, consistent radii on rectangles plus two "soft"
/// shapes reserved for the pieces Grok always renders as a capsule — the
/// composer bar and the user's prompt bubble both use `xl`, which at their
/// height resolves visually to a full pill without technically being a
/// `Capsule` (their content can wrap to more than one line, where a true
/// capsule would look wrong).
public enum DSRadius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 20
    /// Composer bar, prompt bubble — deliberately large, not just "rounded."
    public static let xl: CGFloat = 28
    /// Large enough to always resolve to a full pill/capsule at normal control heights.
    public static let pill: CGFloat = 999
}
