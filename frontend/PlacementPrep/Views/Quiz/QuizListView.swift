import SwiftUI

/// Ordered quizzes within one track, each showing its lock or pass state.
///
/// A track is a topic (DBMS, Operating Systems) rather than a whole category,
/// which is what makes the unlock chain usable — see `QuizTrackListView`.
struct QuizListView: View {

    let track: QuizTrack

    @Environment(QuizBank.self) private var bank
    @Environment(QuizProgressStore.self) private var progress
    @State private var activeQuiz: Quiz?
    // Not `private`: a private stored property makes the memberwise
    // initializer private too, and this view is constructed by name.
    var columns = PPAdaptiveColumns()

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle(track.title)
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .fullScreenCover(item: $activeQuiz) { quiz in
            QuizView(quiz: quiz)
        }
    }

    private var items: [QuizListItem] {
        progress.listItems(for: bank.quizzes(in: track))
    }

    /// A grid rather than a stack, because a track runs to 30 quizzes and the
    /// rows are short: on a regular-width screen `columns` gives two, on a phone
    /// exactly one, which is the stack this used to be.
    private var list: some View {
        ScrollView {
            LazyVGrid(columns: columns.grid(), spacing: PPSpacing.md) {
                ForEach(items) { item in
                    Button {
                        activeQuiz = item.quiz
                    } label: {
                        row(item)
                    }
                    .buttonStyle(.ppPressable)
                    .disabled(!item.isUnlocked)
                }
            }
            .padding(.horizontal, PPSpacing.xl)
            .padding(.vertical, PPSpacing.lg)
            .ppContentColumn(PPSize.wideColumn)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ item: QuizListItem) -> some View {
        PPCard {
            HStack(spacing: PPSpacing.md) {
                statusMark(item)

                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    Text(item.quiz.title)
                        .font(.ppBodyMedium)
                        .foregroundStyle(item.isUnlocked ? Color.ppText : Color.ppMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: PPSpacing.sm) {
                        PPBadge(item.quiz.difficulty.title, tone: .tinted(item.quiz.difficulty.accent))

                        Text("\(item.quiz.questions.count) questions")
                            .font(.ppMicro)
                            .foregroundStyle(Color.ppMuted)

                        if let best = item.bestScore {
                            Text("Best \(best)%")
                                .font(.ppMicro)
                                .foregroundStyle(item.isPassed ? Color.ppEasy : Color.ppMuted)
                        }
                    }
                }

                Spacer(minLength: PPSpacing.sm)

                if !item.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                }
            }
        }
        // Locked rows read as inert rather than merely un-tappable.
        .opacity(item.isUnlocked ? 1 : 0.5)
    }

    /// Numbered marker that becomes a tick once the quiz is passed.
    private func statusMark(_ item: QuizListItem) -> some View {
        ZStack {
            Circle()
                .fill(item.isPassed ? Color.ppAccent : Color.clear)
                .overlay {
                    if !item.isPassed {
                        Circle().strokeBorder(Color.ppBorderStrong, lineWidth: 1)
                    }
                }

            if item.isPassed {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.ppOnAccent)
            } else {
                Text("\(item.number)")
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
            }
        }
        .frame(width: 32, height: 32)
    }

    private var emptyState: some View {
        VStack(spacing: PPSpacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundStyle(Color.ppMuted)
            Text("No quizzes authored yet")
                .font(.ppBodyMedium)
            Text("Add a quiz JSON for \(track.title) under Resources/Quizzes, then run xcodegen generate.")
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PPSpacing.xxl)
    }
}

#Preview {
    NavigationStack {
        QuizListView(track: QuizTrack(category: .csFundamentals, subject: .dbms))
    }
    .environment(QuizBank())
    .environment(QuizProgressStore.preview())
    .environment(SavedQuestionsStore.preview())
}
