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
                    statRow
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
    }

    private var header: some View {
        Text("Quiz complete · \(model.topic.displayName) · \(model.difficulty.rawValue.capitalized)")
            .ppSectionLabelStyle()
            .multilineTextAlignment(.center)
            .padding(.top, PPSpacing.lg)
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
            PPStatTile(value: "+\(model.correctCount * 10)", label: "XP")
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
    let model = QuizSessionModel(topic: .csFundamentals, difficulty: .medium)
    model.answer("C")
    model.advance()
    model.answer("A")
    model.finish()

    return QuizResultsView(model: model, onRetry: {}, onClose: {})
        .ppScreenBackground()
}
