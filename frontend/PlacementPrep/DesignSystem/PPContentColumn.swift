import SwiftUI

/// How the app behaves on a screen wider than a phone.
///
/// The Ledger layouts are one column of full-bleed cards, and that is a
/// deliberate shape, not a limitation of the device they were drawn on. Let the
/// same column run to 1024pt and it stops being a column: a card's title sits a
/// hand's width from its badge, body text runs past a comfortable measure, and
/// the hairline borders that carry all the depth end up framing mostly nothing.
///
/// So an iPad does not get a different design — it gets the same one, held to
/// the width it was drawn for, with the ground showing either side. That is the
/// whole adaptation, and it is why it lives in one file: a screen opts in with a
/// single modifier and inherits every later decision made here.
///
/// Two widths, because the screens fall into two kinds:
///
///  * `contentColumn` — a stack of cards read top to bottom (Home, a quiz
///    question, the interview transcript). One column, phone measure.
///  * `wideColumn` — a long flat list of short rows (companies, quizzes in a
///    track). One phone-width column of these on an iPad is a ribbon down the
///    middle of an empty screen, so these get a wider frame and lay their rows
///    out in `ppAdaptiveColumns` columns instead.
///
/// Nothing here is gated on the idiom. The caps are expressed as maximums, so
/// on a phone — where the available width is already narrower — they cost
/// nothing and change no pixel. Split View and Slide Over land in the compact
/// size class and get the phone layout for the same reason.
extension View {

    /// Holds this content to a readable measure and centres it in whatever
    /// width it is given.
    ///
    /// Apply it *outside* the content's own padding, so the gutter travels with
    /// the column rather than being stranded against the screen edge.
    func ppContentColumn(_ width: CGFloat = PPSize.contentColumn) -> some View {
        // Two frames, and both are load-bearing: the first caps the content,
        // the second makes the result greedy again so the cap has a full-width
        // box to be centred inside. With only the first, the column pins to
        // whichever edge the parent's alignment happens to name.
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
    }
}

extension PPSize {

    /// Widest a column of cards is allowed to get. Close to a large phone plus
    /// its gutters, which is the measure the cards were drawn at.
    static let contentColumn: CGFloat = 640

    /// Widest a multi-column list is allowed to get. Two `contentColumn`-ish
    /// rows side by side, and no wider — a third column of company rows on a
    /// 13" iPad reads as a table, not as a list.
    static let wideColumn: CGFloat = 980
}

/// How many columns a list of short rows should use at the current width.
///
/// A `LazyVGrid` with an adaptive `GridItem` would also reflow, but it sizes
/// columns from a minimum width and so silently picks three or four on a big
/// iPad. This says the number outright, which is the decision worth keeping.
struct PPAdaptiveColumns: DynamicProperty {

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// 1 on a phone (and in Split View), 2 on a full-width iPad.
    var count: Int { sizeClass == .regular ? 2 : 1 }

    /// Ready to hand to `LazyVGrid(columns:)`.
    func grid(spacing: CGFloat = PPSpacing.md) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}

#Preview("Content column") {
    ScrollView {
        VStack(spacing: PPSpacing.md) {
            ForEach(0..<4, id: \.self) { index in
                PPCard {
                    Text("Card \(index + 1) — held to \(Int(PPSize.contentColumn))pt however wide the screen is")
                        .font(.ppBody)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(PPSpacing.xl)
        .ppContentColumn()
    }
    .foregroundStyle(Color.ppText)
    .ppScreenBackground()
}
