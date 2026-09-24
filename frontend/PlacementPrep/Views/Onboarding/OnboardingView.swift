import SwiftUI

struct OnboardingView: View {

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(InterviewSetupStore.self) private var setupStore
    @Bindable private var theme = ThemeStore.shared

    @State private var step: Step = .name
    @State private var isMovingForward = true
    @State private var name = ""
    @State private var role: CareerRole?
    @State private var resume = ResumeImporter()

    private enum Step: Int, CaseIterable {
        case name, role, resume, theme

        var title: String {
            switch self {
            case .name: "Let's set you up."
            case .role: "What are you preparing for?"
            case .resume: "Got a resume handy?"
            case .theme: "Make it yours."
            }
        }

        var subtitle: String {
            switch self {
            case .name: "Four quick steps so Placement Prep can tailor your practice."
            case .role: "Your mock interviews and one extra quiz are built around this. You can change it later."
            case .resume: "The interviewer will ask about your own projects and the stack you've listed. Optional — you can add it later from the Interview tab."
            case .theme: "Pick a starter theme. You can switch any time from Home."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: PPSpacing.xxl) {
                    header
                    stepContent
                }
                .padding(PPSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ppContentColumn()
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: isMovingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: isMovingForward ? .leading : .trailing).combined(with: .opacity)
                ))
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .onAppear {
            if name.isEmpty { name = auth.currentUser?.fullName ?? "" }
            if role == nil { role = CareerRole(title: auth.currentUser?.targetRole) }
            if let id = auth.currentUser?.id {
                setupStore.adopt(userId: id)
                if !resume.hasResume, let saved = setupStore.setup {
                    resume = ResumeImporter(restoring: saved)
                }
            }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            HStack {
                if step != .name {
                    Button {
                        go(to: Step(rawValue: step.rawValue - 1))
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.ppInlineLink)
                    .disabled(auth.isLoading)
                }
                Spacer()
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .contentTransition(.numericText())
            }
            .frame(height: 28)
            PPProgressBar(progress: Double(step.rawValue + 1) / Double(Step.allCases.count))
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.lg)
        .ppContentColumn()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text(step.title)
                .font(.ppDisplay)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.subtitle)
                .font(.ppBody)
                .foregroundStyle(Color.ppMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, PPSpacing.lg)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .name: nameStep
        case .role: RolePicker(selection: $role)
        case .resume: resumeStep
        case .theme: themeStep
        }
    }

    private var footer: some View {
        VStack(spacing: PPSpacing.sm) {
            errorBanner

            Button(action: advance) {
                if auth.isLoading {
                    ProgressView().tint(.ppOnAccent)
                } else {
                    Text(primaryTitle)
                }
            }
            .buttonStyle(.ppPrimary)
            .disabled(!canAdvance || auth.isLoading)
            .opacity(canAdvance || auth.isLoading ? 1 : 0.5)
            .animation(PPMotion.snappy, value: canAdvance)

            if step == .resume, !resume.hasResume, !resume.phase.isBusy {
                Button("Skip for now") { go(to: .theme) }
                    .buttonStyle(.ppGhost)
            }
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.vertical, PPSpacing.lg)
        .ppContentColumn()
    }

    // MARK: - Steps

    private var nameStep: some View {
        PPTextField(
            label: "Your name",
            placeholder: "e.g. Aditi Sharma",
            text: $name,
            textContentType: .name,
            autocapitalization: .words,
            submitLabel: .continue,
            onSubmit: advance
        )
    }

    private var resumeStep: some View {
        VStack(alignment: .leading, spacing: PPSpacing.lg) {
            ResumeAttachCard(importer: resume, targetRole: role?.title ?? "")

            VStack(alignment: .leading, spacing: PPSpacing.md) {
                Text("What it unlocks").ppSectionLabelStyle()
                unlockRow(.projects)
                unlockRow(.techStack)
            }
        }
    }

    private func unlockRow(_ mode: InterviewMode) -> some View {
        let unlocked = mode.lockReason(for: resume.setup) == nil
        return HStack(alignment: .top, spacing: PPSpacing.md) {
            Image(systemName: unlocked ? "checkmark.circle.fill" : mode.icon)
                .foregroundStyle(unlocked ? Color.ppEasy : Color.ppMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title).font(.ppBodyMedium)
                Text(mode.subtitle)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(PPMotion.snappy, value: unlocked)
    }

    private var themeStep: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: PPSpacing.md),
                      GridItem(.flexible(), spacing: PPSpacing.md)],
            spacing: PPSpacing.md
        ) {
            ForEach(AppTheme.allCases) { option in
                themeCard(option)
            }
        }
    }

    private func themeCard(_ option: AppTheme) -> some View {
        let isSelected = !theme.isDynamic && theme.activeTheme == option
        return Button {
            withAnimation(PPMotion.settle) {
                theme.isDynamic = false
                theme.selection = option
            }
        } label: {
            VStack(spacing: PPSpacing.sm) {
                ThemeSwatch(palette: option.palette)
                Text(option.name)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppText)
            }
            .frame(maxWidth: .infinity)
            .padding(PPSpacing.md)
            .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.lg)
                    .strokeBorder(isSelected ? Color.ppAccent : Color.ppBorder,
                                  lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = auth.errorMessage {
            HStack(alignment: .top, spacing: PPSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.ppHard)
                Text(message)
                    .font(.ppCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PPSpacing.md)
            .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.md)
                    .strokeBorder(Color.ppHard.opacity(0.4), lineWidth: 1)
            }
        }
    }

    // MARK: - Flow

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var primaryTitle: String {
        switch step {
        case .resume: resume.phase.isBusy ? "Reading…" : "Continue"
        case .theme: "Get started"
        default: "Continue"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .name: !trimmedName.isEmpty
        case .role: role != nil
        case .resume: !resume.phase.isBusy
        case .theme: !trimmedName.isEmpty && role != nil
        }
    }

    private func advance() {
        guard canAdvance, !auth.isLoading else { return }
        if let next = Step(rawValue: step.rawValue + 1) {
            go(to: next)
        } else {
            submit()
        }
    }

    private func go(to target: Step?) {
        guard let target else { return }
        isMovingForward = target.rawValue > step.rawValue
        withAnimation(PPMotion.settle) { step = target }
    }

    private func submit() {
        guard let role else { return }
        setupStore.save(resume.setup)
        Task { await auth.completeOnboarding(fullName: trimmedName, targetRole: role.title) }
    }
}

#Preview {
    OnboardingView()
        .environment(InterviewSetupStore.preview())
        .environmentObject(AuthViewModel())
}
