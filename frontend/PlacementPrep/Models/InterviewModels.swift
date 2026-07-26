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
    /// `InterviewMode.rawValue`. The backend parses it and stores it on the
    /// session, so follow-up turns stay in the same round.
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

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcribedAnswer = "transcribed_answer"
    }
}

/// Resume-derived material the round is tailored to. Everything optional — a
/// round with no context simply gets an untailored prompt.
struct InterviewContextPayload: Codable {
    var projectsText: String?
    var skills: String?
    var dsaProblem: String?
    var topic: String?

    var isEmpty: Bool {
        projectsText == nil && skills == nil && dsaProblem == nil && topic == nil
    }

    enum CodingKeys: String, CodingKey {
        case projectsText = "projects_text"
        case skills
        case dsaProblem = "dsa_problem"
        case topic
    }
}

/// Reply from `/api/interview/transcribe` — the text Whisper heard.
struct TranscriptionResponse: Codable {
    let text: String
}

struct InterviewAiResponse: Codable {
    let sessionId: Int
    let aiMessage: String
    let isFollowUp: Bool
    let interviewComplete: Bool
    /// The interviewer stopped the round itself, rather than it running its
    /// course — today, only when the candidate wasn't answering in good faith.
    ///
    /// Optional, not a defaulted `Bool`: the synthesized decoder ignores property
    /// defaults and throws on a missing key, so a deployed backend older than
    /// this field would fail to decode the whole response.
    let endedEarly: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case aiMessage = "ai_message"
        case isFollowUp = "is_follow_up"
        case interviewComplete = "interview_complete"
        case endedEarly = "ended_early"
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
