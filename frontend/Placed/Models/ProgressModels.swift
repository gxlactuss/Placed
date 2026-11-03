import Foundation

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

struct QuizProgressItem: Codable {
    let quizId: String
    let bestScore: Int

    enum CodingKeys: String, CodingKey {
        case quizId = "quiz_id"
        case bestScore = "best_score"
    }
}

struct SolvedSlugRequest: Codable {
    let slug: String
}
