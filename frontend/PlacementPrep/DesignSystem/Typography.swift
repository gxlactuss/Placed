import SwiftUI

extension Font {
    static let ppDisplay = Font.system(.largeTitle, design: .serif, weight: .semibold)

    static let ppTitle = Font.system(.title2, design: .serif, weight: .semibold)

    static let ppHeadline = Font.system(.headline, weight: .semibold)

    static let ppBody = Font.system(.body)
    static let ppBodyMedium = Font.system(.body, weight: .medium)

    static let ppCaption = Font.system(.footnote, weight: .medium)

    static let ppMicro = Font.system(.caption2, weight: .semibold)

    static let ppSectionLabel = Font.system(.caption, weight: .semibold)

    static func ppStat(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .serif, weight: .semibold)
    }

    static func ppStatFixed(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}

extension View {
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
