import Foundation

/// Loads company question lists from the CSVs bundled under `Resources/Companies`.
///
/// Two deliberate performance choices, given 470 companies and up to ~2,300
/// rows each:
///
/// - The company list is built from **filenames only**, so opening the picker
///   parses nothing.
/// - A company's CSV is parsed off the main actor, on first open, and cached.
@MainActor
@Observable
final class CompanyBank {

    private(set) var companies: [DSACompany] = []
    private var cache: [DSACompany.ID: [DSAProblem]] = [:]

    /// Difficulty of every *distinct* problem across all bundled companies, keyed
    /// by LeetCode slug. The same slug appearing in ten companies collapses to a
    /// single entry, so global progress counts a problem once however many lists
    /// carry it. Built lazily, once, off the main actor.
    private(set) var catalog: [DSAProblem.ID: DSADifficulty] = [:]
    /// Distinct-problem totals per difficulty, cached alongside `catalog` so the
    /// header never re-tallies 2,900+ entries on each render.
    private(set) var catalogTotals: [DSADifficulty: Int] = [:]
    private(set) var isCatalogReady = false

    init() {
        companies = Self.discoverCompanies()
    }

    /// Parses every CSV once to build the deduped `catalog`. A no-op after the
    /// first successful run. Kept off the main actor — 38 files, ~1.4 MB.
    func loadCatalogIfNeeded() async {
        guard !isCatalogReady else { return }

        let urls = companies.map(\.fileURL)
        let built = await Task.detached(priority: .utility) { () -> [DSAProblem.ID: DSADifficulty] in
            var map: [DSAProblem.ID: DSADifficulty] = [:]
            map.reserveCapacity(3000)
            for url in urls {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for row in CSVParser.keyedRows(from: text) {
                    guard let problem = DSAProblem(csvRow: row) else { continue }
                    map[problem.id] = problem.difficulty
                }
            }
            return map
        }.value

        catalog = built
        catalogTotals = built.values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        isCatalogReady = true
    }

    /// Problems for a company, parsed on first request and cached thereafter.
    func problems(for company: DSACompany) async -> [DSAProblem] {
        if let cached = cache[company.id] { return cached }

        let url = company.fileURL
        let parsed = await Task.detached(priority: .userInitiated) { () -> [DSAProblem] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return CSVParser.keyedRows(from: text).compactMap(DSAProblem.init(csvRow:))
        }.value

        cache[company.id] = parsed
        return parsed
    }

    /// Finds the bundled CSVs. Falls back to a flat bundle search because
    /// XcodeGen may or may not preserve the folder reference depending on how
    /// the resource is declared.
    private static func discoverCompanies() -> [DSACompany] {
        let bundle = Bundle.main
        let urls = bundle.urls(forResourcesWithExtension: "csv", subdirectory: "Companies")
            ?? bundle.urls(forResourcesWithExtension: "csv", subdirectory: nil)
            ?? []

        return urls
            .map { DSACompany(name: $0.deletingPathExtension().lastPathComponent, fileURL: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
