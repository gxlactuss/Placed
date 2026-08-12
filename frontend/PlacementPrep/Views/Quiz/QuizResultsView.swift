import SwiftUI

/// Score summary shown once the last question is answered.
struct QuizResultsView: View {

    let model: QuizSessionModel
    let onRetry: () -> Void
    let onClose: () -> Void

    /// Ring animates from zero on appear rather than snapping to the score.
    @State private var animatedProgress: Double = 0
    /// Drives the one-shot staggered reveal of the cards below the ring.
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: PPSpacing.xl) {
                    header
                    ring
                    verdict
                    statRow
                    aiSummary
                    weakAreas
                    recommendations
                }
                .padding(PPSpacing.xl)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .foregroundStyle(Color.ppText)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) {
                animatedProgress = Double(model.scorePercentage) / 100
            }
            revealed = true
        }
        // Fires once per attempt — the model guards against a second request,
        // and a retake resets it.
        .task { await model.loadSummary() }
    }

    private var header: some View {
        Text("\(model.quiz.category.title) · \(model.quiz.title)")
            .ppSectionLabelStyle()
            .multilineTextAlignment(.center)
            .padding(.top, PPSpacing.lg)
    }

    /// States plainly whether the next quiz just unlocked — the single most
    /// important thing on this screen once progression is in play.
    private var verdict: some View {
        let passed = model.hasPassed

        return PPCard(tone: .elevated) {
            HStack(spacing: PPSpacing.md) {
                Image(systemName: passed ? "lock.open.fill" : "arrow.counterclockwise")
                    .foregroundStyle(passed ? Color.ppEasy : Color.ppMedium)

                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    Text(passed ? "Passed — next quiz unlocked" : "Not passed yet")
                        .font(.ppBodyMedium)
                    Text(passed
                         ? "You cleared the \(model.quiz.passPercentage)% pass mark."
                         : "Score \(model.quiz.passPercentage)% or higher to unlock the next quiz.")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var ring: some View {
        PPRingProgress(progress: animatedProgress, tint: ringTint) {
            VStack(spacing: PPSpacing.xs) {
                Text("\(model.scorePercentage)%").font(.ppStatFixed(44))
                Text("\(model.correctCount) / \(model.questions.count) correct")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }
        }
        .padding(.vertical, PPSpacing.sm)
    }

    private var ringTint: Color {
        switch model.scorePercentage {
        case 80...: .ppEasy
        case 50..<80: .ppAccent
        default: .ppHard
        }
    }

    private var statRow: some View {
        HStack(spacing: PPSpacing.md) {
            PPStatTile(value: model.formattedTotalTime, label: "Time")
            PPStatTile(
                value: "\(model.correctCount)/\(model.questions.count)",
                label: "Correct",
                valueColor: .ppEasy
            )
            // The real payout, not what the score is nominally worth: a retake
            // of a quiz already cleared at 70% earns nothing, and claiming
            // otherwise would make the number on Home look broken.
            PPStatTile(
                value: model.xpEarned > 0 ? "+\(model.xpEarned)" : "—",
                label: "XP",
                valueColor: model.xpEarned > 0 ? .ppAccent : .ppMuted
            )
        }
    }

    /// The part of this screen that says something the student couldn't work out
    /// themselves. Everything else here is arithmetic on their own answers; this
    /// is the pattern behind them and what to do about it.
    @ViewBuilder
    private var aiSummary: some View {
        if let summary = model.summary {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                PPSectionHeader("What this tells you")

                PPCard(tone: .elevated) {
                    VStack(alignment: .leading, spacing: PPSpacing.md) {
                        Text(summary.summary)
                            .font(.ppBody)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(Array(summary.focus.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: PPSpacing.md) {
                                Circle()
                                    .fill(Color.ppAccent400)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 7)
                                Text(item)
                                    .font(.ppCaption)
                                    .foregroundStyle(Color.ppMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if model.isLoadingSummary {
            HStack(spacing: PPSpacing.md) {
                ProgressView().tint(Color.ppAccent400)
                Text("Working out what to focus on…")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                Spacer(minLength: 0)
            }
        } else if let error = model.summaryError {
            // Deliberately quiet: the score, the answers and the per-question
            // explanations are all already on screen and all still correct. This
            // is the one extra layer, and losing it isn't worth an alarm.
            Text(error)
                .font(.ppMicro)
                .foregroundStyle(Color.ppMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var weakAreas: some View {
        if !model.weakAreas.isEmpty {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                PPSectionHeader("Areas to improve")

                ForEach(Array(model.weakAreas.enumerated()), id: \.element.concept) { position, area in
                    PPCard {
                        HStack(spacing: PPSpacing.md) {
                            Circle()
                                .fill(area.missed >= area.total ? Color.ppHard : Color.ppMedium)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                                Text(area.concept).font(.ppHeadline)
                                Text("Missed \(area.missed) of \(area.total)")
                                    .font(.ppCaption)
                                    .foregroundStyle(Color.ppMuted)
                            }

                            Spacer()
                        }
                    }
                    // One-shot staggered entrance: opacity + a small offset,
                    // 80ms apart. Nothing runs after the cards settle.
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 14)
                    .animation(
                        PPMotion.settle.delay(0.25 + Double(position) * 0.08),
                        value: revealed
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var recommendations: some View {
        if let focus = model.weakAreas.first?.concept {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                PPSectionHeader("Recommended for you")

                PPCard {
                    HStack(spacing: PPSpacing.lg) {
                        PPIconTile(systemName: "book.closed.fill")

                        VStack(alignment: .leading, spacing: PPSpacing.xs) {
                            Text("\(focus), Zero to Hero").font(.ppHeadline)
                            PPBadge(focus, tone: .accent)
                        }

                        Spacer()

                        Text("Start")
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppAccent400)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: PPSpacing.md) {
            Button("Close") { onClose() }
                .buttonStyle(.ppSecondary)

            Button("Retry quiz") {
                animatedProgress = 0
                onRetry()
            }
            .buttonStyle(.ppPrimary)
        }
        .padding(PPSpacing.xl)
        .background(.ultraThinMaterial)
        .background(Color.ppGround.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ppBorder).frame(height: 1)
        }
    }
}

#Preview {
    if let quiz = QuizBank().quizzes(in: .aptitude).first {
        let model = QuizSessionModel(quiz: quiz)
        model.answer(quiz.questions[0].correctOptionID)
        model.advance()
        model.finish()
        return AnyView(
            QuizResultsView(model: model, onRetry: {}, onClose: {})
                .ppScreenBackground()
        )
    } else {
        return AnyView(Text("No quiz JSON bundled"))
    }
}
