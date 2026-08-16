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
    /// Which user this device's cache belongs to, so a different account signing
    /// in on the same device doesn't inherit the previous user's scores.
    private static let ownerKey = "quizBestScoresOwner"

    /// Set once `sync(userId:)` runs; `nil` disables network writes (previews and
    /// the pre-auth window), so mutations stay purely local until we're signed in.
    private var userId: Int?
    private let network = NetworkManager.shared

    /// TESTING ONLY — when true, every quiz reports as unlocked so any of them
    /// can be opened without clearing the one before it. Progress is still
    /// recorded normally, so flipping it either way loses no saved score.
    /// Ships `false`: the pass-to-unlock progression is the real behaviour.
    static let unlockAllForTesting = false

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

    /// Records a finished attempt: keeps the higher local best, and (when signed
    /// in) reports every attempt to the server so history + best stay in sync.
    func record(score: Int, correct: Int, total: Int, for quiz: Quiz) {
        if userId != nil {
            let attempt = QuizAttemptRequest(
                quizId: quiz.id,
                totalQuestions: total,
                correctAnswers: correct,
                scorePercentage: score
            )
            Task { try? await network.send(path: "/api/quiz/submit", method: .post, body: attempt) }
        }

        let previous = bestScores[quiz.id] ?? 0
        guard score > previous else { return }
        bestScores[quiz.id] = score
        persist()
    }

    // MARK: - Server sync

    /// Pulls this user's best scores from the server and reconciles with the
    /// local cache. On first sign-in for a user, local-only progress is pushed up
    /// (migration); a different user's cache is discarded first so nothing leaks.
    /// Offline: keeps the local cache untouched.
    func sync(userId: Int) async {
        if let owner = defaults.object(forKey: Self.ownerKey) as? Int, owner != userId {
            bestScores = [:]
            persist()
        }
        self.userId = userId
        defaults.set(userId, forKey: Self.ownerKey)

        do {
            let items: [QuizProgressItem] = try await network.request(path: "/api/quiz/progress")
            var merged = Dictionary(items.map { ($0.quizId, $0.bestScore) }, uniquingKeysWith: max)

            // Push any local best the server doesn't have yet (legacy migration).
            for (quizId, localBest) in bestScores where localBest > (merged[quizId] ?? -1) {
                let attempt = QuizAttemptRequest(
                    quizId: quizId, totalQuestions: 0, correctAnswers: 0, scorePercentage: localBest
                )
                try? await network.send(path: "/api/quiz/submit", method: .post, body: attempt)
                merged[quizId] = localBest
            }

            bestScores = merged
            persist()
        } catch {
            // Offline / server down — keep the local cache as-is.
        }
    }

    /// Clears the in-memory cache on sign-out (server remains the source of truth).
    func clear() {
        userId = nil
        bestScores = [:]
        persist()
    }

    /// Pairs each quiz with its unlock state and its position in the list.
    ///
    /// The rule: the first quiz is always open, and every later one opens when
    /// the quiz immediately before it has been passed. Walking the ordered list
    /// once means a gap cannot be skipped — failing quiz 3 leaves 4 onward shut
    /// even if 4 was somehow passed earlier.
    ///
    /// The chain is only as long as the array handed in, which is why the caller
    /// passes **one track** (see `QuizBank.quizzes(in:track:)`) rather than a
    /// whole category. Chaining every CS quiz into one line would put seven
    /// Operating Systems quizzes between a student and the first DBMS one.
    func listItems(for quizzes: [Quiz]) -> [QuizListItem] {
        var previousPassed = true

        return quizzes.enumerated().map { position, quiz in
            // Role quizzes sit outside the chain. A student sees exactly one of
            // them, so there is no earlier quiz to have passed — walking the
            // chain would leave it permanently shut.
            let chained = quiz.category != .role
            let item = QuizListItem(
                quiz: quiz,
                number: position + 1,
                isUnlocked: Self.unlockAllForTesting || !chained || previousPassed,
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
