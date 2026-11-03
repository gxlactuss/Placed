import Foundation

enum DSADifficulty: String, CaseIterable, Identifiable, Codable, Hashable {
    case easy, medium, hard

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var initial: String { title.prefix(1).uppercased() }

    init?(csvValue: String) {
        self.init(rawValue: csvValue.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

struct DSAProblem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let url: URL?
    let difficulty: DSADifficulty
    let frequency: Double
    let topics: [String]

    init?(csvRow row: [String: String]) {
        guard
            let rawDifficulty = row["Difficulty"],
            let difficulty = DSADifficulty(csvValue: rawDifficulty),
            let title = row["Title"]?.trimmingCharacters(in: .whitespaces),
            !title.isEmpty,
            let link = row["Link"]?.trimmingCharacters(in: .whitespaces)
        else { return nil }

        self.id = Self.slug(fromLink: link) ?? title.lowercased()
        self.title = title
        self.url = URL(string: link)
        self.difficulty = difficulty
        self.frequency = Double(row["Frequency"] ?? "") ?? 0
        self.topics = (row["Topics"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func slug(fromLink link: String) -> String? {
        guard let components = URL(string: link)?.pathComponents else { return nil }
        guard let last = components.last, last != "/" else { return nil }
        return last
    }
}

struct DSACompany: Identifiable, Hashable, Sendable {
    var id: String { name.lowercased() }
    let name: String
    let fileURL: URL

    static let kjsitRecruiters: Set<String> = [
        "deloitte", "media.net", "idfc first bank", "accenture", "ltimindtree",
    ]

    var isKJSITRecruiter: Bool { Self.kjsitRecruiters.contains(id) }
}
