import SwiftUI

/// The container every grouped block in the app sits inside.
///
/// ```swift
/// PPCard { Text("Daily streak") }
/// PPCard(tone: .accent) { statsRow }
/// ```
struct PPCard<Content: View>: View {

    enum Tone {
        /// Default block on the ground colour.
        case surface
        /// A card nested inside another surface, or a selected row.
        case elevated
        /// The blurple hero card used for headline statistics.
        case accent
    }

    var tone: Tone = .surface
    var padding: CGFloat = PPSpacing.lg
    var cornerRadius: CGFloat = PPRadius.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
    }

    @ViewBuilder
    private var background: some View {
        switch tone {
        case .surface: Color.ppSurface
        case .elevated: Color.ppElevated
        case .accent: LinearGradient.ppAccentCard
        }
    }

    private var borderColor: Color {
        switch tone {
        case .surface, .elevated: .ppBorder
        case .accent: .ppAccent.opacity(0.45)
        }
    }
}

#Preview("Cards") {
    VStack(spacing: PPSpacing.lg) {
        PPCard(tone: .accent) {
            HStack {
                PPStatTile(value: "24", label: "Quizzes", style: .inline)
                Divider().overlay(Color.white.opacity(0.2))
                PPStatTile(value: "78%", label: "Avg score", style: .inline)
                Divider().overlay(Color.white.opacity(0.2))
                PPStatTile(value: "6", label: "Interviews", style: .inline)
            }
            .frame(height: 52)
        }

        PPCard {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Company-wise DSA").font(.ppHeadline)
                Text("2,400+ tagged LeetCode problems")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }
        }

        PPCard(tone: .elevated) {
            Text("Elevated tone").font(.ppBodyMedium)
        }
    }
    .foregroundStyle(Color.ppText)
    .padding(PPSpacing.xl)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
