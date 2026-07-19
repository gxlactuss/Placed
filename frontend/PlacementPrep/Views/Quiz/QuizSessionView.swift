import SwiftUI

/// One run through a quiz, then its results. Both phases live behind the same
/// full-screen cover so the X dismisses back to the setup screen from either.
struct QuizSessionView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var model: QuizSessionModel

    init(topic: QuizTopic, difficulty: QuizDifficulty) {
        _model = State(initialValue: QuizSessionModel(topic: topic, difficulty: difficulty))
    }

    var body: some View {
        Group {
            if model.isFinished {
                QuizResultsView(
                    model: model,
                    onRetry: { model.restart() },
                    onClose: { dismiss() }
                )
            } else {
                questionScreen
            }
        }
        .ppScreenBackground()
        .onAppear { model.startTimer() }
        .onDisappear { model.stopTimer() }
    }

    // MARK: - Question phase

    private var questionScreen: some View {
        VStack(spacing: 0) {
            topBar
            progressHeader

            ScrollView {
                VStack(alignment: .leading, spacing: PPSpacing.xl) {
                    Text(model.current.prompt)
                        .font(.ppTitle)
                        .foregroundStyle(Color.ppText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: PPSpacing.md) {
                        ForEach(model.current.options) { option in
                            PPOptionRow(
                                letter: option.letter,
                                text: option.text,
                                state: .resolve(
                                    optionID: option.letter,
                                    selectedID: model.currentAnswer,
                                    correctID: model.current.correctLetter
                                )
                            ) {
                                model.answer(option.letter)
                            }
                        }
                    }

                    if model.currentAnswer != nil {
                        explanation
                    }
                }
                .padding(PPSpacing.xl)
            }
            .scrollIndicators(.hidden)

            footer
        }
    }

    private var topBar: some View {
        HStack(spacing: PPSpacing.md) {
            PPIconButton(systemName: "xmark", diameter: 36) { dismiss() }

            PPBadge(model.topic.displayName, tone: .accent)
            PPBadge(PPDifficulty(model.difficulty))

            Spacer()

            HStack(spacing: PPSpacing.xs) {
                Image(systemName: "clock")
                Text(model.formattedQuestionTime).monospacedDigit()
            }
            .font(.ppMicro)
            .foregroundStyle(Color.ppMuted)
            .padding(.horizontal, PPSpacing.md)
            .frame(height: 30)
            .background(Color.ppSurface, in: .capsule)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.vertical, PPSpacing.md)
    }

    private var progressHeader: some View {
        VStack(spacing: PPSpacing.sm) {
            HStack {
                Text("Question \(model.index + 1) of \(model.questions.count)")
                Spacer()
                Text("\(Int(model.progress * 100))%")
            }
            .font(.ppCaption)
            .foregroundStyle(Color.ppMuted)

            PPProgressBar(progress: model.progress)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.bottom, PPSpacing.md)
    }

    private var explanation: some View {
        PPCard(tone: .elevated) {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Label(
                    model.currentAnswer == model.current.correctLetter ? "Correct" : "Not quite",
                    systemImage: model.currentAnswer == model.current.correctLetter
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill"
                )
                .font(.ppMicro)
                .foregroundStyle(
                    model.currentAnswer == model.current.correctLetter ? Color.ppEasy : Color.ppHard
                )

                Text(model.current.explanation)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var footer: some View {
        HStack(spacing: PPSpacing.md) {
            Button("Skip") {
                withAnimation { model.advance() }
            }
            .buttonStyle(PPButtonStyle(variant: .secondary, expands: false))
            .disabled(model.currentAnswer != nil)
            .opacity(model.currentAnswer != nil ? 0.4 : 1)

            Button {
                withAnimation { model.advance() }
            } label: {
                Label(
                    model.isLastQuestion ? "Finish" : "Next",
                    systemImage: model.isLastQuestion ? "flag.checkered" : "arrow.right"
                )
                .labelStyle(.trailingIcon)
            }
            .buttonStyle(.ppPrimary)
        }
        .padding(PPSpacing.xl)
        .background(Color.ppGround)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ppBorder).frame(height: 1)
        }
        .animation(.easeOut(duration: 0.2), value: model.currentAnswer)
    }
}

#Preview {
    QuizSessionView(topic: .csFundamentals, difficulty: .medium)
}
