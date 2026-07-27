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

    /// The role group the signed-in student's role unlocks.
    ///
    /// Held here rather than passed at every call site because it filters the
    /// bank itself: a role quiz that isn't theirs should be invisible, not shown
    /// and locked. `nil` — no role picked, or one this build doesn't know —
    /// means the Your Role track is simply empty.
    private(set) var activeRoleGroup: RoleQuizGroup?

    func adopt(role: CareerRole?) {
        activeRoleGroup = role?.quizGroup
    }

    /// Quizzes in a category, in play order.
    ///
    /// Role quizzes are filtered to the student's own group. Every other
    /// category is untouched, so this is a no-op for the three bundled tracks.
    func quizzes(in category: Category) -> [Quiz] {
        quizzes
            .filter { $0.category == category }
            .filter { $0.roleGroup == nil || $0.roleGroup == activeRoleGroup }
            .sorted { $0.order < $1.order }
    }

    func quiz(id: String) -> Quiz? {
        quizzes.first { $0.id == id }
    }

    /// Resolves saved question ids back to their content and originating quiz,
    /// dropping any id whose quiz is no longer bundled. Grouped by category then
    /// quiz order, so the saved list reads in the same order the quizzes do.
    /// O(all questions) — fine for the ~675-question bank on a page open.
    func savedQuestions(ids: Set<String>) -> [SavedQuestion] {
        guard !ids.isEmpty else { return [] }
        let ordered = quizzes.sorted {
            $0.category.rawValue != $1.category.rawValue
                ? $0.category.rawValue < $1.category.rawValue
                : $0.order < $1.order
        }
        return ordered.flatMap { quiz in
            quiz.questions
                .filter { ids.contains($0.id) }
                .map { SavedQuestion(quiz: quiz, question: $0) }
        }
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
