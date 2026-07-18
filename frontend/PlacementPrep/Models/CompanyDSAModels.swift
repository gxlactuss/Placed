import Foundation

struct DSAQuestion: Codable, Identifiable {
    var id: String { leetcodeURL }
    let title: String
    let leetcodeURL: String
    let difficulty: String
    let frequency: Double?

    enum CodingKeys: String, CodingKey {
        case title
        case leetcodeURL = "leetcode_url"
        case difficulty, frequency
    }
}

struct CompanySummary: Codable, Identifiable {
    var id: String { slug }
    let slug: String
    let name: String
    let questionCount: Int

    enum CodingKeys: String, CodingKey {
        case slug, name
        case questionCount = "question_count"
    }
}

struct CompanyQuestionList: Codable {
    let slug: String
    let name: String
    let questions: [DSAQuestion]
}
