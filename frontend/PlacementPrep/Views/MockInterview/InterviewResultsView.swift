import SwiftUI

struct InterviewResultsView: View {

    let model: InterviewSessionModel
    let onAnotherRound: () -> Void
    let onClose: () -> Void

    @State private var animatedProgress: Double = 0
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: PPSpacing.xl) {
                    header
                    if let feedback = model.feedback {
                        ring(feedback)
                        rubric(feedback)
                        scoreTrend(feedback)
                        summary(feedback)
                        mistakes(feedback)
                        improvements(feedback)
                    } else if model.isLoadingFeedback {
                        loading
                    } else if let error = model.feedbackError {
                        errorState(error)
                    }
                }
                .padding(PPSpacing.xl)
                .ppContentColumn()
            }
            .scrollIndicators(.hidden)

            footer
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .onChange(of: model.feedback?.rating) { _, rating in
            guard let rating else { return }
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) {
                animatedProgress = Double(rating) / 10
            }
            revealed = true
        }
    }

    private var header: some View {
        VStack(spacing: PPSpacing.xs) {
            Text("\(model.role) · Round debrief")
                .ppSectionLabelStyle()
                .multilineTextAlignment(.center)
            roundReach
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
        }
        .padding(.top, PPSpacing.lg)
    }

    private var roundReach: Text {
        if let difficulty = model.difficulty {
            Text("^[\(model.answeredCount) question](inflect: true) · finished at \(difficulty.title)")
        } else {
            Text("^[\(model.answeredCount) question](inflect: true)")
        }
    }

    private func ring(_ feedback: InterviewFeedback) -> some View {
        PPRingProgress(progress: animatedProgress, tint: .ppScore(Double(feedback.rating))) {
            VStack(spacing: PPSpacing.xs) {
                Text("\(feedback.rating)").font(.ppStatFixed(44))
                Text("out of 10")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }
        }
        .padding(.vertical, PPSpacing.sm)
    }

    @ViewBuilder
    private func rubric(_ feedback: InterviewFeedback) -> some View {
        if let rubric = feedback.rubric {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                PPSectionHeader("Where the marks went")
                PPCard { InterviewRubricBreakdown(rubric: rubric, revealed: revealed) }
            }
            .opacity(revealed ? 1 : 0)
            .animation(PPMotion.settle.delay(0.2), value: revealed)
        }
    }

    @ViewBuilder
    private func scoreTrend(_ feedback: InterviewFeedback) -> some View {
        if feedback.answers.count > 1 {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                PPSectionHeader("Answer by answer")
                PPCard { InterviewScoreChart(answers: feedback.answers) }
            }
            .opacity(revealed ? 1 : 0)
            .animation(PPMotion.settle.delay(0.3), value: revealed)
        }
    }

    private func summary(_ feedback: InterviewFeedback) -> some View {
        PPCard(tone: .elevated) {
            Text(feedback.summary)
                .font(.ppBody)
                .foregroundStyle(Color.ppText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func mistakes(_ feedback: InterviewFeedback) -> some View {
        if !feedback.mistakes.isEmpty {
            section("What to correct", items: feedback.mistakes, dot: .ppHard, from: 0)
        }
    }

    @ViewBuilder
    private func improvements(_ feedback: InterviewFeedback) -> some View {
        if !feedback.improvements.isEmpty {
            section(
                "Areas to improve",
                items: feedback.improvements,
                dot: .ppMedium,
                from: feedback.mistakes.count
            )
        }
    }

    private func section(
        _ title: String,
        items: [String],
        dot: Color,
        from offset: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPSectionHeader(title)

            ForEach(Array(items.enumerated()), id: \.offset) { position, item in
                PPCard {
                    HStack(alignment: .top, spacing: PPSpacing.md) {
                        Circle()
                            .fill(dot)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        Text(item)
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppText)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 14)
                .animation(
                    PPMotion.settle.delay(0.25 + Double(offset + position) * 0.08),
                    value: revealed
                )
            }
        }
    }

    private var loading: some View {
        VStack(spacing: PPSpacing.md) {
            ProgressView().tint(Color.ppAccent400)
            Text("Marking your interview…")
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
        }
        .padding(.vertical, PPSpacing.xxl)
    }

    private func errorState(_ message: String) -> some View {
        PPCard {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                HStack(alignment: .top, spacing: PPSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.ppAccent400)
                    Text(message)
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Try again") { Task { await model.loadFeedback() } }
                    .buttonStyle(.ppInlineLink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: PPSpacing.md) {
            Button("Close") { onClose() }
                .buttonStyle(.ppSecondary)

            Button("Another round") { onAnotherRound() }
                .buttonStyle(.ppPrimary)
        }
        .padding(PPSpacing.xl)
        .ppContentColumn()
        .background(.ultraThinMaterial)
        .background(Color.ppGround.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ppBorder).frame(height: 1)
        }
    }
}
