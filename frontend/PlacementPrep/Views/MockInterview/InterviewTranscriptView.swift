import SwiftUI

struct InterviewTranscriptView: View {

    let summaryID: Int

    @State private var session: InterviewSession?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let session {
                content(session)
            } else if isLoading {
                ProgressView().tint(Color.ppAccent400)
            } else if let errorMessage {
                errorState(errorMessage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .navigationTitle(session?.round?.title ?? "Interview")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func content(_ session: InterviewSession) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: PPSpacing.xl) {
                    header(session)
                    if let feedback = session.feedback {
                        debrief(feedback) { answer in
                            withAnimation(PPMotion.settle) {
                                scroller.scrollTo(answerAnchor(answer.answer), anchor: .center)
                            }
                        }
                    }
                    transcript(session)
                }
                .padding(PPSpacing.xl)
                .ppContentColumn()
            }
            .scrollIndicators(.hidden)
        }
    }

    private func answerAnchor(_ number: Int) -> String { "answer-\(number)" }

    private func header(_ session: InterviewSession) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.xs) {
            Text(session.roleLine).font(.ppTitle)
            Text(session.startedAt.formatted(date: .long, time: .shortened))
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
            if session.status == .abandoned {
                PPBadge("The interviewer ended this round early", tone: .neutral)
                    .padding(.top, PPSpacing.xs)
            }
        }
    }

    private func debrief(
        _ feedback: InterviewFeedback,
        onSelectAnswer: @escaping (AnswerScore) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPSectionHeader("Debrief")

            PPCard(tone: .elevated) {
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    HStack(alignment: .firstTextBaseline, spacing: PPSpacing.sm) {
                        Text("\(feedback.rating)")
                            .font(.ppStatFixed(30))
                            .foregroundStyle(Color.ppScore(Double(feedback.rating), middle: .ppAccent400))
                        Text("out of 10")
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                    }
                    Text(feedback.summary)
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let rubric = feedback.rubric {
                PPCard { InterviewRubricBreakdown(rubric: rubric) }
            }

            if feedback.answers.count > 1 {
                PPCard { InterviewScoreChart(answers: feedback.answers, onSelect: onSelectAnswer) }
            }

            bullets("What to correct", feedback.mistakes, dot: .ppHard)
            bullets("Areas to improve", feedback.improvements, dot: .ppMedium)
        }
    }

    @ViewBuilder
    private func bullets(_ title: String, _ items: [String], dot: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text(title)
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: PPSpacing.md) {
                        Circle().fill(dot).frame(width: 6, height: 6).padding(.top, 6)
                        Text(item)
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func transcript(_ session: InterviewSession) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPSectionHeader("Transcript")

            ForEach(numberedTurns(session.transcript), id: \.offset) { offset, turn, answerNumber in
                let isUser = turn.isCandidate
                VStack(alignment: .trailing, spacing: PPSpacing.sm) {
                    HStack {
                        if isUser { Spacer(minLength: PPSpacing.xxl) }
                        Text(turn.text)
                            .font(.ppBody)
                            .foregroundStyle(isUser ? Color.ppOnAccent : Color.ppText)
                            .padding(.horizontal, PPSpacing.lg)
                            .padding(.vertical, PPSpacing.md)
                            .background(
                                isUser ? Color.ppAccent : Color.ppSurface,
                                in: .rect(cornerRadius: PPRadius.lg)
                            )
                            .overlay {
                                if !isUser {
                                    RoundedRectangle(cornerRadius: PPRadius.lg)
                                        .stroke(Color.ppBorder, lineWidth: 1)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        if !isUser { Spacer(minLength: PPSpacing.xxl) }
                    }
                    if let answerNumber, let score = session.feedback?.score(forAnswer: answerNumber) {
                        answerScore(score)
                    }
                }
                .id(answerNumber.map(answerAnchor) ?? "turn-\(offset)")
            }
        }
    }

    private func numberedTurns(
        _ turns: [InterviewTurn]
    ) -> [(offset: Int, turn: InterviewTurn, answerNumber: Int?)] {
        var answered = 0
        return turns.enumerated().map { offset, turn in
            guard turn.isCandidate else { return (offset, turn, nil) }
            answered += 1
            return (offset, turn, answered)
        }
    }

    private func answerScore(_ score: AnswerScore) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PPSpacing.sm) {
            Spacer(minLength: PPSpacing.xxl)
            if !score.note.isEmpty {
                Text(score.note)
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InterviewScoreChip(score: score.score)
        }
        .accessibilityElement(children: .combine)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: PPSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.ppAccent400)
            Text(message)
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { Task { await load() } }
                .buttonStyle(PPButtonStyle(variant: .secondary, expands: false))
        }
        .padding(PPSpacing.xxl)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            session = try await NetworkManager.shared.request(path: "/api/interview/\(summaryID)")
        } catch {
            errorMessage = "Couldn't open that interview. Check your connection and try again."
        }
    }
}
