import SwiftUI

/// The primary action: inverse fill (black-on-white in light mode,
/// white-on-black in dark mode), pill-shaped, no shadow — the highest
/// possible contrast for the one thing on screen you most want tapped.
public struct DSPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.bodyEmphasis)
            .foregroundStyle(DSColor.onAccent)
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.sm)
            .frame(minHeight: 48)
            .background(DSColor.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary action: outline only, no fill — sits quietly next to a
/// primary button without competing for attention.
public struct DSSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.bodyEmphasis)
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.sm)
            .frame(minHeight: 48)
            .background(DSColor.surface, in: Capsule())
            .overlay(
                Capsule().strokeBorder(DSColor.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Tertiary action: text only — for the lowest-emphasis affordance (e.g.
/// "Dismiss", "Not now") that still needs to be tappable.
public struct DSGhostButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.bodyEmphasis)
            .foregroundStyle(DSColor.textSecondary)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A circular icon button. Default is a floating white circle with a
/// hairline border (the top-bar hamburger/compose icons); `isProminent`
/// swaps to the solid black fill used for the composer's send/stop button.
public struct DSIconButtonStyle: ButtonStyle {
    var isProminent: Bool

    public init(isProminent: Bool = false) {
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isProminent ? DSColor.onAccent : DSColor.textPrimary)
            .frame(width: 40, height: 40)
            .background(
                Circle().fill(isProminent ? DSColor.accent : DSColor.surface)
            )
            .overlay(
                Circle().strokeBorder(isProminent ? Color.clear : DSColor.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}

public extension ButtonStyle where Self == DSSecondaryButtonStyle {
    static var dsSecondary: DSSecondaryButtonStyle { DSSecondaryButtonStyle() }
}

public extension ButtonStyle where Self == DSGhostButtonStyle {
    static var dsGhost: DSGhostButtonStyle { DSGhostButtonStyle() }
}

public extension ButtonStyle where Self == DSIconButtonStyle {
    static var dsIcon: DSIconButtonStyle { DSIconButtonStyle() }
    static func dsIcon(isProminent: Bool) -> DSIconButtonStyle { DSIconButtonStyle(isProminent: isProminent) }
}
