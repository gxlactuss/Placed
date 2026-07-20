import Foundation

/// Records the best score for each quiz and derives which quizzes are unlocked.
///
/// Only the best score is kept, not a full attempt history: unlocking depends
/// solely on whether a quiz has ever been passed, and retaking a quiz should
/// never re-lock what it already opened.
@MainActor
@Observable
final class QuizProgressStore {

    private static let defaultsKey = "quizBestScores"

    /// Quiz id -> best score percentage.
    private(set) var bestScores: [String: Int]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.bestScores = decoded
        } else {
            self.bestScores = [:]
        }
    }

    func bestScore(for quiz: Quiz) -> Int? { bestScores[quiz.id] }

    func hasPassed(_ quiz: Quiz) -> Bool {
        (bestScores[quiz.id] ?? 0) >= quiz.passPercentage
    }

    /// Records an attempt, keeping whichever score is higher.
    func record(score: Int, for quiz: Quiz) {
        let previous = bestScores[quiz.id] ?? 0
        guard score > previous else { return }
        bestScores[quiz.id] = score
        persist()
    }

    /// Pairs each quiz with its unlock state.
    ///
    /// The rule: the first quiz in a category is always open, and every later
    /// one opens when the quiz immediately before it has been passed. Walking
    /// the ordered list once means a gap cannot be skipped — failing quiz 3
    /// leaves 4 onward shut even if 4 was somehow passed earlier.
    func listItems(for quizzes: [Quiz]) -> [QuizListItem] {
        var previousPassed = true

        return quizzes.map { quiz in
            let item = QuizListItem(
                quiz: quiz,
                isUnlocked: previousPassed,
                bestScore: bestScores[quiz.id]
            )
            previousPassed = hasPassed(quiz)
            return item
        }
    }

    /// How many quizzes in the given list have been passed.
    func passedCount(in quizzes: [Quiz]) -> Int {
        quizzes.count { hasPassed($0) }
    }

    /// Wipes progress for a category — useful in settings, and in previews.
    func reset(_ quizzes: [Quiz]) {
        for quiz in quizzes { bestScores.removeValue(forKey: quiz.id) }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(bestScores) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

extension QuizProgressStore {
    /// In-memory store for previews, so previews never touch real defaults.
    static func preview(passed: [String: Int] = [:]) -> QuizProgressStore {
        let store = QuizProgressStore(
            defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        )
        store.bestScores = passed
        return store
    }
}
