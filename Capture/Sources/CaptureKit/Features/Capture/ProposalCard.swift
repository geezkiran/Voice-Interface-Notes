// The app is iOS-only (per the plan: native SwiftUI, App Store, iOS APIs
// throughout). The screens are fenced off so `swift build` on macOS still
// checks the design system and the model layer, which are portable.
#if os(iOS)
import SwiftUI
import DesignSystem

/// The one thing in this app that asks the user a question about their own
/// note: "this sounds like two notes — want me to split it?" or "you've talked
/// about this before — add it to that one?".
///
/// It sits *in* the page, between the heading and the body, rather than over it.
/// A sheet would cover the note the person is being asked to decide about, and a
/// screen of its own would put a decision gate on a flow whose whole promise is
/// that capture costs nothing. Inline, it can simply be ignored: the note is
/// already saved, already titled, already filed, and scrolling past this card
/// leaves it exactly as it is.
///
/// Both actions are reversible by hand and neither is destructive to a word the
/// user said — a split copies the whole recording onto both halves, and a merge
/// appends rather than overwrites — which is what makes it acceptable to offer
/// them one tap away.
struct ProposalCard: View {
    var proposal: CaptureProposal
    /// The note a merge would fold into. Resolved by the caller, which owns the
    /// store; nil is not a state this view can be in, because the caller doesn't
    /// build the card until it has one.
    var mergeTarget: CaptureItem?
    var onAccept: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                headline
                detail
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Headline

    /// The sparkle plus the model's own sentence. The gradient is this app's
    /// established "a model did this" signal — the same one Summarize wears —
    /// so a tinted line always means the same thing wherever it appears.
    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DSColor.intelligenceGradient)

            Text(reason)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DSColor.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The model's `reason`, which is the only explanation the user gets and the
    /// thing they decide from. Falling back to a generic line rather than
    /// showing an empty card — but the prompt works hard to make sure this
    /// fallback is never reached.
    private var reason: String {
        switch proposal {
        case .keep:
            return ""
        case let .merge(_, reason):
            return reason.isEmpty ? "This sounds like more of a note you already have." : reason
        case let .split(reason, _):
            return reason.isEmpty ? "This sounds like more than one note." : reason
        }
    }

    // MARK: Detail

    /// What would actually happen, named. A person cannot judge "split this"
    /// without seeing what the two halves would be called, and cannot judge
    /// "merge this" without seeing which note it would disappear into.
    @ViewBuilder
    private var detail: some View {
        switch proposal {
        case .keep:
            EmptyView()

        case .merge:
            if let mergeTarget {
                row(mergeTarget.title.isEmpty ? "Untitled" : mergeTarget.title)
            }

        case let .split(_, parts):
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    row(part.title)
                }
            }
        }
    }

    /// One named note-to-be. A middle dot rather than a bullet list: these are
    /// titles being pointed at, not items to be worked through, and the body
    /// text on this page carries no list markers either.
    private func row(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
            Text("·")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.textTertiary)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Actions

    /// Accept first, dismiss second, and the dismissal is a plain word rather
    /// than an ✕. The card is making an offer, and an offer needs a legible way
    /// to decline that says what declining *means* — "Keep as one" and "Keep
    /// separate" describe the outcome, where a close button would only describe
    /// the card going away.
    private var actions: some View {
        HStack(spacing: DSSpacing.sm) {
            Button(acceptLabel, action: onAccept)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DSColor.intelligenceGradient)
                .buttonStyle(.plain)

            Button(dismissLabel, action: onDismiss)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DSColor.textTertiary)
                .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.top, DSSpacing.xxs)
    }

    private var acceptLabel: String {
        switch proposal {
        case .keep: ""
        case .merge: "Add to it"
        case .split: "Split"
        }
    }

    private var dismissLabel: String {
        switch proposal {
        case .keep: ""
        case .merge: "Keep separate"
        case .split: "Keep as one"
        }
    }
}

#Preview("Split") {
    VStack(spacing: DSSpacing.md) {
        ProposalCard(
            proposal: .split(
                reason: "This starts on the Q3 launch date and then moves to booking the dentist.",
                parts: [
                    .init(title: "Q3 launch date moving to October", body: "", type: .idea),
                    .init(title: "Book the dentist for a cleaning", body: "", type: .task)
                ]
            ),
            mergeTarget: nil,
            onAccept: {},
            onDismiss: {}
        )

        ProposalCard(
            proposal: .merge(
                into: UUID(),
                reason: "You said more about the car insurance quotes you noted last week."
            ),
            mergeTarget: CaptureItem(title: "Renew the car insurance before it lapses"),
            onAccept: {},
            onDismiss: {}
        )
    }
    .padding(DSSpacing.md)
    .frame(maxHeight: .infinity)
    .background(DSColor.background)
}

#endif
