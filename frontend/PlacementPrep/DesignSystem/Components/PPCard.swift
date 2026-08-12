import SwiftUI

/// The container every grouped block in the app sits inside.
///
/// Flat by design: a fill and a hairline, no shadows, no gradients. Hierarchy
/// comes from the three surface steps and from typography, which keeps every
/// card a single cheap draw.
///
/// ```swift
/// PPCard { Text("Daily streak") }
/// PPCard(tone: .accent) { statsRow }   // solid amber — ink text inside
/// ```
struct PPCard<Content: View>: View {

    enum Tone {
        /// Default block on the ground colour.
        case surface
        /// A card nested inside another surface, or a selected row.
        case elevated
        /// The solid accent hero card. Content inside must use the accent's ink
        /// (`Color.ppOnAccent`) for text, not the usual light palette.
        case accent
    }

    var tone: Tone = .surface
    var padding: CGFloat = PPSpacing.lg
    var cornerRadius: CGFloat = PPRadius.lg
    /// A colour bled across the card from its leading edge — used to carry a
    /// problem's difficulty across its whole row rather than leaving it to a
    /// badge the eye has to find.
    ///
    /// **The one sanctioned gradient in the design system.** It's kept honest by
    /// being a wash of a single hue over the normal fill (never a second colour,
    /// never a shift in lightness for its own sake), so the flat-surfaces rule
    /// still holds everywhere else. Pass `nil` — the default — for a plain card.
    var wash: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fill)
                    .overlay {
                        if let wash {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(
                                    LinearGradient(
                                        stops: [
                                            .init(color: wash.opacity(0.22), location: 0),
                                            .init(color: wash.opacity(0.08), location: 0.45),
                                            .init(color: wash.opacity(0.02), location: 1),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                    }
            }
            .overlay {
                if tone != .accent {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.ppBorder, lineWidth: 1)
                }
            }
            .contentShape(.rect(cornerRadius: cornerRadius))
    }

    private var fill: Color {
        switch tone {
        case .surface: .ppSurface
        case .elevated: .ppElevated
        case .accent: .ppAccent
        }
    }
}

/// Press feedback for tappable cards: a small spring scale and dim. Scale and
/// opacity are GPU-composited transforms — the cheapest animations available.
struct PPPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(PPMotion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PPPressableStyle {
    static var ppPressable: PPPressableStyle { PPPressableStyle() }
}

#Preview("Cards") {
    VStack(spacing: PPSpacing.lg) {
        PPCard(tone: .accent) {
            PPStatRow(
                items: [
                    .init(value: "24", label: "Quizzes"),
                    .init(value: "78%", label: "Avg score"),
                    .init(value: "6", label: "Interviews"),
                ],
                valueColor: .ppOnAccent,
                labelColor: Color.ppOnAccent.opacity(0.65)
            )
        }

        Button {
        } label: {
            PPCard {
                VStack(alignment: .leading, spacing: PPSpacing.sm) {
                    Text("Company-wise DSA").font(.ppHeadline)
                    Text("Tap me — cards press with a spring")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                }
            }
        }
        .buttonStyle(.ppPressable)

        PPCard(tone: .elevated) {
            Text("Elevated tone").font(.ppBodyMedium)
        }
    }
    .foregroundStyle(Color.ppText)
    .padding(PPSpacing.xl)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
