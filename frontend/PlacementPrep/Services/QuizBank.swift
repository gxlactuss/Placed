import Foundation

@MainActor
@Observable
final class QuizBank {

    private(set) var quizzes: [Quiz] = []
    private(set) var loadFailures: [String] = []

    init(bundle: Bundle = .main) {
        let (quizzes, failures) = Self.load(from: bundle)
        self.quizzes = quizzes
        self.loadFailures = failures
    }

    private(set) var activeRoleGroup: RoleQuizGroup?

    func adopt(role: CareerRole?) {
        activeRoleGroup = role?.quizGroup
    }

    func quizzes(in category: Category) -> [Quiz] {
        quizzes
            .filter { $0.category == category }
            .filter { $0.roleGroup == nil || $0.roleGroup == activeRoleGroup }
            .sorted { $0.order < $1.order }
    }

    func subjects(in category: Category) -> [Subject] {
        var seen: Set<Subject> = []
        return quizzes(in: category).compactMap { quiz in
            guard let subject = quiz.subject, seen.insert(subject).inserted else { return nil }
            return subject
        }
    }

    func tracks(in category: Category) -> [QuizTrack] {
        let subjects = subjects(in: category)
        guard !subjects.isEmpty else { return [QuizTrack(category: category, subject: nil)] }
        return subjects.map { QuizTrack(category: category, subject: $0) }
    }

    func quizzes(in track: QuizTrack) -> [Quiz] {
        let all = quizzes(in: track.category)
        guard let subject = track.subject else { return all }
        return all.filter { $0.subject == subject }
    }

    func quiz(id: String) -> Quiz? {
        quizzes.first { $0.id == id }
    }

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
