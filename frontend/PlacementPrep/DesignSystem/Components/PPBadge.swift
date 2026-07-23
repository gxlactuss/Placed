import SwiftUI

/// Difficulty semantics for the DSA content, kept separate from the networking
/// models so the design system stays independent. See the `QuizDifficulty`
/// bridge at the bottom of this file.
enum PPDifficulty: String, CaseIterable, Identifiable {
    case easy, medium, hard

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .easy: .ppEasy
        case .medium: .ppMedium
        case .hard: .ppHard
        }
    }

    /// Single-letter form used in the "12/30 E · 9/50 M · 2/20 H" summary line.
    var initial: String { title.prefix(1).uppercased() }
}

/// A small tinted pill. Difficulty labels, topic tags and frequency markers all
/// use this shape.
struct PPBadge: View {

    enum Tone {
        /// Blurple pill for topics, e.g. "CS Fundamentals".
        case accent
        /// Low-contrast pill for metadata, e.g. "Freq 98%".
        case neutral
        /// Any palette colour — pass `difficulty.color` here.
        case tinted(Color)
    }

    let text: String
    var tone: Tone = .neutral

    init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    init(_ difficulty: PPDifficulty) {
        self.text = difficulty.title
        self.tone = .tinted(difficulty.color)
    }

    var body: some View {
        Text(text)
            .font(.ppMicro)
            .foregroundStyle(foreground)
            .padding(.horizontal, PPSpacing.sm)
            .padding(.vertical, 5)
            .background(background, in: .capsule)
    }

    private var foreground: Color {
        switch tone {
        case .accent: .ppAccent300
        case .neutral: .ppMuted
        case .tinted(let color): color
        }
    }

    private var background: Color {
        switch tone {
        case .accent: .ppAccentSection
        case .neutral: .ppElevated
        case .tinted(let color): color.opacity(0.16)
        }
    }
}

/// Horizontally scrolling selector used for the company filter row.
struct PPFilterChip: View {

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ppCaption)
                .foregroundStyle(isSelected ? Color.ppOnAccent : Color.ppText)
                .padding(.horizontal, PPSpacing.lg)
                .frame(height: 36)
                .background(isSelected ? Color.ppAccent400 : Color.ppSurface, in: .capsule)
                .overlay {
                    Capsule().strokeBorder(
                        isSelected ? .clear : Color.ppBorderStrong,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Model bridge

extension PPDifficulty {
    init(_ difficulty: QuizDifficulty) {
        switch difficulty {
        case .easy: self = .easy
        case .medium: self = .medium
        case .hard: self = .hard
        }
    }
}

#Preview("Badges & chips") {
    VStack(alignment: .leading, spacing: PPSpacing.xl) {
        HStack(spacing: PPSpacing.sm) {
            ForEach(PPDifficulty.allCases) { PPBadge($0) }
            PPBadge("CS Fundamentals", tone: .accent)
            PPBadge("Freq 98%")
        }

        HStack(spacing: PPSpacing.sm) {
            PPFilterChip(title: "Google", isSelected: true) {}
            PPFilterChip(title: "Amazon", isSelected: false) {}
            PPFilterChip(title: "Meta", isSelected: false) {}
        }
    }
    .padding(PPSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .ppScreenBackground()
}
