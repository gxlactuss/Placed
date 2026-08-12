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

/// The debrief for a finished round, from `POST /api/interview/{id}/feedback`.
/// The backend caches it on the session, so asking twice is free.
/// `Equatable` so a view can react to the debrief arriving — that's the moment
/// the round's XP is settled, and it has to fire whether the mark came from the
/// first request or a retry after a failure.
struct InterviewFeedback: Codable, Equatable {
    /// Out of 10, against campus-placement expectations for the target role.
    let rating: Int
    let summary: String
    let improvements: [String]
    /// Answers that were wrong or incomplete, each carrying its correction.
    /// Legitimately empty when there weren't any.
    let mistakes: [String]
}

/// One row in the saved-interviews list, from `GET /api/interview`.
///
/// Deliberately not the full session: the list renders from this alone, so
/// opening the screen doesn't pull every transcript the student has ever
/// recorded.
/// `Hashable` so it can drive `navigationDestination(item:)` directly.
struct InterviewSummary: Codable, Identifiable, Hashable {
    let id: Int
    let targetRole: String
    /// `InterviewMode.rawValue`, or `nil` on sessions recorded before modes.
    let mode: String?
    let status: InterviewStatus
    /// Questions actually answered — how far the round really got.
    let answerCount: Int
    /// Only present once a debrief was generated for this round.
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
    /// The debrief as stored when the round finished. Read-only here — fetching
    /// a past interview never generates one, so an unmarked round shows none.
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
