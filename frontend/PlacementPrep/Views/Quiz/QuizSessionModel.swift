import Foundation
import Observation

/// Drives one run through a quiz: answering, scoring and the per-question timer.
///
/// Answers commit once and cannot be changed, so `answers` is keyed by question
/// index and only ever written on the first tap for that question.
@MainActor
@Observable
final class QuizSessionModel {

    let quiz: Quiz

    private(set) var index = 0
    /// The furthest question reached this run. Stepping back with `goBack()`
    /// must not rewind the progress bar — the ground covered is still covered —
    /// so the bar tracks this rather than `index`.
    private(set) var furthestReached = 0
    private(set) var answers: [Int: String] = [:]
    private(set) var secondsOnQuestion = 0
    private(set) var totalSeconds = 0
    private(set) var isFinished = false

    /// A cancellable Task rather than a `Timer`: the model is main-actor isolated,
    /// and a `deinit` cannot reach isolated state to invalidate a Timer. The task
    /// holds `self` weakly and exits on its own if the model goes away.
    private var ticker: Task<Void, Never>?

    // MARK: - Debrief

    private(set) var summary: QuizSummaryResponse?
    private(set) var isLoadingSummary = false
    private(set) var summaryError: String?

    /// Asks the backend to explain the result rather than restate it.
    ///
    /// The only network call in this model, and it happens once, after the last
    /// question — scoring stays entirely on-device, so a student with no
    /// connection still gets their score, their answers and their explanations.
    /// Only this extra layer is missing.
    func loadSummary() async {
        guard summary == nil, !isLoadingSummary else { return }
        isLoadingSummary = true
        summaryError = nil
        defer { isLoadingSummary = false }

        let missed = questions.enumerated().compactMap { position, question -> MissedQuestionPayload? in
            let chosen = answers[position]
            guard chosen != question.correctOptionID else { return nil }
            return MissedQuestionPayload(
                prompt: question.prompt,
                chosenText: chosen.flatMap { id in question.options.first { $0.id == id }?.text },
                correctText: question.options.first { $0.id == question.correctOptionID }?.text ?? "",
                concept: question.concept
            )
        }

        do {
            summary = try await NetworkManager.shared.request(
                path: "/api/quiz/summary",
                method: .post,
                body: QuizSummaryRequestPayload(
                    quizTitle: quiz.title,
                    subject: quiz.subject?.title ?? quiz.category.title,
                    scorePercentage: scorePercentage,
                    correctCount: correctCount,
                    totalQuestions: questions.count,
                    missed: missed
                )
            )
        } catch {
            summaryError = "Couldn't load your summary. Your score and answers above are unaffected."
        }
    }

    private func resetSummary() {
        summary = nil
        summaryError = nil
        isLoadingSummary = false
    }

    init(quiz: Quiz) {
        self.quiz = quiz
    }

    // MARK: - Derived state

    var questions: [Question] { quiz.questions }
    var current: Question { questions[index] }

    var progress: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(furthestReached) / Double(questions.count)
    }

    var isLastQuestion: Bool { index == questions.count - 1 }

    var isFirstQuestion: Bool { index == 0 }

    /// The answer committed for the current question, if any.
    var currentAnswer: String? { answers[index] }

    /// Questions walked past without an answer. Going back to them is the whole
    /// point of `goBack()`, so the footer can say how many are still waiting.
    var skippedCount: Int {
        questions.indices.count { $0 != index && answers[$0] == nil && $0 < furthestReached }
    }

    /// Whether every question has an answer — the cue that "Finish" is safe to
    /// press without leaving marks on the table.
    var isFullyAnswered: Bool { answers.count == questions.count }

    var correctCount: Int {
        answers.reduce(into: 0) { total, entry in
            if questions[entry.key].correctOptionID == entry.value { total += 1 }
        }
    }

    var scorePercentage: Int {
        guard !questions.isEmpty else { return 0 }
        return Int((Double(correctCount) / Double(questions.count) * 100).rounded())
    }

    /// Whether this run cleared the quiz's pass mark — the signal that unlocks
    /// the next quiz in the category.
    var hasPassed: Bool { scorePercentage >= quiz.passPercentage }

    var formattedTotalTime: String {
        String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var formattedQuestionTime: String {
        String(format: "%02d:%02d", secondsOnQuestion / 60, secondsOnQuestion % 60)
    }

    /// Concepts the user got wrong, most-missed first — feeds "Areas to improve".
    var weakAreas: [(concept: String, missed: Int, total: Int)] {
        var missed: [String: Int] = [:]
        var totals: [String: Int] = [:]

        for (questionIndex, question) in questions.enumerated() {
            totals[question.concept, default: 0] += 1
            let answer = answers[questionIndex]
            if answer == nil || answer != question.correctOptionID {
                missed[question.concept, default: 0] += 1
            }
        }

        return missed
            .filter { $0.value > 0 }
            .map { (concept: $0.key, missed: $0.value, total: totals[$0.key] ?? 0) }
            .sorted { $0.missed > $1.missed }
    }

    // MARK: - Actions

    func answer(_ optionID: String) {
        // One-shot commit: ignore taps once this question is resolved.
        guard answers[index] == nil else { return }
        answers[index] = optionID
    }

    func advance() {
        if isLastQuestion {
            finish()
        } else {
            move(to: index + 1)
        }
    }

    /// Steps back one question.
    ///
    /// This is not a retake: an answer already committed stays committed and
    /// still shows its verdict (see `answer(_:)`), so revisiting a resolved
    /// question is read-only. What it buys is the skipped ones — a question
    /// walked past unanswered is still open, and can be answered on the way
    /// back.
    func goBack() {
        guard !isFirstQuestion else { return }
        move(to: index - 1)
    }

    /// Jumps straight to the nearest unanswered question, wrapping around the
    /// end — the "3 skipped" shortcut in the footer.
    func goToNextSkipped() {
        guard questions.count > 1 else { return }
        let order = (1..<questions.count).map { (index + $0) % questions.count }
        guard let target = order.first(where: { answers[$0] == nil }) else { return }
        move(to: target)
    }

    private func move(to target: Int) {
        guard questions.indices.contains(target) else { return }
        index = target
        furthestReached = max(furthestReached, target)
        secondsOnQuestion = 0
    }

    func startTimer() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !self.isFinished, !Task.isCancelled else { return }
                self.secondsOnQuestion += 1
                self.totalSeconds += 1
            }
        }
    }

    func stopTimer() {
        ticker?.cancel()
        ticker = nil
    }

    func finish() {
        isFinished = true
        stopTimer()
    }

    func restart() {
        index = 0
        furthestReached = 0
        answers = [:]
        secondsOnQuestion = 0
        totalSeconds = 0
        isFinished = false
        // A retake is a different attempt, so last attempt's debrief must not
        // survive into it.
        resetSummary()
        startTimer()
    }
}

// MARK: - Wire types

/// One question the student got wrong. Carries the question itself, not just its
/// concept tag — a summary written from tags alone can only restate the tags.
struct MissedQuestionPayload: Encodable {
    let prompt: String
    /// `nil` when the timer ran out and nothing was picked.
    let chosenText: String?
    let correctText: String
    let concept: String

    enum CodingKeys: String, CodingKey {
        case prompt, concept
        case chosenText = "chosen_text"
        case correctText = "correct_text"
    }
}

struct QuizSummaryRequestPayload: Encodable {
    let quizTitle: String
    let subject: String
    let scorePercentage: Int
    let correctCount: Int
    let totalQuestions: Int
    let missed: [MissedQuestionPayload]

    enum CodingKeys: String, CodingKey {
        case subject, missed
        case quizTitle = "quiz_title"
        case scorePercentage = "score_percentage"
        case correctCount = "correct_count"
        case totalQuestions = "total_questions"
    }
}

/// Reply from `/api/quiz/summary` — the pattern behind the wrong answers, and
/// what to revise. `focus` is legitimately empty after a clean sweep.
struct QuizSummaryResponse: Decodable {
    let summary: String
    let focus: [String]
}
