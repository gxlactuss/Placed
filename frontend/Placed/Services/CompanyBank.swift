import Foundation

@MainActor
@Observable
final class CompanyBank {

    private(set) var companies: [DSACompany] = []
    private var cache: [DSACompany.ID: [DSAProblem]] = [:]

    private(set) var catalog: [DSAProblem.ID: DSADifficulty] = [:]
    private(set) var catalogTotals: [DSADifficulty: Int] = [:]
    private(set) var isCatalogReady = false

    /// The average company's topic mix across its most-asked problems. Each company counts
    /// once, so the 2000-problem lists don't drown out the 10-problem ones.
    private(set) var baseline: [TopicFamily: Double] = [:]
    private(set) var generalProfile: CompanyProfile?
    private var profiles: [DSACompany.ID: CompanyProfile] = [:]

    init() {
        companies = Self.discoverCompanies()
    }

    func loadCatalogIfNeeded() async {
        guard !isCatalogReady else { return }

        let companies = companies
        let built = await Task.detached(priority: .utility) { () -> CatalogBuild in
            var build = CatalogBuild()
            build.catalog.reserveCapacity(3000)
            var shareSums: [TopicFamily: Double] = [:]
            var mixSums: [DSADifficulty: Double] = [:]
            var profiled = 0

            for company in companies {
                guard let text = try? String(contentsOf: company.fileURL, encoding: .utf8) else { continue }
                let problems = CSVParser.keyedRows(from: text).compactMap(DSAProblem.init(csvRow:))
                build.problems[company.id] = problems
                for problem in problems { build.catalog[problem.id] = problem.difficulty }

                let core = CompanyProfile.coreSet(of: problems)
                guard !core.isEmpty else { continue }
                profiled += 1
                for (family, share) in CompanyProfile.familyShares(in: core) {
                    shareSums[family, default: 0] += share
                }
                for problem in core {
                    mixSums[problem.difficulty, default: 0] += 1 / Double(core.count)
                }
            }

            if profiled > 0 {
                build.baseline = shareSums.mapValues { $0 / Double(profiled) }
                build.difficultyMix = mixSums.mapValues { $0 / Double(profiled) }
            }
            return build
        }.value

        catalog = built.catalog
        catalogTotals = built.catalog.values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        baseline = built.baseline
        generalProfile = .general(baseline: built.baseline, difficultyMix: built.difficultyMix)
        cache.merge(built.problems) { current, _ in current }
        isCatalogReady = true
    }

    func profile(for company: DSACompany) async -> CompanyProfile {
        if let cached = profiles[company.id] { return cached }
        await loadCatalogIfNeeded()
        let problems = await problems(for: company)
        let profile = CompanyProfile.build(name: company.name, problems: problems, baseline: baseline)
        profiles[company.id] = profile
        return profile
    }

    /// Matches a stored target like "amazon " to the bundled company, or nil when it isn't bundled.
    func company(named name: String?) -> DSACompany? {
        guard let key = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !key.isEmpty
        else { return nil }
        return companies.first { $0.id == key }
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

private struct CatalogBuild: Sendable {
    var catalog: [DSAProblem.ID: DSADifficulty] = [:]
    var problems: [DSACompany.ID: [DSAProblem]] = [:]
    var baseline: [TopicFamily: Double] = [:]
    var difficultyMix: [DSADifficulty: Double] = [:]
}
