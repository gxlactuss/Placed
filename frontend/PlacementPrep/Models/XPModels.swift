import Foundation

/// The six XP tiers. Each one unlocks an app icon, so the boundaries are a
/// shipped promise — moving one retroactively takes an icon off someone's home
/// screen. Treat `minimumXP` as fixed.
enum XPLevel: Int, CaseIterable, Identifiable, Comparable {
    case fresher = 1     // 0–99
    case shortlisted     // 100–199
    case screened        // 200–299
    case interviewing    // 300–399
    case finalRound      // 400–999
    case placed          // 1000+

    var id: Int { rawValue }

    static func < (lhs: XPLevel, rhs: XPLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// XP at which this tier begins.
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

    /// The alternate app icon this tier unlocks, or `nil` for the tier that uses
    /// the icon the app ships with.
    ///
    /// These names must match the icon sets in the asset catalog. Until the art
    /// lands there are no alternates declared, `supportsAlternateIcons` is false
    /// and `AppIconService` no-ops — the tiers still unlock, they just have
    /// nothing to apply yet.
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

    /// A small copy of the tier's icon, for drawing inside the app.
    ///
    /// Separate from `alternateIconName` on purpose: app-icon sets in an asset
    /// catalog are compiled for the home screen and can't be relied on to load
    /// through `UIImage(named:)`, so the picker draws these 180px imagesets
    /// instead. They're generated from the same 1024 source.
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

    /// The tier containing `xp`.
    static func level(for xp: Int) -> XPLevel {
        allCases.last { xp >= $0.minimumXP } ?? .fresher
    }

    var next: XPLevel? { XPLevel(rawValue: rawValue + 1) }
}

/// Something the student did that is worth XP.
///
/// Each case carries the identity of the *thing* — the day, the quiz, the
/// interview session, the problem — and `ledgerKey` turns it into the string
/// `XPStore` dedupes on. That is what makes awarding idempotent: solving a
/// problem, un-ticking it and ticking it again pays once, and finishing a quiz
/// twice doesn't pay twice.
enum XPAward {
    /// A day on which the student practised at all. +10, once per day.
    case streakDay(String)
    /// A quiz finished at 70% or better. +10, once per quiz.
    case quizPassed(quizID: String)
    /// A mock round marked at or above its bar. +25, once per session.
    case interviewCleared(sessionID: Int)
    /// A LeetCode problem ticked solved. Pays by difficulty, once per problem.
    case problemSolved(slug: String, difficulty: DSADifficulty)

    /// The score a quiz must reach to pay out, independent of the quiz's own
    /// pass mark — XP is one currency, so its bar can't move per quiz.
    static let quizThreshold = 70

    /// The mark out of 10 a round must reach. The conversational rounds are
    /// marked more generously than the technical ones, so they're held higher.
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
        case .problemSolved(_, let difficulty):
            switch difficulty {
            case .easy: 5
            case .medium: 10
            case .hard: 15
            }
        }
    }

    /// Stable across app versions — it is persisted. Don't reshape these.
    var ledgerKey: String {
        switch self {
        case .streakDay(let day): "streak:\(day)"
        case .quizPassed(let quizID): "quiz:\(quizID)"
        case .interviewCleared(let sessionID): "interview:\(sessionID)"
        case .problemSolved(let slug, _): "dsa:\(slug)"
        }
    }

    /// Short line for the "+15 XP" toast and the history list.
    var reason: String {
        switch self {
        case .streakDay: "Practised today"
        case .quizPassed: "Quiz cleared"
        case .interviewCleared: "Mock round cleared"
        case .problemSolved(_, let difficulty): "\(difficulty.title) problem solved"
        }
    }
}
