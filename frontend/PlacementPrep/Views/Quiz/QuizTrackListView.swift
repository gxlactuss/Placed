import SwiftUI

/// The topic folders inside a category: DBMS, Operating Systems, Networks and so
/// on for CS Fundamentals.
///
/// This layer exists because of the unlock chain, not because the list was long.
/// Quizzes open one at a time in order, and that rule only means anything
/// between quizzes about the same thing — with all 30 CS quizzes in one line, a
/// student who wanted DBMS had to clear seven Operating Systems quizzes to reach
/// it. A folder per topic gives each subject its own chain, so every topic is
/// open from its own first quiz.
///
/// A category with no topics (Your Role) never reaches this screen — see
/// `QuizCategoryView`, which pushes its single track's quiz list directly.
struct QuizTrackListView: View {

    let category: Category

    @Environment(QuizBank.self) private var bank
    @Environment(QuizProgressStore.self) private var progress

    var body: some View {
        ScrollView {
            LazyVStack(spacing: PPSpacing.md) {
                ForEach(bank.tracks(in: category)) { track in
                    NavigationLink(value: track) {
                        card(track)
                    }
                    .buttonStyle(.ppPressable)
                }
            }
            .padding(.horizontal, PPSpacing.xl)
            .padding(.vertical, PPSpacing.lg)
            .ppContentColumn()
        }
        .scrollIndicators(.hidden)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
    }

    private func card(_ track: QuizTrack) -> some View {
        let quizzes = bank.quizzes(in: track)
        let passed = progress.passedCount(in: quizzes)

        return PPCard {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                HStack(spacing: PPSpacing.md) {
                    PPCategoryBadge(category: category, symbol: track.badgeSymbol, size: 48)

                    VStack(alignment: .leading, spacing: PPSpacing.xs) {
                        Text(track.title)
                            .font(.ppHeadline)
                            .multilineTextAlignment(.leading)
                        Text(track.blurb)
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: PPSpacing.sm)

                    Image(systemName: "chevron.right")
                        .font(.ppMicro)
                        .foregroundStyle(Color.ppMuted)
                }

                // The denominator here is the real count, not a planned one:
                // a topic is as long as the quizzes authored for it, and
                // "3 of 8" is the number the chain actually runs to.
                HStack {
                    Text("\(passed) of \(quizzes.count) passed")
                        .font(.ppMicro)
                        .foregroundStyle(Color.ppMuted)
                    Spacer()
                    if let next = nextUp(in: quizzes) {
                        Text(next)
                            .font(.ppMicro)
                            .foregroundStyle(Color.ppAccent400)
                    }
                }

                PPProgressBar(
                    progress: quizzes.isEmpty ? 0 : Double(passed) / Double(quizzes.count)
                )
            }
        }
    }

    /// Says where the student is in this topic rather than repeating the count:
    /// the quiz the chain is waiting on, or that the topic is finished.
    ///
    /// Reads the first *unpassed* position rather than adding one to the passed
    /// count — those agree under the chain, but not for a device carrying scores
    /// recorded while `unlockAllForTesting` was on.
    private func nextUp(in quizzes: [Quiz]) -> String? {
        guard !quizzes.isEmpty else { return nil }
        guard let next = quizzes.firstIndex(where: { !progress.hasPassed($0) }) else {
            return "Complete"
        }
        return "Next: quiz \(next + 1)"
    }
}

#Preview {
    NavigationStack {
        QuizTrackListView(category: .csFundamentals)
    }
    .environment(QuizBank())
    .environment(QuizProgressStore.preview())
}
