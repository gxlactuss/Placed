import Foundation

/// A finished, on-device-scored quiz attempt sent to `POST /api/quiz/submit`.
struct QuizAttemptRequest: Codable {
    let quizId: String
    let totalQuestions: Int
    let correctAnswers: Int
    let scorePercentage: Int

    enum CodingKeys: String, CodingKey {
        case quizId = "quiz_id"
        case totalQuestions = "total_questions"
        case correctAnswers = "correct_answers"
        case scorePercentage = "score_percentage"
    }
}

/// Best score for a quiz, from `GET /api/quiz/progress`.
struct QuizProgressItem: Codable {
    let quizId: String
    let bestScore: Int

    enum CodingKeys: String, CodingKey {
        case quizId = "quiz_id"
        case bestScore = "best_score"
    }
}

/// Body for `POST /api/dsa/solved`.
struct SolvedSlugRequest: Codable {
    let slug: String
}
