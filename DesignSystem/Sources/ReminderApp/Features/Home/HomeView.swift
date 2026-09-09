// The app is iOS-only (per the plan: native SwiftUI, App Store, iOS APIs
// throughout). The screens are fenced off so `swift build` on macOS still
// checks the design system and the model layer, which are portable.
#if os(iOS)
import SwiftUI
import UIKit
import DesignSystem

/// **The list.** The default landing screen: every past capture, newest first,
/// one flat list. It wears Apple Notes' note list, down to the inset-grouped
/// rows, and each row carries its own date.
///
/// Above the list sits the type strip — "All" and one title per `ItemType`,
/// drawn as display-size words rather than as a control (`DSTitleTabs`), so the
/// current filter *is* the screen's title instead of sitting under one.
///
/// One deliberate departure from Notes: the floating plus opens the
/// **recorder**, not a blank page. It wears Notes' glyph and Notes' yellow,
/// because the app's premise is that capture is a reflex, spoken. The written
/// path exists — the small plus up in the masthead — but it is deliberately the
/// quieter of the two: it is there for the text you already have and can only
/// paste, not for the thought you are having right now.
struct HomeView: View {
    var store: CaptureStore
    /// Starts a written note rather than a spoken one, filed under the type the
    /// strip is standing on (nil on "All"). See `plusButton`.
    var onNewNote: (ItemType?) -> Void

    /// The type the strip is standing on. `nil` is "All" — the rest are the
    /// `ItemType` cases in declaration order. Local state, not persisted: the
    /// list opens on everything, every time.
    @State private var filter: ItemType?

    private var items: [CaptureItem] {
        store.visibleItems(filter: filter)
    }

    private var filterTabs: [DSTitleTabs<ItemType?>.Item] {
        [.init(value: nil, label: "All")]
            + ItemType.allCases.map { .init(value: $0, label: $0.sectionTitle) }
    }

    var body: some View {
        List {
            // The masthead: the logo top-left, the written-note plus top-right.
            // It scrolls away with everything else rather than pinning, matching
            // the strip it sits over (nothing on this screen is fixed chrome).
            // No avatar — this is a single-person app, so a picture of the only
            // person using it was a badge, not a control.
            Section {
                HStack(spacing: DSSpacing.sm) {
                    DSLogo(height: 30)
                    Spacer()
                    plusButton
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.xs)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listSectionMargins(.horizontal, 0)

            // The type strip. Full-bleed — it brings its own leading inset and
            // has to be able to scroll out to both edges — so the row insets
            // are cleared rather than left at the list's.
            Section {
                DSTitleTabs(items: filterTabs, selection: $filter)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listSectionMargins(.horizontal, 0)

            // The captures get a section of their own so the card treatment
            // starts below the masthead rather than swallowing it.
            Section {
                if items.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                ForEach(items) { item in
                    NavigationLink(value: item.id) {
                        row(for: item)
                    }
                    .listRowBackground(DSColor.surface)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(item)
                        } label: {
                            // No caption: the glyph and its color say it, and
                            // the word underneath only made the target smaller.
                            // The name moves to the accessibility label, which
                            // is where a screen reader was reading it from
                            // anyway.
                            Self.swipeIcon("trash", tint: DSColor.danger)
                        }
                        .accessibilityLabel("Delete")
                        // Cleared, not colored: the color moves into the ring
                        // and the glyph, so the action is named rather than
                        // shouted by a block of fill.
                        .tint(.clear)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            store.markDone(item)
                        } label: {
                            Self.swipeIcon(
                                item.state == .done ? "arrow.uturn.backward" : "checkmark",
                                tint: DSColor.success
                            )
                        }
                        .accessibilityLabel(item.state == .done ? "Reopen" : "Done")
                        .tint(.clear)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        // An inset-grouped list reserves room above its first section for a
        // header it doesn't have here; the strip brings its own padding.
        .contentMargins(.top, DSSpacing.xs, for: .scrollContent)
        .listSectionSpacing(DSSpacing.xs)
        .scrollContentBackground(.hidden)
        .background(DSColor.background)
        // No title bar and nothing pinned: the masthead scrolls away with the
        // content.
        .toolbar(.hidden, for: .navigationBar)
        // The bottom bar — roots plus the capture button — is `RootView`'s, so
        // it's identical here and on Schedule and doesn't follow the user into
        // Editing. It reserves its own space, so the last row can always be
        // scrolled clear of it.
    }

    // MARK: Pieces

    /// The one way into a note without talking. Voice is still the premise —
    /// which is why this is a small disc up in the masthead rather than a
    /// second button beside the yellow one in the bottom bar — but pasting a
    /// page of text you already have is not a thing you can say out loud, and
    /// until now there was no path in for it at all.
    ///
    /// It opens the same Editing screen every capture opens in, on an empty
    /// section with the keyboard already up.
    ///
    /// Drawn to match Editing's back button — a 44pt glass disc — so the two
    /// pieces of floating chrome in the app are the same object at different
    /// corners. Deliberately not tinted: yellow means "start talking".
    private var plusButton: some View {
        Button {
            onNewNote(filter)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New typed note")
    }

    /// A swipe action drawn as an outlined disc: colored glyph inside a
    /// hairline ring in the same color, over a wash of it.
    ///
    /// Baked into a bitmap rather than composed in SwiftUI, and that is not a
    /// preference — `swipeActions` does not render the view you hand it. It
    /// takes the symbol out of the label and draws it itself, in its own
    /// white, on a disc filled with the button's tint; a `Circle` overlay is
    /// discarded and a `foregroundStyle` is overwritten. An image marked
    /// `.alwaysOriginal` is the one thing it will not recolor, so the ring and
    /// the color are drawn here, into the icon itself, and the tint at the
    /// call site is cleared so nothing is painted behind them.
    ///
    /// Drawn at the size it should appear at: the system scales whatever it
    /// gets into its glyph slot, so a disc drawn much larger would come back
    /// with a hairline ring around a shrunken glyph. The canvas carries a
    /// margin of its own, which is the gap between the disc and the row edge —
    /// there is no view around this image to put padding on.
    private static func swipeIcon(_ systemName: String, tint: Color) -> Image {
        let disc: CGFloat = 44
        let margin: CGFloat = 6
        let canvas = disc + margin * 2
        let line: CGFloat = 1
        // How much of the disc the glyph fills. Well under half: the room
        // inside the ring is what makes it read as a target rather than a
        // badge, and the ring is thin enough that a crowded glyph would touch.
        let glyphRatio: CGFloat = 0.36
        let color = UIColor(tint)

        let image = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas)).image { _ in
            let ring = UIBezierPath(
                ovalIn: CGRect(
                    x: margin + line / 2,
                    y: margin + line / 2,
                    width: disc - line,
                    height: disc - line
                )
            )
            // A wash of the same color inside the ring — enough to make the
            // disc read as a filled target rather than an empty outline,
            // nowhere near enough to become the block of color the system's
            // own treatment paints.
            color.withAlphaComponent(0.14).setFill()
            ring.fill()

            ring.lineWidth = line
            color.setStroke()
            ring.stroke()

            let config = UIImage.SymbolConfiguration(pointSize: disc * glyphRatio, weight: .semibold)
            if let glyph = UIImage(systemName: systemName, withConfiguration: config)?
                .withTintColor(color, renderingMode: .alwaysOriginal) {
                glyph.draw(
                    at: CGPoint(
                        x: (canvas - glyph.size.width) / 2,
                        y: (canvas - glyph.size.height) / 2
                    )
                )
            }
        }

        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }

    private func row(for item: CaptureItem) -> some View {
        DSNoteRow(
            title: item.title,
            preview: item.summary.isEmpty ? item.transcript : item.summary,
            dateLabel: dateLabel(for: item.createdAt)
        )
        .opacity(item.state == .done ? 0.45 : 1)
        .strikethrough(item.state == .done, color: DSColor.textSecondary)
    }

    private var emptyState: some View {
        VStack(spacing: DSSpacing.md) {
            // The brand mark with its mouth turned down. Barely there on
            // purpose: an empty list is a normal state, not a fault, so the
            // mark sits at the tertiary ink and is faded further still —
            // present if you look for it, invisible if you don't.
            DSLogo(.down, height: 72, tint: DSColor.textTertiary)
                // Fainter than the line under it: the mark is atmosphere, the
                // sentence is the part that has to be read.
                .opacity(0.45)

            // Held to a narrow column so the line breaks under the mark
            // rather than running the width of the list.
            Text("Oops! Nothing to show here.")
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 180)
        }
        .opacity(0.5)
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xxl)
    }

    // MARK: Formatting

    /// Notes shows a time for today's notes and a date for everything else;
    /// this matches that exactly.
    private func dateLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            date.formatted(date: .omitted, time: .shortened)
        } else if Calendar.current.isDateInYesterday(date) {
            "Yesterday"
        } else {
            date.formatted(.dateTime.day().month(.abbreviated))
        }
    }
}

#Preview {
    RootView()
}

#endif
