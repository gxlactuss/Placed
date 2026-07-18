import SwiftUI

struct QuizListView: View {
    @StateObject private var viewModel = QuizViewModel()
    @State private var selectedTopic: QuizTopic = .dsa
    @State private var selectedDifficulty: QuizDifficulty = .medium

    var body: some View {
        NavigationStack {
            Form {
                Picker("Topic", selection: $selectedTopic) {
                    ForEach(QuizTopic.allCases) { topic in
                        Text(topic.displayName).tag(topic)
                    }
                }

                Picker("Difficulty", selection: $selectedDifficulty) {
                    ForEach(QuizDifficulty.allCases) { difficulty in
                        Text(difficulty.rawValue.capitalized).tag(difficulty)
                    }
                }

                Button("Start Quiz") {
                    Task { await viewModel.loadQuestions(topic: selectedTopic, difficulty: selectedDifficulty) }
                }

                // TODO: once viewModel.questions loads, navigate to a QuizQuestionView
                // that walks through questions and binds answers to viewModel.selectedAnswers.
            }
            .navigationTitle("Quiz Practice")
        }
    }
}

#Preview {
    QuizListView()
}
