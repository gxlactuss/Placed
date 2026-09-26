import SwiftUI

/// What a company asks most: its topic mix against the average company, with a heat pill on
/// the topics it over-indexes on.
struct CompanyInsightCard: View {

    let profile: CompanyProfile
    /// Shown for a company that isn't bundled, e.g. a name typed under "Other".
    var unlistedName: String? = nil
    var maxFamilies = 5

    var body: some View {
        PPCard(padding: PPSpacing.lg) {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                headline
                    .font(.ppBody)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    ForEach(profile.families.prefix(maxFamilies)) { item in
                        TopicHeatRow(item: item, fullShare: topShare, showsHeat: !profile.isGeneral)
                    }
                }

                DifficultyMixBar(mix: profile.difficultyMix)

                footnote
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var topShare: Double { profile.families.first?.share ?? 1 }

    private var headline: Text {
        let lead = profile.families.prefix(3).map(\.family.shortTitle).formatted(.list(type: .and))

        if profile.isGeneral {
            let opener = unlistedName.map { "We don't have \($0)'s question list yet. " } ?? ""
            return Text("\(opener)Across all companies, interviews lean on ")
                .foregroundStyle(Color.ppMuted)
                + Text(lead).foregroundStyle(Color.ppText).bold()
                + Text(".").foregroundStyle(Color.ppMuted)
        }

        let name = profile.companyName ?? "This company"
        let signature = profile.signature.map(\.family.title)
        guard !signature.isEmpty else {
            return Text("\(name)'s mix is close to average, mostly ")
                .foregroundStyle(Color.ppMuted)
                + Text(lead).foregroundStyle(Color.ppText).bold()
                + Text(".").foregroundStyle(Color.ppMuted)
        }
        return Text("\(name) asks more ")
            .foregroundStyle(Color.ppMuted)
            + Text(signature.formatted(.list(type: .and))).foregroundStyle(Color.ppText).bold()
            + Text(" than most companies.").foregroundStyle(Color.ppMuted)
    }

    private var footnote: Text {
        if profile.isGeneral {
            return Text("Pick a company later from the LeetCode tab to get a tailored plan.")
        }
        let base = profile.problemCount > profile.core.count
            ? "Based on the top \(profile.core.count) of \(profile.problemCount) reported questions, weighted by how often each is asked."
            : "Based on \(profile.problemCount) reported questions, weighted by how often each is asked."
        guard profile.isSmallSample else { return Text(base) }
        return Text(base + " ") + Text("Small sample, so treat this as a rough guide.").foregroundStyle(Color.ppMedium)
    }
}

struct TopicHeatRow: View {

    let item: FamilyShare
    /// The share that fills the bar, usually the company's largest.
    var fullShare: Double = 1
    var showsHeat = true

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.xs) {
            HStack(spacing: PPSpacing.sm) {
                Image(systemName: item.family.symbol)
                    .foregroundStyle(Color.ppMuted)
                    .frame(width: 18)
                Text(item.family.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if showsHeat { TopicHeatPill(item: item) }
                Spacer(minLength: PPSpacing.sm)
                Text("\(Int((item.share * 100).rounded()))%")
                    .foregroundStyle(Color.ppMuted)
                    .monospacedDigit()
            }
            .font(.ppCaption)

            PPProgressBar(progress: fullShare > 0 ? item.share / fullShare : 0, height: 6, tint: tint)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        showsHeat ? .ppHeat(item.temperature) : .ppAccent
    }
}

struct TopicHeatPill: View {

    let item: FamilyShare

    var body: some View {
        switch item.heat {
        case .hot, .warm: pill(tint: .ppHeat(item.temperature))
        case .normal: EmptyView()
        }
    }

    private func pill(tint: Color) -> some View {
        Text(item.lift.formatted(.number.precision(.fractionLength(1))) + "× avg")
        .font(.ppMicro)
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint.opacity(0.16), in: .capsule)
        .fixedSize()
        .accessibilityLabel("Asked \(item.lift.formatted(.number.precision(.fractionLength(1)))) times more than average")
    }
}

struct DifficultyMixBar: View {

    let mix: [DSADifficulty: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(DSADifficulty.allCases) { level in
                        let share = mix[level, default: 0]
                        if share > 0 {
                            Rectangle()
                                .fill(level.accent)
                                .frame(width: max(proxy.size.width * share - 2, 2))
                        }
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 6)

            HStack(spacing: PPSpacing.lg) {
                ForEach(DSADifficulty.allCases) { level in
                    HStack(spacing: 5) {
                        Circle().fill(level.accent).frame(width: 7, height: 7)
                        Text("\(Int((mix[level, default: 0] * 100).rounded()))% \(level.title)")
                            .font(.ppMicro)
                            .foregroundStyle(Color.ppMuted)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Company and general") {
    let bank = CompanyBank()
    return ScrollView {
        InsightPreview(bank: bank).padding(PPSpacing.xl)
    }
    .foregroundStyle(Color.ppText)
    .ppScreenBackground()
    .environment(bank)
}

private struct InsightPreview: View {
    let bank: CompanyBank
    @State private var profiles: [CompanyProfile] = []

    var body: some View {
        VStack(spacing: PPSpacing.lg) {
            ForEach(profiles.indices, id: \.self) { index in
                CompanyInsightCard(profile: profiles[index])
            }
        }
        .task {
            await bank.loadCatalogIfNeeded()
            for name in ["Uber", "Amazon", "Nykaa"] {
                if let company = bank.company(named: name) {
                    profiles.append(await bank.profile(for: company))
                }
            }
            if let general = bank.generalProfile { profiles.append(general) }
        }
    }
}
