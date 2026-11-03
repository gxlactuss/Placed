import SwiftUI

struct PPScoreBars: View {

    struct Item: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let score: Int
        var detail: String? = nil
    }

    let items: [Item]
    var revealed = true

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            ForEach(items) { item in
                row(item)
            }
        }
    }

    private func row(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.xs) {
            HStack(spacing: PPSpacing.sm) {
                Image(systemName: item.symbol)
                    .foregroundStyle(Color.ppMuted)
                    .frame(width: 18)
                Text(item.title)
                Spacer(minLength: PPSpacing.md)
                HStack(spacing: 0) {
                    Text("\(item.score)")
                        .foregroundStyle(Color.ppScore(Double(item.score), middle: .ppAccent400))
                    Text(" / 10")
                        .foregroundStyle(Color.ppMuted)
                }
                .monospacedDigit()
            }
            .font(.ppCaption)

            PPProgressBar(
                progress: revealed ? Double(item.score) / 10 : 0,
                height: 6,
                tint: .ppScore(Double(item.score))
            )

            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.score) out of 10")
        .accessibilityHint(item.detail ?? "")
    }
}

#Preview("Score bars") {
    PPCard {
        PPScoreBars(items: [
            .init(id: "a", title: "Correctness", symbol: "checkmark.circle", score: 8),
            .init(id: "b", title: "Depth", symbol: "square.stack.3d.up", score: 5,
                  detail: "Stops at the definition and never gets to the trade-offs."),
            .init(id: "c", title: "Confidence", symbol: "waveform", score: 3),
        ])
    }
    .padding(PPSpacing.xl)
    .foregroundStyle(Color.ppText)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
