import SwiftUI

// MARK: - Difficulty

/// Question difficulty. Shares the DSA colour semantics so a "Medium" tag looks
/// the same whether it appears on a quiz or a LeetCode problem row.
enum Difficulty: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case easy, medium, hard

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var initial: String { title.prefix(1).uppercased() }

    var accent: Color {
        switch self {
        case .easy: .ppEasy
        case .medium: .ppMedium
        case .hard: .ppHard
        }
    }
}

// MARK: - Category

/// Top-level quiz track. `rawValue` doubles as the JSON filename prefix and the
/// key that quiz IDs are namespaced under.
enum Category: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case csFundamentals = "cs-fundamentals"
    case dsa
    case aptitude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .csFundamentals: "CS Fundamentals"
        case .dsa: "DSA"
        case .aptitude: "Aptitude"
        }
    }

    var blurb: String {
        switch self {
        case .csFundamentals: "OS · Networks · DBMS · System Design"
        case .dsa: "Algorithms, data structures & patterns"
        case .aptitude: "Puzzles, riddles & quantitative"
        }
    }

    /// The planned size of each track. Used for "3 of 30" style progress copy
    /// before every quiz file has been authored.
    var plannedQuizCount: Int {
        switch self {
        case .csFundamentals, .dsa: 30
        case .aptitude: 15
        }
    }
}

/// Sub-topic within a category — only CS Fundamentals uses these today, but the
/// field is generic so DSA can be subdivided later without a model change.
enum Subject: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case operatingSystems = "os"
    case networks = "cn"
    case dbms
    case systemDesign = "system-design"
    case algorithms
    case dataStructures = "data-structures"
    case quantitative
    case logical
    case verbal
    /// Cross-cutting CS topics that do not belong to one named subject —
    /// theory of computation, compilers, architecture, digital logic, OOP.
    case general
    /// The DSA "related concepts" track — bit manipulation, math, complexity,
    /// OOP for interviews and analysis techniques.
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .operatingSystems: "Operating Systems"
        case .networks: "Computer Networks"
        case .dbms: "DBMS"
        case .systemDesign: "System Design"
        case .algorithms: "Algorithms"
        case .dataStructures: "Data Structures"
        case .quantitative: "Quantitative"
        case .logical: "Logical Reasoning"
        case .verbal: "Verbal Ability"
        case .general: "General CS"
        case .mixed: "Related Concepts"
        }
    }
}

// MARK: - Question

/// One multiple-choice question.
///
/// `correctOptionID` is matched against `Option.id` rather than an array index,
/// so options can be reordered in the JSON without silently changing the answer.
struct Question: Codable, Identifiable, Hashable, Sendable {

    struct Option: Codable, Identifiable, Hashable, Sendable {
        /// Stable letter key: "A", "B", "C", "D".
        let id: String
        let text: String
    }

    let id: String
    let prompt: String
    let options: [Option]
    let correctOptionID: String
    /// Shown after the answer commits, and the reason wrong answers are useful.
    let explanation: String
    /// Fine-grained tag used to compute "Areas to improve" on the results screen.
    let concept: String

    // Difficulty is deliberately absent: it is a property of the whole quiz, not
    // of individual questions, so it lives on `Quiz`. Keeping it in one place
    // stops a "Hard" quiz from showing an "Easy" badge on question 3.

    enum CodingKeys: String, CodingKey {
        case id, prompt, options, explanation, concept
        case correctOptionID = "correct_option_id"
    }

    var correctOption: Option? {
        options.first { $0.id == correctOptionID }
    }
}

// MARK: - Quiz

/// A single numbered quiz within a category.
struct Quiz: Codable, Identifiable, Hashable, Sendable {

    /// Namespaced and stable, e.g. `cs-fundamentals-01`. Used as the persistence
    /// key for progress, so it must not change once shipped.
    let id: String
    let category: Category
    let subject: Subject?
    /// 1-based position in its category. Drives both display and unlock order.
    let order: Int
    let title: String
    /// Headline difficulty for the quiz as a whole; individual questions carry
    /// their own tags too.
    let difficulty: Difficulty
    let questions: [Question]
    /// Fraction of questions required to pass and unlock the next quiz.
    /// Defaults to 0.7 when absent from the JSON.
    let passMark: Double

    enum CodingKeys: String, CodingKey {
        case id, category, subject, order, title, difficulty, questions
        case passMark = "pass_mark"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(Category.self, forKey: .category)
        subject = try container.decodeIfPresent(Subject.self, forKey: .subject)
        order = try container.decode(Int.self, forKey: .order)
        title = try container.decode(String.self, forKey: .title)
        difficulty = try container.decode(Difficulty.self, forKey: .difficulty)
        questions = try container.decode([Question].self, forKey: .questions)
        passMark = try container.decodeIfPresent(Double.self, forKey: .passMark) ?? 0.7
    }

    /// Minimum number of correct answers to pass.
    var questionsToPass: Int { Int((Double(questions.count) * passMark).rounded(.up)) }

    /// The score percentage needed to pass.
    ///
    /// Derived from `questionsToPass` rather than straight from `passMark`, so
    /// the displayed threshold and the actual gate can never disagree. Taking it
    /// from `passMark` directly drifts on short quizzes: 3 questions at 0.67
    /// rounds to a 67% threshold, which 2/3 (67%) clears — even though 0.67
    /// implies all three are needed.
    var passPercentage: Int {
        guard !questions.isEmpty else { return 0 }
        return Int((Double(questionsToPass) / Double(questions.count) * 100).rounded())
    }
}

// MARK: - Progression

/// A quiz paired with its unlock state, which is what the list UI actually needs.
struct QuizListItem: Identifiable, Hashable, Sendable {
    let quiz: Quiz
    let isUnlocked: Bool
    /// Best score recorded so far, as a percentage. Nil if never attempted.
    let bestScore: Int?

    var id: String { quiz.id }
    var isPassed: Bool { (bestScore ?? 0) >= quiz.passPercentage }
}

/// A bookmarked question resolved back to its content and the quiz it came from,
/// which is what the saved-questions page renders.
struct SavedQuestion: Identifiable, Hashable, Sendable {
    let quiz: Quiz
    let question: Question

    var id: String { question.id }
}
