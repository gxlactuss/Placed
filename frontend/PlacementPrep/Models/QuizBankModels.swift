import SwiftUI

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

enum Category: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case csFundamentals = "cs-fundamentals"
    case dsa
    case aptitude
    case role

    var id: String { rawValue }

    var title: String {
        switch self {
        case .csFundamentals: "CS Fundamentals"
        case .dsa: "DSA"
        case .aptitude: "Aptitude"
        case .role: "Your Role"
        }
    }

    var blurb: String {
        switch self {
        case .csFundamentals: "OS · Networks · DBMS · System Design"
        case .dsa: "Algorithms, data structures & patterns"
        case .aptitude: "Puzzles, riddles & quantitative"
        case .role: "The stack you picked, tested properly"
        }
    }

    var plannedQuizCount: Int {
        switch self {
        case .csFundamentals, .dsa: 30
        case .aptitude: 15
        case .role: 1
        }
    }
}

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
    case general
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

    var blurb: String {
        switch self {
        case .operatingSystems: "Processes, memory, scheduling, deadlocks"
        case .networks: "TCP/IP, routing, HTTP, the OSI layers"
        case .dbms: "SQL, normalisation, transactions, indexing"
        case .systemDesign: "Scaling, caching, queues, trade-offs"
        case .algorithms: "Sorting, graphs, DP, greedy, searching"
        case .dataStructures: "Arrays, trees, heaps, hashing, graphs"
        case .quantitative: "Numbers, ratios, time and work, probability"
        case .logical: "Puzzles, sequences, seating, deduction"
        case .verbal: "Comprehension, grammar, vocabulary"
        case .general: "Theory, compilers, architecture, OOP"
        case .mixed: "Bit tricks, maths, complexity, OOP for interviews"
        }
    }

    var badgeSymbol: String {
        switch self {
        case .operatingSystems: "gearshape.2"
        case .networks: "network"
        case .dbms: "cylinder.split.1x2"
        case .systemDesign: "square.grid.3x3.topleft.filled"
        case .algorithms: "function"
        case .dataStructures: "tree"
        case .quantitative: "number"
        case .logical: "puzzlepiece"
        case .verbal: "text.book.closed"
        case .general: "books.vertical"
        case .mixed: "shuffle"
        }
    }
}

struct QuizTrack: Hashable, Identifiable, Sendable {

    let category: Category
    let subject: Subject?

    var id: String { "\(category.rawValue)/\(subject?.rawValue ?? "all")" }

    var title: String { subject?.title ?? category.title }
    var blurb: String { subject?.blurb ?? category.blurb }
    var badgeSymbol: String { subject?.badgeSymbol ?? category.badgeSymbol }
}

struct Question: Codable, Identifiable, Hashable, Sendable {

    struct Option: Codable, Identifiable, Hashable, Sendable {
        let id: String
        let text: String
    }

    let id: String
    let prompt: String
    let options: [Option]
    let correctOptionID: String
    let explanation: String
    let concept: String

    enum CodingKeys: String, CodingKey {
        case id, prompt, options, explanation, concept
        case correctOptionID = "correct_option_id"
    }

    var correctOption: Option? {
        options.first { $0.id == correctOptionID }
    }
}

struct Quiz: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let category: Category
    let subject: Subject?
    let order: Int
    let title: String
    let difficulty: Difficulty
    let questions: [Question]
    let passMark: Double
    let roleGroup: RoleQuizGroup?

    enum CodingKeys: String, CodingKey {
        case id, category, subject, order, title, difficulty, questions
        case passMark = "pass_mark"
        case roleGroup = "role_group"
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
        roleGroup = try container.decodeIfPresent(RoleQuizGroup.self, forKey: .roleGroup)
    }

    var questionsToPass: Int { Int((Double(questions.count) * passMark).rounded(.up)) }

    var passPercentage: Int {
        guard !questions.isEmpty else { return 0 }
        return Int((Double(questionsToPass) / Double(questions.count) * 100).rounded())
    }
}

struct QuizListItem: Identifiable, Hashable, Sendable {
    let quiz: Quiz
    let number: Int
    let isUnlocked: Bool
    let bestScore: Int?

    var id: String { quiz.id }
    var isPassed: Bool { (bestScore ?? 0) >= quiz.passPercentage }
}

struct SavedQuestion: Identifiable, Hashable, Sendable {
    let quiz: Quiz
    let question: Question

    var id: String { question.id }
}
