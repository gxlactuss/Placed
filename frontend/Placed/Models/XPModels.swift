import Foundation

enum XPLevel: Int, CaseIterable, Identifiable, Comparable {
    case fresher = 1
    case shortlisted
    case screened
    case interviewing
    case finalRound
    case placed

    var id: Int { rawValue }

    static func < (lhs: XPLevel, rhs: XPLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var minimumXP: Int {
        switch self {
        case .fresher: 0
        case .shortlisted: 100
        case .screened: 200
        case .interviewing: 300
        case .finalRound: 400
        case .placed: 1000
        }
    }

    var title: String {
        switch self {
        case .fresher: "Fresher"
        case .shortlisted: "Shortlisted"
        case .screened: "Screened"
        case .interviewing: "Interviewing"
        case .finalRound: "Final round"
        case .placed: "Placed"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .fresher: nil
        case .shortlisted: "AppIconTier2"
        case .screened: "AppIconTier3"
        case .interviewing: "AppIconTier4"
        case .finalRound: "AppIconTier5"
        case .placed: "AppIconTier6"
        }
    }

    var previewImageName: String {
        switch self {
        case .fresher: "IconPreviewBase"
        case .shortlisted: "IconPreviewTier2"
        case .screened: "IconPreviewTier3"
        case .interviewing: "IconPreviewTier4"
        case .finalRound: "IconPreviewTier5"
        case .placed: "IconPreviewTier6"
        }
    }

    static func level(for xp: Int) -> XPLevel {
        allCases.last { xp >= $0.minimumXP } ?? .fresher
    }

    var next: XPLevel? { XPLevel(rawValue: rawValue + 1) }
}

enum XPAward {
    case streakDay(String)
    case quizPassed(quizID: String)
    case interviewCleared(sessionID: Int)
    case problemSolved(slug: String, difficulty: DSADifficulty)
    case readinessMilestone(company: String, percent: Int)

    static let quizThreshold = 70

    static func interviewThreshold(for mode: InterviewMode) -> Int {
        switch mode {
        case .hr, .panelDebate: 8
        case .projects, .techStack, .coreCs, .dsaApproach: 6
        }
    }

    var points: Int {
        switch self {
        case .streakDay: 10
        case .quizPassed: 10
        case .interviewCleared: 25
        case .readinessMilestone: 20
        case .problemSolved(_, let difficulty):
            switch difficulty {
            case .easy: 5
            case .medium: 10
            case .hard: 15
            }
        }
    }

    var ledgerKey: String {
        switch self {
        case .streakDay(let day): "streak:\(day)"
        case .quizPassed(let quizID): "quiz:\(quizID)"
        case .interviewCleared(let sessionID): "interview:\(sessionID)"
        case .problemSolved(let slug, _): "dsa:\(slug)"
        case .readinessMilestone(let company, let percent): "readiness:\(company.lowercased()):\(percent)"
        }
    }

    var reason: String {
        switch self {
        case .streakDay: "Practised today"
        case .quizPassed: "Quiz cleared"
        case .interviewCleared: "Mock round cleared"
        case .problemSolved(_, let difficulty): "\(difficulty.title) problem solved"
        case .readinessMilestone(let company, let percent): "\(company) \(percent)% ready"
        }
    }
}
