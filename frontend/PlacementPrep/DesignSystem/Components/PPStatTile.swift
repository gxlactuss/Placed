import SwiftUI

/// A number over a label. Appears bare inside the blurple hero card (`.inline`)
/// and inside its own surface card on the results screen (`.card`).
struct PPStatTile: View {

    enum Style {
        case inline
        case card
    }

    let value: String
    let label: String
    var style: Style = .card
    /// Overrides the value colour, e.g. green for "Top 18%".
    var valueColor: Color = .ppText

    var body: some View {
        Group {
            switch style {
            case .inline: content
            case .card: PPCard(padding: PPSpacing.md, cornerRadius: PPRadius.md) { content }
            }
        }
    }

    private var content: some View {
        VStack(spacing: PPSpacing.xs) {
            Text(value)
                .font(.ppStat())
                .foregroundStyle(valueColor)
            Text(label)
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Evenly divided row of inline tiles, as on the home hero card.
struct PPStatRow: View {

    struct Item: Identifiable {
        let id = UUID()
        let value: String
        let label: String

        init(value: String, label: String) {
            self.value = value
            self.label = label
        }
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1, height: 34)
                }
                PPStatTile(value: item.value, label: item.label, style: .inline)
            }
        }
    }
}

#Preview("Stats") {
    VStack(spacing: PPSpacing.lg) {
        PPCard(tone: .accent) {
            PPStatRow(items: [
                .init(value: "24", label: "Quizzes"),
                .init(value: "78%", label: "Avg score"),
                .init(value: "6", label: "Interviews"),
            ])
        }

        HStack(spacing: PPSpacing.md) {
            PPStatTile(value: "4:12", label: "Time")
            PPStatTile(value: "Top 18%", label: "Percentile", valueColor: .ppEasy)
            PPStatTile(value: "+120", label: "XP")
        }
    }
    .padding(PPSpacing.xl)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
