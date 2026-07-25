import SwiftUI

/// Button styling for the three button weights in the designs:
/// the bordered blurple call to action ("Next", "Retry quiz"), the neutral
/// companion beside it ("Skip", "Review answers"), and a borderless text button.
struct PPButtonStyle: ButtonStyle {

    enum Variant {
        case primary
        case secondary
        case ghost
    }

    var variant: Variant = .primary
    /// Set false for buttons that should hug their label instead of filling the row.
    var expands: Bool = true
    /// Breathing room either side of the label. Buttons that sit *inside* a line
    /// of text zero this out: otherwise the padding is invisible but still
    /// measured, so a centred sentence ends up centred on the padding rather
    /// than on the words, and reads as off-centre.
    var horizontalPadding: CGFloat = PPSpacing.xl

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ppBodyMedium)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: PPSize.control)
            .background(background)
            .clipShape(.rect(cornerRadius: PPRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.md)
                    .strokeBorder(border, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PPMotion.snappy, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch variant {
        case .primary: .ppOnAccent
        case .secondary: .ppText
        case .ghost: .ppAccent400
        }
    }

    private var background: Color {
        switch variant {
        case .primary: .ppAccent
        case .secondary: .ppSurface
        case .ghost: .clear
        }
    }

    private var border: Color {
        switch variant {
        case .primary: .clear
        case .secondary: .ppBorderStrong
        case .ghost: .clear
        }
    }
}

extension ButtonStyle where Self == PPButtonStyle {
    static var ppPrimary: PPButtonStyle { PPButtonStyle(variant: .primary) }
    static var ppSecondary: PPButtonStyle { PPButtonStyle(variant: .secondary) }
    static var ppGhost: PPButtonStyle { PPButtonStyle(variant: .ghost, expands: false) }
    /// A ghost button that reads as a word in a sentence ("New here? **Create one**").
    /// No side padding, so the sentence centres on its visible text.
    static var ppInlineLink: PPButtonStyle {
        PPButtonStyle(variant: .ghost, expands: false, horizontalPadding: 0)
    }
}

/// Places the icon after the title, as on the "Next →" control.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: PPSpacing.sm) {
            configuration.title
            configuration.icon
        }
    }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: TrailingIconLabelStyle { TrailingIconLabelStyle() }
}

/// Circular icon button — used for the microphone control on the mock interview
/// screen and the dismiss control on the quiz screen.
struct PPIconButton: View {

    let systemName: String
    var diameter: CGFloat = 44
    var tint: Color = .ppText
    var fill: Color = .ppSurface
    /// Draws a soft halo behind the button, as on the active recording control.
    var isGlowing: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.4, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: diameter, height: diameter)
                .background(fill, in: .circle)
                .shadow(color: isGlowing ? fill.opacity(0.6) : .clear, radius: 18)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Buttons") {
    VStack(spacing: PPSpacing.lg) {
        HStack(spacing: PPSpacing.md) {
            Button("Skip") {}
                .buttonStyle(PPButtonStyle(variant: .secondary, expands: false))
            Button {
            } label: {
                Label("Next", systemImage: "arrow.right")
                    .labelStyle(.trailingIcon)
            }
            .buttonStyle(.ppPrimary)
        }

        Button("Retry quiz") {}
            .buttonStyle(.ppPrimary)

        Button("Review answers") {}
            .buttonStyle(.ppSecondary)

        Button("Start") {}
            .buttonStyle(.ppGhost)

        // Inline link: the pair should sit optically centred in the row.
        HStack(spacing: PPSpacing.sm) {
            Text("New here?")
                .font(.ppBody)
                .foregroundStyle(Color.ppMuted)
            Button("Create one") {}
                .buttonStyle(.ppInlineLink)
        }
        .frame(maxWidth: .infinity)

        HStack(spacing: PPSpacing.xl) {
            PPIconButton(systemName: "xmark", diameter: 36) {}
            PPIconButton(
                systemName: "mic.fill",
                diameter: 76,
                tint: .white,
                fill: .ppHard,
                isGlowing: true
            ) {}
        }
    }
    .padding(PPSpacing.xl)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
