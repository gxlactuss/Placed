import Foundation

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
