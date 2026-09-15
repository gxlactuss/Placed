import Foundation

enum InterviewStatus: String, Codable {
    case inProgress = "in_progress"
    case completed
    case abandoned
}

struct InterviewTurn: Codable, Identifiable {
    var id: Date { at }
    let speaker: String
    let text: String
    let at: Date
}

struct InterviewStartRequest: Codable {
    let targetRole: String
    let mode: String
    let context: InterviewContextPayload?

    enum CodingKeys: String, CodingKey {
        case targetRole = "target_role"
        case mode, context
    }
}

struct InterviewAnswerSubmitRequest: Codable {
    let sessionId: Int
    let transcribedAnswer: String
    let thinkSeconds: Double?
    let speakingSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcribedAnswer = "transcribed_answer"
        case thinkSeconds = "think_seconds"
        case speakingSeconds = "speaking_seconds"
    }
}

enum InterviewDifficulty: Int, CaseIterable {
    case beginner = 1
    case foundation
    case intermediate
    case advanced
    case expert

    init(level: Int) {
        let lowest = Self.beginner.rawValue, highest = Self.expert.rawValue
        self = Self(rawValue: min(max(level, lowest), highest)) ?? .intermediate
    }

    var title: String {
        switch self {
        case .beginner: "Beginner"
        case .foundation: "Foundation"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        case .expert: "Expert"
        }
    }
}

struct DSAProblemPool: Codable {
    var easy: [String]
    var medium: [String]
    var hard: [String]
}

struct InterviewContextPayload: Codable {
    var projectsText: String?
    var skills: String?
    var dsaProblems: DSAProblemPool?
    var topic: String?

    var isEmpty: Bool {
        projectsText == nil && skills == nil && dsaProblems == nil && topic == nil
    }

    enum CodingKeys: String, CodingKey {
        case projectsText = "projects_text"
        case skills
        case dsaProblems = "dsa_problems"
        case topic
    }
}

struct TranscriptionResponse: Codable {
    let text: String
}

struct InterviewAiResponse: Codable {
    let sessionId: Int
    let aiMessage: String
    let isFollowUp: Bool
    let interviewComplete: Bool
    let endedEarly: Bool?
    let questionNumber: Int?
    let difficulty: Int?
    let calibrating: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case aiMessage = "ai_message"
        case isFollowUp = "is_follow_up"
        case interviewComplete = "interview_complete"
        case endedEarly = "ended_early"
        case questionNumber = "question_number"
        case difficulty, calibrating
    }
}

struct InterviewFeedback: Codable, Equatable {
    let rating: Int
    let summary: String
    let improvements: [String]
    let mistakes: [String]
}

struct InterviewSummary: Codable, Identifiable, Hashable {
    let id: Int
    let targetRole: String
    let mode: String?
    let status: InterviewStatus
    let answerCount: Int
    let rating: Int?
    let startedAt: Date
    let endedAt: Date?

    var round: InterviewMode? { mode.flatMap(InterviewMode.init(rawValue:)) }

    enum CodingKeys: String, CodingKey {
        case id, mode, status, rating
        case targetRole = "target_role"
        case answerCount = "answer_count"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

struct InterviewSession: Codable, Identifiable {
    let id: Int
    let targetRole: String
    let mode: String?
    let status: InterviewStatus
    let transcript: [InterviewTurn]
    let feedback: InterviewFeedback?
    let startedAt: Date
    let endedAt: Date?

    var round: InterviewMode? { mode.flatMap(InterviewMode.init(rawValue:)) }

    enum CodingKeys: String, CodingKey {
        case id, mode, status, transcript, feedback
        case targetRole = "target_role"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}
