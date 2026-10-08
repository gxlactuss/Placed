import Foundation
import Testing
@testable import PlacementPrep

/// These run inside the PlacementPrep test host, so the app bundle's resources are available.
@Suite("Bundled content")
@MainActor
struct BundledContentTests {

    private var appBundle: Bundle { Bundle(for: QuizBank.self) }

    // MARK: QuizBank

    @Test func allQuizzesDecode() {
        let bank = QuizBank(bundle: appBundle)
        #expect(bank.loadFailures.isEmpty, "Quiz decode failures:\n\(bank.loadFailures.joined(separator: "\n"))")

        let jsonCount = appBundle.urls(forResourcesWithExtension: "json", subdirectory: "Quizzes")?.count ?? 0
        #expect(jsonCount > 0, "No quiz JSON found in the app bundle's Quizzes folder")
        #expect(bank.quizzes.count == jsonCount)
    }

    @Test func quizIDsAreUnique() {
        let ids = QuizBank(bundle: appBundle).quizzes.map(\.id)
        let duplicates = Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.keys.sorted()
        #expect(duplicates.isEmpty, "Duplicate quiz ids: \(duplicates)")
    }

    @Test func everyQuestionIsWellFormed() {
        let quizzes = QuizBank(bundle: appBundle).quizzes
        for quiz in quizzes {
            #expect(!quiz.questions.isEmpty, "\(quiz.id) has no questions")
            for question in quiz.questions {
                #expect(question.correctOption != nil, "\(quiz.id)/\(question.id): correct option missing")
                #expect(question.options.count >= 2, "\(quiz.id)/\(question.id): fewer than 2 options")
            }
        }
    }

    @Test func questionIDsAreUniqueAcrossQuizzes() {
        // SavedQuestionsStore keys saved questions by question id alone.
        let ids = QuizBank(bundle: appBundle).quizzes.flatMap { $0.questions.map(\.id) }
        let duplicates = Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.keys.sorted()
        #expect(duplicates.isEmpty, "Duplicate question ids: \(duplicates.prefix(20))")
    }

    // MARK: CompanyBank

    @Test func everyCompanyCSVParsesToProblems() async throws {
        let bank = CompanyBank()
        #expect(!bank.companies.isEmpty, "No company CSVs found in the app bundle")

        for company in bank.companies {
            let problems = await bank.problems(for: company)
            #expect(!problems.isEmpty, "\(company.name).csv parsed to 0 problems")

            // Every data row should become a problem; a shortfall means rows were
            // dropped for a column-count mismatch or an unknown difficulty.
            let text = try String(contentsOf: company.fileURL, encoding: .utf8)
            let dataRows = CSVParser.rows(from: text).count - 1
            #expect(problems.count == dataRows, "\(company.name).csv: \(problems.count) of \(dataRows) rows parsed")
        }
    }

    @Test func catalogBuildsFromBundledCSVs() async {
        let bank = CompanyBank()
        await bank.loadCatalogIfNeeded()
        #expect(bank.isCatalogReady)
        #expect(!bank.catalog.isEmpty)
        #expect(bank.generalProfile != nil)
    }
}
