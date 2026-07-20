import Foundation

/// Difficulty as published in the CSV (`EASY` / `MEDIUM` / `HARD`).
enum DSADifficulty: String, CaseIterable, Identifiable, Codable, Hashable {
    case easy, medium, hard

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// Single letter for the summary line, e.g. "12/30 E".
    var initial: String { title.prefix(1).uppercased() }

    init?(csvValue: String) {
        self.init(rawValue: csvValue.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

/// One LeetCode problem within a company's list.
///
/// Note there is no `isSolved` here. The same problem appears in many companies'
/// lists, and solved state has to outlive any particular parse of a CSV, so it
/// lives in `SolvedStore` keyed by `id`. Keeping this a plain value type means
/// parsing stays cheap and testable.
struct DSAProblem: Identifiable, Hashable, Sendable {

    /// The LeetCode slug (`two-sum`), taken from the problem URL. Stable across
    /// companies and across data refreshes, which makes it the right key for
    /// persisted solved state — unlike title or row position.
    let id: String
    let title: String
    let url: URL?
    let difficulty: DSADifficulty
    /// 0–100 as published, where 100 is the most frequently asked.
    let frequency: Double
    let topics: [String]

    /// Builds a problem from one keyed CSV row. Returns nil when a required
    /// column is missing or unparseable, so bad rows drop out quietly.
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

    /// `https://leetcode.com/problems/two-sum` -> `two-sum`
    private static func slug(fromLink link: String) -> String? {
        guard let components = URL(string: link)?.pathComponents else { return nil }
        guard let last = components.last, last != "/" else { return nil }
        return last
    }
}

/// A company whose question list ships as a bundled CSV.
///
/// Constructed from the filename alone so the picker can list all 470 companies
/// without parsing a single CSV — problems load only when one is opened.
struct DSACompany: Identifiable, Hashable, Sendable {
    /// Lowercased filename stem, e.g. `goldman sachs`.
    var id: String { name.lowercased() }
    let name: String
    let fileURL: URL
}
