import SwiftUI

/// The rounds a student can pick from.
///
/// `rawValue` is the wire value the backend parses into its own `InterviewMode`
/// — keep the two in step, and don't rename a case once it has shipped, since
/// it's persisted on the session row.
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

    /// All outline, no filled variants: the tiles already carry a hairline
    /// border, and mixing `.fill` marks in made some rounds read heavier than
    /// others in the same list. Shapes are deliberately unalike so no two rounds
    /// are confusable at tile size.
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

    /// Why this round can't be started yet, or `nil` when it can.
    ///
    /// Only the two resume-derived rounds are ever gated — everything else runs
    /// without a resume, which is why uploading one is optional.
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

/// Round chooser — the screen the Interview tab shows when no round is running.
struct InterviewModePicker: View {

    let setup: InterviewSetup?
    let onPick: (InterviewMode) -> Void
    /// Reopens setup. The only route back to it once a setup has been saved —
    /// without this a student who skipped the resume (or whose upload failed)
    /// is stuck looking at two rounds they can never unlock.
    let onEditSetup: () -> Void
    /// Opens the saved interviews. Lives on the picker because this is the
    /// interview hub, and a past round is a thing you reach for from here.
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
            Text(setup.map { "Tailored to \($0.targetRole)." } ?? "Choose what you want to be asked about.")
                .font(.ppBody)
                .foregroundStyle(Color.ppMuted)
            // Named for whichever job the student still has to do: adding a
            // resume is the one that unlocks rounds, so it leads when missing.
            HStack(spacing: PPSpacing.lg) {
                Button(setup?.hasProjects == true ? "Change role or resume" : "Add your resume") {
                    onEditSetup()
                }
                .buttonStyle(.ppInlineLink)

                Button("Saved interviews") { onOpenHistory() }
                    .buttonStyle(.ppInlineLink)
            }
        }
        .padding(.top, PPSpacing.sm)
    }

    /// Nudge rather than a gate — Focus mode is genuinely optional, and the
    /// toggle's own sheet explains what iOS will and won't let it do.
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
        // A locked row opens setup rather than doing nothing: its subtitle already
        // says "Upload your resume to unlock", so tapping it should do that. Left
        // disabled, the instruction would be one the screen gives no way to obey.
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
        // Dimmed to read as unavailable, but not so far that it looks inert —
        // it's still a live target that takes you to the fix.
        .opacity(lock == nil ? 1 : 0.75)
    }
}

#Preview("With resume") {
    InterviewModePicker(
        setup: InterviewSetup(
            targetRole: "Backend Engineer",
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
        setup: InterviewSetup(targetRole: "Backend Engineer"),
        onPick: { _ in },
        onEditSetup: {},
        onOpenHistory: {}
    )
    .environment(FocusModeStore.preview(on: true))
}
