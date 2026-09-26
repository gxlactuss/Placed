import SwiftUI

/// "Amazon: 62% ready, weak on Graphs and DP", with the next problems worth solving.
struct CompanyReadinessCard: View {

    /// The bundled target company, or nil when none is set or it isn't bundled.
    let company: DSACompany?
    /// A target the user typed that we have no question list for.
    var unlistedName: String? = nil
    let onOpen: (DSACompany) -> Void
    let onPickTarget: () -> Void

    @Environment(CompanyBank.self) private var bank
    @Environment(SolvedStore.self) private var solved
    @State private var profile: CompanyProfile?

    var body: some View {
        Group {
            if let company {
                if let profile {
                    readiness(company, CompanyReadiness.compute(profile: profile, isSolved: solved.isSolved))
                } else {
                    PPCard {
                        ProgressView()
                            .tint(Color.ppMuted)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            } else {
                prompt
            }
        }
        .task(id: company?.id) {
            guard let company else { return profile = nil }
            profile = await bank.profile(for: company)
        }
    }

    // MARK: - Target set

    private func readiness(_ company: DSACompany, _ readiness: CompanyReadiness) -> some View {
        PPCard {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                HStack(spacing: PPSpacing.md) {
                    PPCompanyLogo(companyName: company.name, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Target company")
                            .font(.ppMicro)
                            .foregroundStyle(Color.ppMuted)
                        Text(company.name).font(.ppHeadline)
                    }
                    Spacer(minLength: PPSpacing.sm)
                    Menu {
                        Button("Change target", systemImage: "arrow.triangle.2.circlepath", action: onPickTarget)
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Color.ppMuted)
                            .frame(width: 32, height: 32)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Target company options")
                }

                VStack(alignment: .leading, spacing: PPSpacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        (
                            Text("\(readiness.percent)%")
                                .font(.ppStat())
                                .foregroundStyle(tint(readiness))
                            + Text(" ready")
                                .font(.ppHeadline)
                        )
                        .contentTransition(.numericText())
                        Spacer(minLength: PPSpacing.sm)
                        Text("\(readiness.solvedCount)/\(readiness.coreCount) top questions")
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                    }
                    PPProgressBar(progress: readiness.score, height: 6, tint: tint(readiness))
                    Text(readiness.weakLine ?? statusLine(readiness))
                        .font(.ppCaption)
                        .foregroundStyle(readiness.weakFamilies.isEmpty ? Color.ppMuted : Color.ppMedium)
                }
                .animation(PPMotion.settle, value: readiness.percent)

                if !readiness.nextUp.isEmpty {
                    VStack(alignment: .leading, spacing: PPSpacing.sm) {
                        Text("Next up").ppSectionLabelStyle()
                        ForEach(readiness.nextUp) { problem in
                            nextUpRow(problem, weak: readiness.weakFamilies)
                        }
                    }
                }

                Button {
                    onOpen(company)
                } label: {
                    HStack(spacing: PPSpacing.sm) {
                        Text("Open \(company.name) plan")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.ppInlineLink)
            }
        }
    }

    private func nextUpRow(_ problem: DSAProblem, weak: [TopicFamily]) -> some View {
        let families = TopicFamily.families(for: problem.topics)
        let label = weak.first(where: families.contains)
            ?? families.sorted { $0.rawValue < $1.rawValue }.first
        return nextUpRow(problem, label: label)
    }

    private func nextUpRow(_ problem: DSAProblem, label: TopicFamily?) -> some View {
        HStack(spacing: PPSpacing.sm) {
            Circle()
                .fill(problem.difficulty.accent)
                .frame(width: 7, height: 7)
            Text(problem.title)
                .font(.ppCaption)
                .lineLimit(1)
            Spacer(minLength: PPSpacing.sm)
            if let family = label {
                Text(family.shortTitle)
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
            }
            if let url = problem.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right")
                        .font(.ppMicro)
                        .foregroundStyle(Color.ppMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Open \(problem.title) on LeetCode")
            }
        }
    }

    private func tint(_ readiness: CompanyReadiness) -> Color {
        Color.ppScore(readiness.score * 10, middle: .ppAccent400)
    }

    private func statusLine(_ readiness: CompanyReadiness) -> String {
        switch readiness.percent {
        case 100: "Every top question solved. Try a mock DSA round."
        case 0: "Solve a few of their most-asked problems to get started."
        default: "No weak spots in their most-asked topics. Keep going."
        }
    }

    // MARK: - No target

    private var prompt: some View {
        Button(action: onPickTarget) {
            PPCard {
                HStack(spacing: PPSpacing.lg) {
                    PPIconTile(systemName: "scope", tint: .ppAccent400)
                    VStack(alignment: .leading, spacing: PPSpacing.xs) {
                        Text(unlistedName.map { "\($0) isn't in the bank yet" } ?? "Pick a target company")
                            .font(.ppHeadline)
                            .multilineTextAlignment(.leading)
                        Text(unlistedName == nil
                             ? "See what they ask most and how ready you are."
                             : "Pick a listed company to track readiness.")
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: PPSpacing.md)
                    Image(systemName: "chevron.right")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                }
            }
        }
        .buttonStyle(.ppPressable)
    }
}

#Preview {
    let bank = CompanyBank()
    return ScrollView {
        VStack(spacing: PPSpacing.lg) {
            CompanyReadinessCard(
                company: bank.company(named: "Amazon"),
                onOpen: { _ in },
                onPickTarget: {}
            )
            CompanyReadinessCard(company: nil, onOpen: { _ in }, onPickTarget: {})
            CompanyReadinessCard(company: nil, unlistedName: "Deutsche Bank", onOpen: { _ in }, onPickTarget: {})
        }
        .padding(PPSpacing.xl)
    }
    .foregroundStyle(Color.ppText)
    .ppScreenBackground()
    .environment(bank)
    .environment(SolvedStore.preview(solved: ["two-sum", "lru-cache", "number-of-islands"]))
}
