import SwiftUI

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
