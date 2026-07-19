import Foundation
import Observation

/// Drives one run through a quiz: answering, scoring and the per-question timer.
///
/// Answers commit once and cannot be changed, so `answers` is keyed by question
/// index and only ever written on the first tap for that question.
@MainActor
@Observable
final class QuizSessionModel {

    let topic: QuizTopic
    let difficulty: QuizDifficulty
    let questions: [SampleQuizQuestion]

    private(set) var index = 0
    private(set) var answers: [Int: String] = [:]
    private(set) var secondsOnQuestion = 0
    private(set) var totalSeconds = 0
    private(set) var isFinished = false

    /// A cancellable Task rather than a `Timer`: the model is main-actor isolated,
    /// and a `deinit` cannot reach isolated state to invalidate a Timer. The task
    /// holds `self` weakly and exits on its own if the model goes away.
    private var ticker: Task<Void, Never>?

    init(topic: QuizTopic, difficulty: QuizDifficulty) {
        self.topic = topic
        self.difficulty = difficulty
        self.questions = SampleData.questions(topic: topic, difficulty: difficulty)
    }

    // MARK: - Derived state

    var current: SampleQuizQuestion { questions[index] }

    var progress: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(index) / Double(questions.count)
    }

    var isLastQuestion: Bool { index == questions.count - 1 }

    /// The answer committed for the current question, if any.
    var currentAnswer: String? { answers[index] }

    var correctCount: Int {
        answers.reduce(into: 0) { total, entry in
            if questions[entry.key].correctLetter == entry.value { total += 1 }
        }
    }

    var scorePercentage: Int {
        guard !questions.isEmpty else { return 0 }
        return Int((Double(correctCount) / Double(questions.count) * 100).rounded())
    }

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
            if answer == nil || answer != question.correctLetter {
                missed[question.concept, default: 0] += 1
            }
        }

        return missed
            .filter { $0.value > 0 }
            .map { (concept: $0.key, missed: $0.value, total: totals[$0.key] ?? 0) }
            .sorted { $0.missed > $1.missed }
    }

    // MARK: - Actions

    func answer(_ letter: String) {
        // One-shot commit: ignore taps once this question is resolved.
        guard answers[index] == nil else { return }
        answers[index] = letter
    }

    func advance() {
        if isLastQuestion {
            finish()
        } else {
            index += 1
            secondsOnQuestion = 0
        }
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
        answers = [:]
        secondsOnQuestion = 0
        totalSeconds = 0
        isFinished = false
        startTimer()
    }
}
