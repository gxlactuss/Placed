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

    init() {
        companies = Self.discoverCompanies()
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
