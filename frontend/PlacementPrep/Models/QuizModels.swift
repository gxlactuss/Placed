import Foundation

enum QuizTopic: String, Codable, CaseIterable, Identifiable {
    case csFundamentals = "cs_fundamentals"
    case dsa = "dsa"
    case aptitude = "aptitude"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .csFundamentals: return "CS Fundamentals"
        case .dsa: return "DSA"
        case .aptitude: return "Aptitude"
        }
    }
}

enum QuizDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy, medium, hard
    var id: String { rawValue }
}

struct QuizQuestionOption: Codable, Identifiable {
    let id: String
    let text: String
}

struct QuizQuestion: Codable, Identifiable {
    let id: String
    let topic: QuizTopic
    let difficulty: QuizDifficulty
    let prompt: String
    let options: [QuizQuestionOption]
}

struct QuizAnswer: Codable {
    let questionId: String
    let selectedOptionId: String

    enum CodingKeys: String, CodingKey {
        case questionId = "question_id"
        case selectedOptionId = "selected_option_id"
    }
}

struct QuizSubmitRequest: Codable {
    let topic: QuizTopic
    let difficulty: QuizDifficulty
    let answers: [QuizAnswer]
}

struct QuizQuestionFeedback: Codable, Identifiable {
    var id: String { questionId }
    let questionId: String
    let correct: Bool
    let correctOptionId: String
    let explanation: String

    enum CodingKeys: String, CodingKey {
        case questionId = "question_id"
        case correct
        case correctOptionId = "correct_option_id"
        case explanation
    }
}

struct QuizResult: Codable, Identifiable {
    let id: Int
    let topic: QuizTopic
    let difficulty: QuizDifficulty
    let totalQuestions: Int
    let correctAnswers: Int
    let scorePercentage: Double
    let completedAt: Date
    let feedback: [QuizQuestionFeedback]

    enum CodingKeys: String, CodingKey {
        case id, topic, difficulty
        case totalQuestions = "total_questions"
        case correctAnswers = "correct_answers"
        case scorePercentage = "score_percentage"
        case completedAt = "completed_at"
        case feedback
    }
}
