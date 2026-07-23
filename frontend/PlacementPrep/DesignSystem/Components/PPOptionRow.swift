import SwiftUI

/// A selectable multiple-choice answer on the quiz screen.
///
/// Answering is a one-shot commit: the moment the user taps, the row resolves to
/// `.correct` or `.incorrect` and every option in the question locks. `state` is
/// therefore kept separate from "did the user tap this one", so a resolved
/// question can simultaneously mark the user's wrong pick and reveal the right
/// answer. Drive it with `PPOptionRow.State.resolve(...)` below.
struct PPOptionRow: View {

    enum State: Equatable {
        /// No answer committed yet — the row is tappable.
        case idle
        /// The committed answer, and it was right.
        case correct
        /// The committed answer, and it was wrong.
        case incorrect
        /// Not chosen, but revealed as the right answer after a wrong pick.
        case revealed
        /// Not chosen, question already resolved. Dimmed and inert.
        case dimmed

        /// Resolves the state for one option given the question's answer state.
        /// Pass `selectedID` as nil while the question is still unanswered.
        static func resolve(
            optionID: String,
            selectedID: String?,
            correctID: String
        ) -> State {
            guard let selectedID else { return .idle }
            let userWasRight = selectedID == correctID

            if optionID == selectedID {
                return userWasRight ? .correct : .incorrect
            }
            if optionID == correctID && !userWasRight {
                return .revealed
            }
            return .dimmed
        }

        /// True once the question is committed — the row must not accept taps.
        var isLocked: Bool { self != .idle }
    }

    let letter: String
    let text: String
    var state: State = .idle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PPSpacing.md) {
                Text(letter)
                    .font(.ppMicro)
                    .foregroundStyle(markerForeground)
                    .frame(width: 26, height: 26)
                    .background(markerBackground, in: .rect(cornerRadius: PPRadius.sm))

                Text(text)
                    .font(.ppBody)
                    .foregroundStyle(Color.ppText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .foregroundStyle(accent)
                        // One-shot bounce when the verdict lands; free after that.
                        .symbolEffect(.bounce, value: state)
                }
            }
            .padding(PPSpacing.lg)
            .background(background, in: .rect(cornerRadius: PPRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.md)
                    .strokeBorder(border, lineWidth: isHighlighted ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        // Once committed the answer cannot be changed, so locked rows stop
        // taking hits entirely rather than merely looking inert.
        .disabled(state.isLocked)
        .opacity(state == .dimmed ? 0.55 : 1)
        .animation(PPMotion.snappy, value: state)
        .accessibilityLabel(Text("\(letter). \(text)"))
        .accessibilityValue(Text(accessibilityValue))
    }

    /// The states that paint themselves in a semantic colour.
    private var isHighlighted: Bool {
        switch state {
        case .idle, .dimmed: false
        case .correct, .incorrect, .revealed: true
        }
    }

    private var accent: Color {
        switch state {
        case .idle, .dimmed: .ppMuted
        case .correct, .revealed: .ppEasy
        case .incorrect: .ppHard
        }
    }

    private var background: Color {
        isHighlighted ? accent.opacity(0.14) : .ppSurface
    }

    private var border: Color {
        isHighlighted ? accent : .ppBorder
    }

    private var markerBackground: Color {
        isHighlighted ? accent : .ppElevated
    }

    private var markerForeground: Color {
        isHighlighted ? .ppOnAccent : .ppMuted
    }

    private var trailingSymbol: String? {
        switch state {
        case .idle, .dimmed: nil
        case .correct, .revealed: "checkmark.circle.fill"
        case .incorrect: "xmark.circle.fill"
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .idle: ""
        case .correct: "Your answer, correct"
        case .incorrect: "Your answer, incorrect"
        case .revealed: "Correct answer"
        case .dimmed: ""
        }
    }
}

#Preview("Option rows") {
    @Previewable @State var selected: String?

    let options = [
        ("A", "LRU (Least Recently Used)"),
        ("B", "Optimal (OPT)"),
        ("C", "FIFO (First In First Out)"),
        ("D", "Clock (Second Chance)"),
    ]
    let correct = "C"

    VStack(spacing: PPSpacing.md) {
        ForEach(options, id: \.0) { id, text in
            PPOptionRow(
                letter: id,
                text: text,
                state: .resolve(optionID: id, selectedID: selected, correctID: correct)
            ) {
                selected = id
            }
        }

        Button("Reset") { selected = nil }
            .buttonStyle(.ppGhost)
            .padding(.top, PPSpacing.lg)
    }
    .padding(PPSpacing.xl)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
