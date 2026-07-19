import SwiftUI

/// Type scale.
///
/// These map onto the system text styles rather than fixed point sizes so the
/// whole app responds to Dynamic Type. The comment on each line is the size the
/// style resolves to at the default `.large` content size, which is what the
/// reference designs were drawn at.
extension Font {

    /// Screen titles, e.g. "Companies". Serif (New York) — the system's own
    /// editorial voice, no bundled font needed. Resolves to 34pt.
    static let ppDisplay = Font.system(.largeTitle, design: .serif, weight: .semibold)

    /// The user's name on the home header, quiz question prompts. 22pt.
    static let ppTitle = Font.system(.title2, design: .serif, weight: .semibold)

    /// Card headings, e.g. "Company-wise DSA". 17pt.
    static let ppHeadline = Font.system(.headline, weight: .semibold)

    /// Default reading size for answer options and message bubbles. 17pt.
    static let ppBody = Font.system(.body)
    static let ppBodyMedium = Font.system(.body, weight: .medium)

    /// Supporting copy under a headline, e.g. "CS · DSA · Aptitude". 13pt.
    static let ppCaption = Font.system(.footnote, weight: .medium)

    /// Badge and pill text, e.g. "Medium", "Freq 98%". 11pt.
    static let ppMicro = Font.system(.caption2, weight: .semibold)

    /// Uppercased, letter-spaced group labels, e.g. "PRACTICE MODES". 12pt.
    static let ppSectionLabel = Font.system(.caption, weight: .semibold)

    /// Numerals that carry a card, e.g. "78%", "12 day streak". Serif numerals
    /// read like a broadsheet figure, not a fitness app.
    static func ppStat(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .serif, weight: .semibold)
    }

    /// Non-scaling variant of `ppStat`, for numerals laid out inside fixed
    /// geometry — the score ring in particular, where scaling the text would
    /// push it outside the circle it sits in.
    static func ppStatFixed(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}

// MARK: - Text styles

extension View {

    /// Uppercases and tracks a label the way section headers are drawn in the designs.
    func ppSectionLabelStyle() -> some View {
        self
            .font(.ppSectionLabel)
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(Color.ppMuted)
    }
}

#Preview("Typography") {
    VStack(alignment: .leading, spacing: PPSpacing.lg) {
        Text("Companies").font(.ppDisplay)
        Text("Khushi Shelke").font(.ppTitle)
        Text("Company-wise DSA").font(.ppHeadline)
        Text("Which page-replacement algorithm can exhibit Belady's anomaly?")
            .font(.ppBody)
        Text("2,400+ tagged LeetCode problems")
            .font(.ppCaption)
            .foregroundStyle(Color.ppMuted)
        Text("Practice modes").ppSectionLabelStyle()
        Text("78%").font(.ppStat(.largeTitle))
    }
    .foregroundStyle(Color.ppText)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(PPSpacing.xl)
    .ppScreenBackground()
}
