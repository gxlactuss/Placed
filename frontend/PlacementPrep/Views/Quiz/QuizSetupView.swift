import SwiftUI

/// Quiz tab landing screen: pick a topic and difficulty, then start.
/// The session itself is a full-screen cover so it can own the whole screen and
/// dismiss with the X, matching the designs.
struct QuizSetupView: View {

    @State private var topic: QuizTopic = .csFundamentals
    @State private var difficulty: QuizDifficulty = .medium
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.xxl) {
                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    Text("Quiz Practice").font(.ppDisplay)
                    Text("Pick a topic and difficulty to begin")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                }

                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    PPSectionHeader("Topic")
                    FlowRow {
                        ForEach(QuizTopic.allCases) { option in
                            PPFilterChip(
                                title: option.displayName,
                                isSelected: option == topic
                            ) {
                                topic = option
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    PPSectionHeader("Difficulty")
                    FlowRow {
                        ForEach(QuizDifficulty.allCases) { option in
                            PPFilterChip(
                                title: option.rawValue.capitalized,
                                isSelected: option == difficulty
                            ) {
                                difficulty = option
                            }
                        }
                    }
                }

                PPCard {
                    HStack(spacing: PPSpacing.lg) {
                        PPIconTile(systemName: "checklist")
                        VStack(alignment: .leading, spacing: PPSpacing.xs) {
                            Text("\(SampleData.allQuestions.count) questions")
                                .font(.ppHeadline)
                            Text("No time limit — the timer is per question")
                                .font(.ppCaption)
                                .foregroundStyle(Color.ppMuted)
                        }
                    }
                }

                Button("Start quiz") { isRunning = true }
                    .buttonStyle(.ppPrimary)
            }
            .padding(PPSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .fullScreenCover(isPresented: $isRunning) {
            QuizSessionView(topic: topic, difficulty: difficulty)
        }
    }
}

/// Minimal wrapping row. `LazyVGrid` cannot size columns to their content, and
/// the chip rows here need to wrap on smaller widths and at larger text sizes.
struct FlowRow: Layout {

    var spacing: CGFloat = PPSpacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        return CGSize(width: maxWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    QuizSetupView()
}
