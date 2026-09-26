import SwiftUI

struct QuizCategoryView: View {

    @Environment(QuizBank.self) private var bank
    @Environment(QuizProgressStore.self) private var progress

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PPSpacing.lg) {
                    Text("Quiz")
                        .font(.ppDisplay)
                        .padding(.bottom, PPSpacing.xs)

                    ForEach(Category.allCases) { category in
                        NavigationLink(value: category) {
                            card(for: category)
                        }
                        .buttonStyle(.ppPressable)
                    }

                    if !bank.loadFailures.isEmpty {
                        authoringErrors
                    }
                }
                .padding(PPSpacing.xl)
                .ppContentColumn()
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Category.self) { category in
                if bank.subjects(in: category).isEmpty {
                    QuizListView(track: QuizTrack(category: category, subject: nil))
                } else {
                    QuizTrackListView(category: category)
                }
            }
            .navigationDestination(for: QuizTrack.self) { track in
                QuizListView(track: track)
            }
            .foregroundStyle(Color.ppText)
            .ppScreenBackground()
        }
    }

    private func card(for category: Category) -> some View {
        let quizzes = bank.quizzes(in: category)
        let passed = progress.passedCount(in: quizzes)

        return PPCard {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                HStack(spacing: PPSpacing.md) {
                    PPCategoryBadge(category: category)

                    VStack(alignment: .leading, spacing: PPSpacing.xs) {
                        Text(bank.title(for: category))
                            .font(.ppHeadline)
                            .multilineTextAlignment(.leading)
                        Text(category.blurb)
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: PPSpacing.sm)

                    Image(systemName: "chevron.right")
                        .font(.ppMicro)
                        .foregroundStyle(Color.ppMuted)
                }

                HStack {
                    Text("\(passed) of \(category.plannedQuizCount) passed")
                        .font(.ppMicro)
                        .foregroundStyle(Color.ppMuted)
                    Spacer()
                    if quizzes.count < category.plannedQuizCount {
                        Text("\(quizzes.count) available")
                            .font(.ppMicro)
                            .foregroundStyle(Color.ppMuted)
                    }
                }

                PPProgressBar(
                    progress: Double(passed) / Double(max(category.plannedQuizCount, 1))
                )
            }
        }
    }

    private var authoringErrors: some View {
        PPCard(tone: .elevated) {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Label("\(bank.loadFailures.count) quiz file(s) failed to load", systemImage: "exclamationmark.triangle")
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppHard)
                ForEach(bank.loadFailures, id: \.self) { failure in
                    Text(failure)
                        .font(.ppMicro)
                        .foregroundStyle(Color.ppMuted)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}

#Preview {
    QuizCategoryView()
        .environment(QuizBank())
        .environment(QuizProgressStore.preview())
}
