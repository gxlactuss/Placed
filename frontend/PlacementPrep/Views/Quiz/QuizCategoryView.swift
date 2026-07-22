import SwiftUI

/// Quiz tab root: pick a track, then a quiz within it.
struct QuizCategoryView: View {

    @Environment(QuizBank.self) private var bank
    @Environment(QuizProgressStore.self) private var progress

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PPSpacing.lg) {
                    // In-content serif header rather than a system large title:
                    // the nav bar renders in SF, which fights the Ledger type scale.
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
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Category.self) { category in
                QuizListView(category: category)
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
                        Text(category.title)
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

                // Denominator is the planned track size, so the copy reads
                // sensibly while only some quizzes have been authored.
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

    /// Surfaces malformed quiz JSON during authoring instead of silently
    /// dropping the file.
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
