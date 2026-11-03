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
    let level: Int?
    let accuracy: Int?
    let ease: Int?

    var isCandidate: Bool { speaker == "user" }
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
    var company: String?

    var isEmpty: Bool {
        projectsText == nil && skills == nil && dsaProblems == nil && topic == nil && company == nil
    }

    enum CodingKeys: String, CodingKey {
        case projectsText = "projects_text"
        case skills
        case dsaProblems = "dsa_problems"
        case topic, company
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

enum RubricDimension: String, CaseIterable, Identifiable {
    case correctness, depth, structure, communication, confidence

    var id: Self { self }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .correctness: "checkmark.circle"
        case .depth: "square.stack.3d.up"
        case .structure: "list.bullet.indent"
        case .communication: "text.bubble"
        case .confidence: "waveform"
        }
    }
}

struct RubricScores: Codable, Equatable {
    let correctness: Int
    let depth: Int
    let structure: Int
    let communication: Int
    let confidence: Int

    subscript(dimension: RubricDimension) -> Int {
        switch dimension {
        case .correctness: correctness
        case .depth: depth
        case .structure: structure
        case .communication: communication
        case .confidence: confidence
        }
    }
}

struct AnswerScore: Codable, Equatable, Identifiable {
    var id: Int { answer }
    let answer: Int
    let scores: RubricScores
    let score: Double
    let note: String
    let level: Int?
}

struct InterviewFeedback: Codable, Equatable {
    let rating: Int
    let summary: String
    let improvements: [String]
    let mistakes: [String]
    let rubric: RubricScores?
    let answers: [AnswerScore]

    enum CodingKeys: String, CodingKey {
        case rating, summary, improvements, mistakes, rubric, answers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rating = try container.decode(Int.self, forKey: .rating)
        summary = try container.decode(String.self, forKey: .summary)
        improvements = try container.decodeIfPresent([String].self, forKey: .improvements) ?? []
        mistakes = try container.decodeIfPresent([String].self, forKey: .mistakes) ?? []
        rubric = try container.decodeIfPresent(RubricScores.self, forKey: .rubric)
        answers = try container.decodeIfPresent([AnswerScore].self, forKey: .answers) ?? []
    }

    func score(forAnswer number: Int) -> AnswerScore? {
        answers.first { $0.answer == number }
    }
}

struct InterviewSummary: Codable, Identifiable, Hashable {
    let id: Int
    let targetRole: String
    let mode: String?
    let company: String?
    let status: InterviewStatus
    let answerCount: Int
    let rating: Int?
    let startedAt: Date
    let endedAt: Date?

    var round: InterviewMode? { mode.flatMap(InterviewMode.init(rawValue:)) }

    /// "Amazon · SDE" for a company-style round, otherwise just the role.
    var roleLine: String { [company, targetRole].compactMap { $0 }.joined(separator: " · ") }

    enum CodingKeys: String, CodingKey {
        case id, mode, company, status, rating
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
    let company: String?
    let status: InterviewStatus
    let transcript: [InterviewTurn]
    let feedback: InterviewFeedback?
    let startedAt: Date
    let endedAt: Date?

    var round: InterviewMode? { mode.flatMap(InterviewMode.init(rawValue:)) }

    /// "Amazon · SDE" for a company-style round, otherwise just the role.
    var roleLine: String { [company, targetRole].compactMap { $0 }.joined(separator: " · ") }

    enum CodingKeys: String, CodingKey {
        case id, mode, company, status, transcript, feedback
        case targetRole = "target_role"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}
