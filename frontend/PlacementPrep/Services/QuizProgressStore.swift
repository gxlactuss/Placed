import Foundation

@MainActor
@Observable
final class QuizProgressStore {

    private static let defaultsKey = "quizBestScores"
    private static let ownerKey = "quizBestScoresOwner"

    private var userId: Int?
    private let network = NetworkManager.shared

    static let unlockAllForTesting = false

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
        }
    }

    func clear() {
        userId = nil
        bestScores = [:]
        persist()
    }

    func listItems(for quizzes: [Quiz]) -> [QuizListItem] {
        var previousPassed = true

        return quizzes.enumerated().map { position, quiz in
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

    func passedCount(in quizzes: [Quiz]) -> Int {
        quizzes.count { hasPassed($0) }
    }

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
    static func preview(passed: [String: Int] = [:]) -> QuizProgressStore {
        let store = QuizProgressStore(
            defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        )
        store.bestScores = passed
        return store
    }
}
