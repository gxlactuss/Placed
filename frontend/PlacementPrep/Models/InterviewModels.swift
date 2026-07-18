import Foundation

enum InterviewStatus: String, Codable {
    case inProgress = "in_progress"
    case completed
    case abandoned
}

struct InterviewTurn: Codable, Identifiable {
    var id: Date { at }
    let speaker: String // "ai" | "user"
    let text: String
    let at: Date
}

struct InterviewStartRequest: Codable {
    let targetRole: String

    enum CodingKeys: String, CodingKey {
        case targetRole = "target_role"
    }
}

struct InterviewAnswerSubmitRequest: Codable {
    let sessionId: Int
    let transcribedAnswer: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcribedAnswer = "transcribed_answer"
    }
}

struct InterviewAiResponse: Codable {
    let sessionId: Int
    let aiMessage: String
    let isFollowUp: Bool
    let interviewComplete: Bool

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case aiMessage = "ai_message"
        case isFollowUp = "is_follow_up"
        case interviewComplete = "interview_complete"
    }
}

struct InterviewSession: Codable, Identifiable {
    let id: Int
    let targetRole: String
    let status: InterviewStatus
    let transcript: [InterviewTurn]
    let overallFeedback: String?
    let startedAt: Date
    let endedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case targetRole = "target_role"
        case status, transcript
        case overallFeedback = "overall_feedback"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}
