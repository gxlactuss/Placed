import SwiftUI

enum InterviewMode: String, CaseIterable, Identifiable, Codable {
    case hr
    case projects
    case techStack = "tech_stack"
    case coreCs = "core_cs"
    case dsaApproach = "dsa_approach"
    case panelDebate = "panel_debate"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hr: "HR & behavioural"
        case .projects: "Your projects"
        case .techStack: "Technical Round"
        case .coreCs: "Core CS"
        case .dsaApproach: "DSA Round"
        case .panelDebate: "Group discussion"
        }
    }

    var subtitle: String {
        switch self {
        case .hr: "Tell me about yourself, strengths, conflict, why this role."
        case .projects: "Defend what you built — decisions, trade-offs, what broke."
        case .techStack: "Depth on the technologies your resume claims."
        case .coreCs: "OS, DBMS, networks, OOP — asked in every campus interview."
        case .dsaApproach: "Talk through a problem's approach. No code."
        case .panelDebate: "A moderator sets the topic. Argue it out with one opponent."
        }
    }

    var icon: String {
        switch self {
        case .hr: "person.text.rectangle"
        case .projects: "wrench.and.screwdriver"
        case .techStack: "terminal"
        case .coreCs: "memorychip"
        case .dsaApproach: "arrow.triangle.branch"
        case .panelDebate: "bubble.left.and.text.bubble.right"
        }
    }

    func lockReason(for setup: InterviewSetup?) -> String? {
        switch self {
        case .projects:
            return (setup?.hasProjects ?? false) ? nil : "Upload your resume to unlock"
        case .techStack:
            return (setup?.hasSkills ?? false) ? nil : "Needs a skills section on your resume"
        default:
            return nil
        }
    }
}

struct InterviewModePicker: View {

    let role: String
    let setup: InterviewSetup?
    let onPick: (InterviewMode) -> Void
    let onEditSetup: () -> Void
    let onOpenHistory: () -> Void

    @Environment(FocusModeStore.self) private var focus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                heading
                if !focus.isOn { focusPrompt }
                ForEach(InterviewMode.allCases) { mode in
                    row(for: mode)
                }
            }
            .padding(PPSpacing.xl)
            .ppContentColumn()
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text("Pick a round").font(.ppDisplay)
            Text("Tailored to \(role).")
                .font(.ppBody)
                .foregroundStyle(Color.ppMuted)
            HStack(spacing: PPSpacing.lg) {
                Button(setup == nil ? "Add your resume" : "Change role or resume") {
                    onEditSetup()
                }
                .buttonStyle(.ppInlineLink)

                Button("Saved interviews") { onOpenHistory() }
                    .buttonStyle(.ppInlineLink)
            }
        }
        .padding(.top, PPSpacing.sm)
    }

    private var focusPrompt: some View {
        PPCard {
            HStack(alignment: .center, spacing: PPSpacing.lg) {
                PPIconTile(systemName: "moon.zzz", tint: .ppAccent400)
                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    Text("Turn on Focus first?").font(.ppHeadline)
                    Text("Keeps the screen awake through a hands-free round.")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PPSpacing.sm)
                FocusModeToggle(compact: true)
            }
        }
    }

    private func row(for mode: InterviewMode) -> some View {
        let lock = mode.lockReason(for: setup)
        return Button {
            if lock == nil { onPick(mode) } else { onEditSetup() }
        } label: {
            PPCard {
                HStack(alignment: .top, spacing: PPSpacing.lg) {
                    PPIconTile(systemName: mode.icon, tint: lock == nil ? .ppAccent400 : .ppMuted)

                    VStack(alignment: .leading, spacing: PPSpacing.xs) {
                        Text(mode.title).font(.ppHeadline)
                        Text(lock ?? mode.subtitle)
                            .font(.ppCaption)
                            .foregroundStyle(lock == nil ? Color.ppMuted : Color.ppAccent400)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: PPSpacing.sm)

                    Image(systemName: lock == nil ? "chevron.right" : "lock.fill")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.ppPressable)
        .opacity(lock == nil ? 1 : 0.75)
    }
}

#Preview("With resume") {
    InterviewModePicker(
        role: "Backend Engineer",
        setup: InterviewSetup(
            projectsSummary: nil,
            projectsText: "PlacementPrep — SwiftUI + FastAPI",
            skills: "Go, Redis, Docker"
        ),
        onPick: { _ in },
        onEditSetup: {},
        onOpenHistory: {}
    )
    .environment(FocusModeStore.preview())
}

#Preview("Resume skipped") {
    InterviewModePicker(
        role: "Backend Engineer",
        setup: nil,
        onPick: { _ in },
        onEditSetup: {},
        onOpenHistory: {}
    )
    .environment(FocusModeStore.preview(on: true))
}
