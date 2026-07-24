import SwiftUI

/// Plays one quiz, then shows its result. Category-agnostic — it renders
/// whatever `Quiz` it is handed, so a 3-question aptitude set and a 10-question
/// CS set use the same view.
struct QuizView: View {

    let quiz: Quiz

    @Environment(\.dismiss) private var dismiss
    @Environment(QuizProgressStore.self) private var progress
    @Environment(SavedQuestionsStore.self) private var saved
    @State private var model: QuizSessionModel

    init(quiz: Quiz) {
        self.quiz = quiz
        _model = State(initialValue: QuizSessionModel(quiz: quiz))
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
        .onChange(of: model.isFinished) { _, finished in
            // Record on completion, not on every answer, so an abandoned run
            // never counts toward unlocking.
            if finished {
                progress.record(
                    score: model.scorePercentage,
                    correct: model.correctCount,
                    total: model.questions.count,
                    for: quiz
                )
            }
        }
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
                                letter: option.id,
                                text: option.text,
                                state: .resolve(
                                    optionID: option.id,
                                    selectedID: model.currentAnswer,
                                    correctID: model.current.correctOptionID
                                )
                            ) {
                                model.answer(option.id)
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

            PPBadge(quiz.category.title, tone: .neutral)
            PPBadge(quiz.difficulty.title, tone: .tinted(quiz.difficulty.accent))

            Spacer()

            HStack(spacing: PPSpacing.xs) {
                Image(systemName: "clock")
                Text(model.formattedQuestionTime)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(PPMotion.snappy, value: model.formattedQuestionTime)
            }
            .font(.ppMicro)
            .foregroundStyle(Color.ppMuted)
            .padding(.horizontal, PPSpacing.md)
            .frame(height: 30)
            .background(Color.ppSurface, in: .capsule)

            saveButton
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.vertical, PPSpacing.md)
    }

    /// Bookmarks the current question for review on the Saved page. Filled and
    /// accent-tinted once saved.
    private var saveButton: some View {
        let isSaved = saved.isSaved(model.current.id)
        return PPIconButton(
            systemName: isSaved ? "bookmark.fill" : "bookmark",
            diameter: 36,
            tint: isSaved ? .ppAccent : .ppText
        ) {
            withAnimation(PPMotion.snappy) { saved.toggle(model.current.id) }
        }
        .accessibilityLabel(isSaved ? "Saved" : "Save question")
    }

    private var progressHeader: some View {
        VStack(spacing: PPSpacing.sm) {
            HStack {
                Text("Question \(model.index + 1) of \(model.questions.count)")
                Spacer()
                Text("Pass \(quiz.passPercentage)%")
            }
            .font(.ppCaption)
            .foregroundStyle(Color.ppMuted)

            PPProgressBar(progress: model.progress)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.bottom, PPSpacing.md)
    }

    private var explanation: some View {
        let wasRight = model.currentAnswer == model.current.correctOptionID

        return PPCard(tone: .elevated) {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Label(
                    wasRight ? "Correct" : "Not quite",
                    systemImage: wasRight ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.ppMicro)
                .foregroundStyle(wasRight ? Color.ppEasy : Color.ppHard)

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
        .background(.ultraThinMaterial)
        .background(Color.ppGround.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ppBorder).frame(height: 1)
        }
        .animation(PPMotion.snappy, value: model.currentAnswer)
    }
}

#Preview {
    if let quiz = QuizBank().quizzes(in: .aptitude).first {
        QuizView(quiz: quiz)
            .environment(QuizProgressStore.preview())
            .environment(SavedQuestionsStore.preview())
    } else {
        Text("No quiz JSON bundled").ppScreenBackground()
    }
}
