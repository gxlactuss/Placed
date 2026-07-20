import SwiftUI

/// Home tab. Assembled entirely from the `DesignSystem` primitives and driven by
/// `SampleData` until the API is wired up.
struct HomeView: View {

    @Binding var selectedTab: AppTab

    @Environment(CompanyBank.self) private var bank

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.xl) {
                header
                heroStats
                resumeCard
                practiceModes
                companyCard
                streakCard
            }
            .padding(PPSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            HStack(alignment: .center, spacing: PPSpacing.md) {
                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    Text(greeting)
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                    Text(SampleData.userName).font(.ppTitle)
                }

                Spacer()

                PPIconPill(systemName: "flame.fill", text: "\(SampleData.streakDays)")
                PPAvatar(initials: initials(from: SampleData.userName))
            }

            HStack(spacing: PPSpacing.xs) {
                Text("Preparing for")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                Text(SampleData.targetRole).font(.ppCaption)
            }
            .padding(.horizontal, PPSpacing.md)
            .frame(height: 32)
            .background(Color.ppSurface, in: .capsule)
        }
    }

    private var heroStats: some View {
        // The one loud moment on the screen: solid amber, ink type.
        PPCard(tone: .accent) {
            PPStatRow(
                items: [
                    .init(value: "\(SampleData.quizzesTaken)", label: "Quizzes"),
                    .init(value: "\(SampleData.averageScore)%", label: "Avg score"),
                    .init(value: "\(SampleData.interviewsTaken)", label: "Interviews"),
                ],
                valueColor: .ppGround,
                labelColor: Color.ppGround.opacity(0.65)
            )
        }
    }

    private var resumeCard: some View {
        Button {
            selectedTab = .quiz
        } label: {
            PPCard {
                HStack(spacing: PPSpacing.lg) {
                    PPIconTile(systemName: "play.fill")

                    VStack(alignment: .leading, spacing: PPSpacing.sm) {
                        Text("Resume: CS Fundamentals + DSA · Medium")
                            .font(.ppHeadline)
                            .multilineTextAlignment(.leading)
                        Text("Question 11 of 15")
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                        PPProgressBar(progress: 11.0 / 15.0)
                    }

                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.ppMuted)
                }
            }
        }
        .buttonStyle(.ppPressable)
    }

    private var practiceModes: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPSectionHeader("Practice modes")

            HStack(spacing: PPSpacing.md) {
                modeCard(
                    icon: "checklist",
                    title: "Quiz Practice",
                    subtitle: "CS · DSA · Aptitude",
                    tab: .quiz
                )
                modeCard(
                    icon: "mic.fill",
                    title: "Mock Interview",
                    subtitle: "AI voice rounds",
                    tab: .interview
                )
            }
        }
    }

    private func modeCard(
        icon: String,
        title: String,
        subtitle: String,
        tab: AppTab
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            PPCard {
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    PPIconTile(systemName: icon)
                    VStack(alignment: .leading, spacing: PPSpacing.xs) {
                        Text(title)
                            .font(.ppHeadline)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.ppPressable)
    }

    private var companyCard: some View {
        Button {
            selectedTab = .companies
        } label: {
            PPCard {
                HStack(spacing: PPSpacing.lg) {
                    PPIconTile(systemName: "building.2.fill")

                    VStack(alignment: .leading, spacing: PPSpacing.xs) {
                        Text("LeetCode")
                            .font(.ppHeadline)
                            .multilineTextAlignment(.leading)
                        Text("Company-wise problem lists")
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: PPSpacing.sm)

                    // Real count from the bundled CSVs rather than a hardcoded figure.
                    Text("\(bank.companies.count) companies")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize()
                }
            }
        }
        .buttonStyle(.ppPressable)
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPSectionHeader("Daily streak")

            PPCard {
                VStack(alignment: .leading, spacing: PPSpacing.lg) {
                    HStack(spacing: PPSpacing.lg) {
                        PPIconTile(systemName: "flame.fill")
                        VStack(alignment: .leading, spacing: PPSpacing.xs) {
                            Text("\(SampleData.streakDays) day streak").font(.ppStat())
                            Text("Keep it going — practice today")
                                .font(.ppCaption)
                                .foregroundStyle(Color.ppMuted)
                        }
                    }

                    HStack(spacing: PPSpacing.sm) {
                        ForEach(Array(zip(weekdayLabels, SampleData.weekProgress).enumerated()), id: \.offset) { index, entry in
                            PPStreakDay(
                                label: entry.0,
                                isComplete: entry.1,
                                isToday: index == SampleData.weekProgress.count - 1
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private func initials(from name: String) -> String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }
}

#Preview {
    @Previewable @State var tab: AppTab = .home
    HomeView(selectedTab: $tab)
        .environment(CompanyBank())
}
