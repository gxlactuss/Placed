import Foundation

@MainActor
@Observable
final class CompanyBank {

    private(set) var companies: [DSACompany] = []
    private var cache: [DSACompany.ID: [DSAProblem]] = [:]

    private(set) var catalog: [DSAProblem.ID: DSADifficulty] = [:]
    private(set) var catalogTotals: [DSADifficulty: Int] = [:]
    private(set) var isCatalogReady = false

    init() {
        companies = Self.discoverCompanies()
    }

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
