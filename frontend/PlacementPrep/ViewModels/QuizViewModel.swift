import Foundation

@MainActor
final class QuizViewModel: ObservableObject {
    @Published var questions: [QuizQuestion] = []
    @Published var selectedAnswers: [String: String] = [:]
    @Published var result: QuizResult?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let network = NetworkManager.shared

    func loadQuestions(topic: QuizTopic, difficulty: QuizDifficulty) async {
        isLoading = true
        defer { isLoading = false }
        do {
            questions = try await network.request(
                path: "/api/quiz/questions?topic=\(topic.rawValue)&difficulty=\(difficulty.rawValue)"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitQuiz(topic: QuizTopic, difficulty: QuizDifficulty) async {
        let answers = selectedAnswers.map { QuizAnswer(questionId: $0.key, selectedOptionId: $0.value) }
        do {
            result = try await network.request(
                path: "/api/quiz/submit",
                method: .post,
                body: QuizSubmitRequest(topic: topic, difficulty: difficulty, answers: answers)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
