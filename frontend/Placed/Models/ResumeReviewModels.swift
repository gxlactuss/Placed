import Foundation

struct ResumeDeviceSignals: Codable, Equatable {
    let hasEmail: Bool
    let hasPhone: Bool
    let hasLinks: Bool
    let pageCount: Int
    let hasTextLayer: Bool

    enum CodingKeys: String, CodingKey {
        case hasEmail = "has_email"
        case hasPhone = "has_phone"
        case hasLinks = "has_links"
        case pageCount = "page_count"
        case hasTextLayer = "has_text_layer"
    }
}

struct ResumeReviewRequest: Encodable {
    let targetRole: String
    let resumeText: String
    let device: ResumeDeviceSignals

    enum CodingKeys: String, CodingKey {
        case targetRole = "target_role"
        case resumeText = "resume_text"
        case device
    }
}

enum ResumeFactorKind: String {
    case roleFit = "role_fit"
    case impact, depth, clarity, format

    var title: String {
        switch self {
        case .roleFit: "Role fit"
        case .impact: "Impact"
        case .depth: "Technical depth"
        case .clarity: "Clarity"
        case .format: "Format & ATS"
        }
    }

    var symbol: String {
        switch self {
        case .roleFit: "scope"
        case .impact: "chart.line.uptrend.xyaxis"
        case .depth: "square.stack.3d.up"
        case .clarity: "text.alignleft"
        case .format: "doc.text.magnifyingglass"
        }
    }
}

struct ResumeFactor: Codable, Equatable, Identifiable {
    var id: String { key }
    let key: String
    let weight: Int
    let score: Int
    let reason: String

    var kind: ResumeFactorKind? { ResumeFactorKind(rawValue: key) }
}

struct ResumeCheck: Codable, Equatable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let passed: Bool
    let detail: String
}

enum ResumePriority: String, Codable, CaseIterable {
    case high, medium, low

    var title: String {
        switch self {
        case .high: "Fix first"
        case .medium: "Worth fixing"
        case .low: "Polish"
        }
    }
}

struct ResumeImprovement: Codable, Equatable {
    let factor: String?
    let priority: ResumePriority
    let section: String
    let issue: String
    let fix: String
}

struct ResumeRewrite: Codable, Equatable {
    let original: String
    let improved: String
    let why: String
}

struct ResumeReview: Codable, Equatable {
    let overall: Int
    let factors: [ResumeFactor]
    let checks: [ResumeCheck]
    let strengths: [String]
    let improvements: [ResumeImprovement]
    let rewrites: [ResumeRewrite]
}

struct SavedResumeReview: Codable, Equatable, Identifiable {
    let id: UUID
    let textHash: String
    let fileName: String
    let targetRole: String
    let reviewedAt: Date
    let review: ResumeReview
}
