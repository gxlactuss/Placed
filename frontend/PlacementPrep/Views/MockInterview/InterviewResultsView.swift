import SwiftUI

/// The debrief shown once a round finishes: a mark out of 10, what went wrong,
/// and what to work on.
///
/// Deliberately shaped like `QuizResultsView` — same ring, same "Areas to
/// improve" heading, same footer — because it answers the same question after a
/// different exercise, and a student shouldn't have to learn two results screens.
struct InterviewResultsView: View {

    let model: InterviewSessionModel
    let onAnotherRound: () -> Void
    let onClose: () -> Void

    /// Ring animates up from zero rather than snapping to the mark.
    @State private var animatedProgress: Double = 0
    /// Drives the one-shot staggered reveal of the cards below the ring.
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: PPSpacing.xl) {
                    header
                    if let feedback = model.feedback {
                        ring(feedback)
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
        Text("\(model.role) · Round debrief")
            .ppSectionLabelStyle()
            .multilineTextAlignment(.center)
            .padding(.top, PPSpacing.lg)
    }

    private func ring(_ feedback: InterviewFeedback) -> some View {
        PPRingProgress(progress: animatedProgress, tint: tint(for: feedback.rating)) {
            VStack(spacing: PPSpacing.xs) {
                Text("\(feedback.rating)").font(.ppStatFixed(44))
                Text("out of 10")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }
        }
        .padding(.vertical, PPSpacing.sm)
    }

    /// Same thresholds the quiz ring uses, so a colour means the same thing in
    /// both places.
    private func tint(for rating: Int) -> Color {
        switch rating {
        case 8...: .ppEasy
        case 5..<8: .ppAccent
        default: .ppHard
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

    /// What they actually got wrong, each with its correction. Empty is a real
    /// outcome — a clean round shows nothing here rather than an empty heading.
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

    /// `offset` continues the stagger across both lists, so the second one
    /// doesn't restart the animation from zero halfway down the screen.
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
        .background(.ultraThinMaterial)
        .background(Color.ppGround.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ppBorder).frame(height: 1)
        }
    }
}
