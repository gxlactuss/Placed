import SwiftUI

/// The bookmarked-questions page, presented as a sheet from the profile menu.
///
/// Reads the saved ids back through `QuizBank` so the content is always the
/// live bundled question, never a stale copy. Each card reviews one question:
/// prompt, the correct answer, and its explanation. Un-saving removes it here
/// and clears the bookmark everywhere.
struct SavedQuestionsView: View {

    @Environment(QuizBank.self) private var bank
    @Environment(SavedQuestionsStore.self) private var saved
    @Environment(\.dismiss) private var dismiss

    private var items: [SavedQuestion] { bank.savedQuestions(ids: saved.savedIDs) }

    var body: some View {
        VStack(spacing: 0) {
            header

            if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Saved").font(.ppTitle)
            if !items.isEmpty {
                Text("\(items.count)")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }
            Spacer()
            Button("Done") { dismiss() }
                .font(.ppBodyMedium)
                .foregroundStyle(Color.ppAccent400)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.xl)
        .padding(.bottom, PPSpacing.md)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: PPSpacing.md) {
                ForEach(items) { item in
                    savedCard(item)
                }
            }
            .padding(PPSpacing.xl)
            .animation(PPMotion.settle, value: saved.savedIDs)
        }
        .scrollIndicators(.hidden)
    }

    private func savedCard(_ item: SavedQuestion) -> some View {
        PPCard {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                HStack(spacing: PPSpacing.sm) {
                    PPBadge(item.quiz.category.title, tone: .neutral)
                    PPBadge(item.quiz.difficulty.title, tone: .tinted(item.quiz.difficulty.accent))

                    Spacer(minLength: PPSpacing.sm)

                    Button {
                        withAnimation(PPMotion.settle) { saved.remove(item.id) }
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppAccent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove from saved")
                }

                Text(item.question.prompt)
                    .font(.ppBodyMedium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let correct = item.question.correctOption {
                    HStack(alignment: .top, spacing: PPSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.ppEasy)
                        Text("\(correct.id) · \(correct.text)")
                            .foregroundStyle(Color.ppText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.ppCaption)
                }

                Text(item.question.explanation)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: PPSpacing.md) {
            Image(systemName: "bookmark")
                .font(.system(size: 30))
                .foregroundStyle(Color.ppMuted)
            Text("No saved questions yet")
                .font(.ppBodyMedium)
            Text("Tap the bookmark on any quiz question to keep it here for review.")
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PPSpacing.xxl)
    }
}

#Preview("With saved") {
    let bank = QuizBank()
    let ids = Set((bank.quizzes(in: .aptitude).first?.questions.prefix(3).map(\.id)) ?? [])
    return SavedQuestionsView()
        .environment(bank)
        .environment(SavedQuestionsStore.preview(saved: ids))
}

#Preview("Empty") {
    SavedQuestionsView()
        .environment(QuizBank())
        .environment(SavedQuestionsStore.preview())
}
