import SwiftUI

struct QuizView: View {

    let quiz: Quiz

    @Environment(\.dismiss) private var dismiss
    @Environment(QuizBank.self) private var bank
    @Environment(QuizProgressStore.self) private var progress
    @Environment(SavedQuestionsStore.self) private var saved
    @Environment(StreakStore.self) private var streak
    @Environment(XPStore.self) private var xp
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
            if finished {
                progress.record(
                    score: model.scorePercentage,
                    correct: model.correctCount,
                    total: model.questions.count,
                    for: quiz
                )
                streak.recordActivity()
                var earned = xp.awardStreakDay()
                if model.scorePercentage >= XPAward.quizThreshold {
                    earned += xp.award(.quizPassed(quizID: quiz.id))
                }
                model.recordXP(earned)
            }
        }
    }

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
                                guard model.currentAnswer == nil else { return }
                                model.answer(option.id)
                                if option.id == model.current.correctOptionID {
                                    PPHaptics.success()
                                } else {
                                    PPHaptics.miss()
                                }
                            }
                        }
                    }

                    if model.currentAnswer != nil {
                        explanation
                    }
                }
                .padding(PPSpacing.xl)
                .ppContentColumn()
            }
            .scrollIndicators(.hidden)

            footer
        }
    }

    private var topBar: some View {
        HStack(spacing: PPSpacing.md) {
            PPIconButton(systemName: "xmark", diameter: 36) { dismiss() }

            PPBadge(bank.title(for: quiz.category), tone: .neutral)
            PPBadge(quiz.difficulty.title, tone: .tinted(quiz.difficulty.accent))
                .layoutPriority(1)

            Spacer(minLength: PPSpacing.xs)

            timerPill

            saveButton
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.vertical, PPSpacing.md)
        .ppContentColumn()
    }

    private var timerPill: some View {
        HStack(spacing: PPSpacing.xs) {
            Image(systemName: "clock")
            Text(model.formattedQuestionTime)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(PPMotion.snappy, value: model.formattedQuestionTime)
        }
        .font(.ppMicro)
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(Color.ppMuted)
        .padding(.horizontal, PPSpacing.md)
        .frame(height: 30)
        .background(Color.ppSurface, in: .capsule)
        .layoutPriority(2)
        .accessibilityLabel("Time on this question")
    }

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
        .ppContentColumn()
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
        VStack(spacing: PPSpacing.md) {
            if model.skippedCount > 0 {
                skippedHint
            }

            HStack(spacing: PPSpacing.md) {
                PPIconButton(systemName: "chevron.left", diameter: 46) {
                    withAnimation { model.goBack() }
                }
                .disabled(model.isFirstQuestion)
                .opacity(model.isFirstQuestion ? 0.35 : 1)
                .accessibilityLabel("Previous question")

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
        }
        .padding(PPSpacing.xl)
        .ppContentColumn()
        .background(.ultraThinMaterial)
        .background(Color.ppGround.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ppBorder).frame(height: 1)
        }
        .animation(PPMotion.snappy, value: model.currentAnswer)
    }

    private var skippedHint: some View {
        Button {
            withAnimation { model.goToNextSkipped() }
        } label: {
            HStack(spacing: PPSpacing.xs) {
                Image(systemName: "arrow.uturn.backward")
                Text(model.skippedCount == 1
                     ? "1 question skipped · go back to it"
                     : "\(model.skippedCount) questions skipped · go back to them")
            }
            .font(.ppMicro)
            .lineLimit(1)
            .foregroundStyle(Color.ppAccent400)
            .padding(.horizontal, PPSpacing.md)
            .frame(height: 30)
            .background(Color.ppAccentSection, in: .capsule)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    if let quiz = QuizBank().quizzes(in: .aptitude).first {
        QuizView(quiz: quiz)
            .environment(QuizBank())
            .environment(QuizProgressStore.preview())
            .environment(SavedQuestionsStore.preview())
            .environment(StreakStore.preview())
            .environment(XPStore.preview())
    } else {
        Text("No quiz JSON bundled").ppScreenBackground()
    }
}
