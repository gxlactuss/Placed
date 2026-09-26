import Charts
import SwiftUI

struct InterviewScoreChart: View {

    let answers: [AnswerScore]
    var onSelect: ((AnswerScore) -> Void)? = nil

    @State private var selected: AnswerScore?

    private var showsDifficulty: Bool { answers.contains { $0.level != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            chart
                .frame(height: 180)

            if let selected {
                detail(selected)
            } else {
                Text(hint)
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
            }
        }
    }

    private var hint: String {
        showsDifficulty
            ? "Shaded bars show how hard each question was. Tap a point to see that answer."
            : "Tap a point to see that answer."
    }

    private var chart: some View {
        Chart {
            ForEach(answers) { answer in
                if let level = answer.level {
                    BarMark(
                        x: .value("Answer", answer.answer),
                        y: .value("Difficulty", Double(level) * 2),
                        width: .ratio(0.7)
                    )
                    .foregroundStyle(Color.ppElevated)
                    .accessibilityHidden(true)
                }
            }

            ForEach(answers) { answer in
                LineMark(
                    x: .value("Answer", answer.answer),
                    y: .value("Score", answer.score)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.ppAccent400)

                PointMark(
                    x: .value("Answer", answer.answer),
                    y: .value("Score", answer.score)
                )
                .foregroundStyle(Color.ppScore(answer.score))
                .symbolSize(selected?.answer == answer.answer ? 140 : 50)
                .accessibilityLabel("Answer \(answer.answer)")
                .accessibilityValue("\(answer.score.formatted(.number.precision(.fractionLength(1)))) out of 10")
            }

            if let selected {
                RuleMark(x: .value("Answer", selected.answer))
                    .foregroundStyle(Color.ppBorderStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...10)
        .chartXScale(domain: 0.5...(Double(answers.count) + 0.5))
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 5, 10]) {
                AxisGridLine().foregroundStyle(Color.ppBorder)
                AxisValueLabel().foregroundStyle(Color.ppMuted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(answers.count, 8))) { value in
                if let number = value.as(Double.self), number == number.rounded() {
                    AxisValueLabel("A\(Int(number))").foregroundStyle(Color.ppMuted)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geometry[plot].origin.x
                        guard let value: Double = proxy.value(atX: x) else { return }
                        select(nearest: value)
                    }
            }
        }
    }

    private func select(nearest value: Double) {
        guard let answer = answers.min(by: {
            abs(Double($0.answer) - value) < abs(Double($1.answer) - value)
        }) else { return }
        PPHaptics.light()
        withAnimation(PPMotion.snappy) { selected = answer }
        onSelect?(answer)
    }

    private func detail(_ answer: AnswerScore) -> some View {
        HStack(alignment: .top, spacing: PPSpacing.md) {
            InterviewScoreChip(score: answer.score)
            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                Text("Answer \(answer.answer)")
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
                if !answer.note.isEmpty {
                    Text(answer.note)
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct InterviewScoreChip: View {

    let score: Double

    var body: some View {
        Text(score.formatted(.number.precision(.fractionLength(1))))
            .font(.ppMicro)
            .monospacedDigit()
            .foregroundStyle(Color.ppScore(score, middle: .ppAccent400))
            .padding(.horizontal, PPSpacing.sm)
            .padding(.vertical, 3)
            .background(Color.ppScore(score).opacity(0.14), in: .capsule)
            .accessibilityLabel("\(score.formatted(.number.precision(.fractionLength(1)))) out of 10")
    }
}
