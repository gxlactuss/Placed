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
