import SwiftUI

struct HomeTile<Icon: View, Content: View>: View {

    let title: String
    @ViewBuilder var icon: Icon
    @ViewBuilder var content: Content

    var body: some View {
        PPCard(padding: PPSpacing.lg) {
            VStack(spacing: PPSpacing.sm) {
                HStack(spacing: PPSpacing.sm) {
                    icon
                    Text(title)
                        .font(.ppMicro)
                        .foregroundStyle(Color.ppMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: PPSpacing.xs)
                content
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 118)
    }
}

struct HomeTileSymbol: View {

    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.ppAccent400)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

struct HomeTileValue: View {

    let value: String
    var tint: Color = .ppText
    var unit: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.ppStat())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

#Preview {
    Grid(horizontalSpacing: PPSpacing.md, verticalSpacing: PPSpacing.md) {
        GridRow {
            HomeTile(title: "Resume") { HomeTileSymbol(name: "doc.text.magnifyingglass") } content: {
                HomeTileValue(value: "72", tint: .ppAccent400, unit: "/100")
            }
            HomeTile(title: "Streak") { HomeTileSymbol(name: "flame.fill") } content: {
                HomeTileValue(value: "5", unit: "days")
            }
        }
    }
    .padding(PPSpacing.xl)
    .foregroundStyle(Color.ppText)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
