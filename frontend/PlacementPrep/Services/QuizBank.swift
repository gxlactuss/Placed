import Foundation

/// Loads quizzes from the JSON files bundled under `Resources/Quizzes`.
///
/// One file per quiz keeps authoring parallel-friendly and diffs small — adding
/// quiz 07 means adding `cs-fundamentals-07.json`, with no existing file
/// touched. Files are decoded once at launch; at the planned 645 questions the
/// whole bank is a few hundred KB, so there is nothing to gain from lazy loading.
@MainActor
@Observable
final class QuizBank {

    private(set) var quizzes: [Quiz] = []
    /// Files that failed to decode, surfaced so an authoring typo is visible
    /// rather than silently producing a shorter list.
    private(set) var loadFailures: [String] = []

    init(bundle: Bundle = .main) {
        let (quizzes, failures) = Self.load(from: bundle)
        self.quizzes = quizzes
        self.loadFailures = failures
    }

    /// Quizzes in a category, in play order.
    func quizzes(in category: Category) -> [Quiz] {
        quizzes
            .filter { $0.category == category }
            .sorted { $0.order < $1.order }
    }

    func quiz(id: String) -> Quiz? {
        quizzes.first { $0.id == id }
    }

    private static func load(from bundle: Bundle) -> ([Quiz], [String]) {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Quizzes")
            ?? bundle.urls(forResourcesWithExtension: "json", subdirectory: nil)
            ?? []

        let decoder = JSONDecoder()
        var quizzes: [Quiz] = []
        var failures: [String] = []

        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                quizzes.append(try decoder.decode(Quiz.self, from: data))
            } catch {
                failures.append("\(url.lastPathComponent): \(error)")
            }
        }

        return (quizzes, failures)
    }
}
