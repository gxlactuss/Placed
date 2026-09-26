import SwiftUI
import UIKit

struct ResumeReviewResultView: View {

    let saved: SavedResumeReview
    let previousScore: Int?

    @State private var animatedProgress: Double = 0
    @State private var revealed = false
    @State private var copiedRewrite: Int?

    private var review: ResumeReview { saved.review }

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.xl) {
            scoreHeader
            factors
            checks
            strengths
            improvements
            rewrites
        }
        .onAppear(perform: reveal)
        .onChange(of: saved.id) { _, _ in
            animatedProgress = 0
            revealed = false
            copiedRewrite = nil
            reveal()
        }
    }

    private func reveal() {
        withAnimation(.easeOut(duration: 0.8).delay(0.15)) {
            animatedProgress = Double(review.overall) / 100
        }
        revealed = true
    }

    private var scoreHeader: some View {
        VStack(spacing: PPSpacing.md) {
            VStack(spacing: PPSpacing.xs) {
                Text(saved.fileName)
                    .ppSectionLabelStyle()
                    .multilineTextAlignment(.center)
                Text("For \(saved.targetRole) · \(saved.reviewedAt.formatted(.relative(presentation: .named)))")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .multilineTextAlignment(.center)
            }

            PPRingProgress(
                progress: animatedProgress,
                tint: .ppScore(Double(review.overall) / 10)
            ) {
                VStack(spacing: PPSpacing.xs) {
                    Text("\(review.overall)").font(.ppStatFixed(44))
                    Text("out of 100")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                }
            }
            .padding(.vertical, PPSpacing.sm)

            if let delta {
                delta.font(.ppCaption)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var delta: Text? {
        guard let previousScore else { return nil }
        let change = review.overall - previousScore
        if change > 0 {
            return Text("▲ \(change) since your last review").foregroundStyle(Color.ppEasy)
        }
        if change < 0 {
            return Text("▼ \(-change) since your last review").foregroundStyle(Color.ppHard)
        }
        return Text("Same score as your last review").foregroundStyle(Color.ppMuted)
    }

    private var factors: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPSectionHeader("Where the points went")
            PPCard {
                PPScoreBars(
                    items: review.factors.map { factor in
                        .init(
                            id: factor.key,
                            title: "\(factor.kind?.title ?? factor.key) · \(factor.weight)%",
                            symbol: factor.kind?.symbol ?? "circle",
                            score: factor.score,
                            detail: factor.reason
                        )
                    },
                    revealed: revealed
                )
            }
        }
    }

    private var checks: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPSectionHeader(title: "Screening checks") {
                Text("\(review.checks.count { $0.passed }) of \(review.checks.count) passed")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }
            PPCard {
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    ForEach(review.checks) { check in
                        HStack(alignment: .top, spacing: PPSpacing.md) {
                            Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(check.passed ? Color.ppEasy : Color.ppHard)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.label).font(.ppCaption)
                                Text(check.detail)
                                    .font(.ppMicro)
                                    .foregroundStyle(Color.ppMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(check.label), \(check.passed ? "passed" : "failed"). \(check.detail)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var strengths: some View {
        if !review.strengths.isEmpty {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                PPSectionHeader("What's working")
                ForEach(Array(review.strengths.enumerated()), id: \.offset) { _, strength in
                    HStack(alignment: .top, spacing: PPSpacing.md) {
                        Circle().fill(Color.ppEasy).frame(width: 6, height: 6).padding(.top, 6)
                        Text(strength)
                            .font(.ppCaption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var improvements: some View {
        if !review.improvements.isEmpty {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                PPSectionHeader("What to fix")
                ForEach(ResumePriority.allCases, id: \.self) { priority in
                    let items = review.improvements.filter { $0.priority == priority }
                    if !items.isEmpty {
                        Text(priority.title)
                            .font(.ppMicro)
                            .foregroundStyle(color(for: priority))
                            .padding(.top, PPSpacing.xs)
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            improvementCard(item, priority: priority)
                        }
                    }
                }
            }
        }
    }

    private func improvementCard(_ item: ResumeImprovement, priority: ResumePriority) -> some View {
        PPCard {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                HStack(spacing: PPSpacing.sm) {
                    Circle().fill(color(for: priority)).frame(width: 8, height: 8)
                    if !item.section.isEmpty {
                        Text(item.section)
                            .font(.ppMicro)
                            .foregroundStyle(Color.ppMuted)
                    }
                    Spacer(minLength: 0)
                    if let kind = item.factor.flatMap(ResumeFactorKind.init(rawValue:)) {
                        PPBadge(kind.title)
                    }
                }
                Text(item.issue)
                    .font(.ppCaption)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: PPSpacing.sm) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.ppMicro)
                        .foregroundStyle(Color.ppAccent400)
                        .padding(.top, 2)
                    Text(item.fix)
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func color(for priority: ResumePriority) -> Color {
        switch priority {
        case .high: .ppHard
        case .medium: .ppMedium
        case .low: .ppMuted
        }
    }

    @ViewBuilder
    private var rewrites: some View {
        if !review.rewrites.isEmpty {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                PPSectionHeader("Rewrites")
                if review.rewrites.contains(where: { $0.improved.contains("[") }) {
                    Text("Replace the highlighted parts with your real numbers before you use them.")
                        .font(.ppMicro)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(review.rewrites.enumerated()), id: \.offset) { index, rewrite in
                    rewriteCard(rewrite, index: index)
                }
            }
        }
    }

    private func rewriteCard(_ rewrite: ResumeRewrite, index: Int) -> some View {
        PPCard {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Before")
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
                Text(rewrite.original)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Text("After")
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppEasy)
                    .padding(.top, PPSpacing.xs)
                Text(highlightingPlaceholders(in: rewrite.improved))
                    .font(.ppCaption)
                    .fixedSize(horizontal: false, vertical: true)

                if !rewrite.why.isEmpty {
                    Text(rewrite.why)
                        .font(.ppMicro)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(copiedRewrite == index ? "Copied" : "Copy rewrite") {
                    UIPasteboard.general.string = rewrite.improved
                    PPHaptics.light()
                    copiedRewrite = index
                }
                .buttonStyle(.ppInlineLink)
                .padding(.top, PPSpacing.xs)
            }
        }
    }

    private func highlightingPlaceholders(in text: String) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for match in text.matches(of: #/\[[^\]]+\]/#) {
            result += AttributedString(String(text[cursor..<match.range.lowerBound]))
            var placeholder = AttributedString(String(text[match.range]))
            placeholder.foregroundColor = .ppAccent400
            placeholder.font = .ppCaption.weight(.semibold)
            result += placeholder
            cursor = match.range.upperBound
        }
        result += AttributedString(String(text[cursor...]))
        return result
    }
}
