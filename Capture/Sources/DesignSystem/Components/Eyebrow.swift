import SwiftUI

/// A tiny lowercase label that sits beside a block of content and says when it
/// arrived, not what it is.
///
/// It is deliberately the quietest type in the system: small, tracked wide,
/// tertiary gray, and nothing else. A dated body is meant to read as one piece
/// of prose, so the dates have to be findable without ever competing with the
/// sentences they belong to — the space around each one is what separates the
/// sections; the label just labels.
///
/// `isLive` promotes it for exactly one case — the section currently being
/// dictated into — where the label stops being a date and starts being a
/// status, and needs to read as the active thing on screen.
public struct DSEyebrow: View {
    var text: String
    var isLive: Bool

    public init(_ text: String, isLive: Bool = false) {
        self.text = text
        self.isLive = isLive
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xs) {
            if isLive {
                Circle()
                    .fill(DSColor.danger)
                    .frame(width: 6, height: 6)
            }

            Text(text)
                .font(.system(size: 15, weight: .semibold))
                // Lowercase carries its own ascenders and descenders, so it
                // reads as a label without the wide uppercase tracking; just
                // enough to keep it from setting tight at this size.
                .tracking(0.2)
                .foregroundStyle(isLive ? DSColor.textPrimary : DSColor.textTertiary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: DSSpacing.lg) {
        DSEyebrow("3h ago")
        DSEyebrow("2mo ago")
        DSEyebrow("adding now", isLive: true)
    }
    .padding()
    .background(DSColor.background)
}
