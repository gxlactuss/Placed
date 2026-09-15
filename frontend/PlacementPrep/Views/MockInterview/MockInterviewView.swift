import SwiftUI

struct MockInterviewView: View {

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(InterviewSetupStore.self) private var setupStore
    @Environment(CompanyBank.self) private var companyBank
    @Environment(StreakStore.self) private var streak
    @Environment(XPStore.self) private var xp
    @State private var model = InterviewSessionModel()
    @State private var showSetup = false
    @State private var mode: InterviewMode?
    @State private var showResults = false
    @State private var showHistory = false

    private var resolvedRole: String {
        let candidates = [
            setupStore.setup?.targetRole,
            auth.currentUser?.targetRole
        ]
        for candidate in candidates {
            let role = candidate?.trimmingCharacters(in: .whitespaces) ?? ""
            if !role.isEmpty { return role }
        }
        return "Software Engineer"
    }

    var body: some View {
        Group {
            if let mode {
                round(mode)
            } else {
                InterviewModePicker(
                    setup: setupStore.setup,
                    onPick: { mode = $0 },
                    onEditSetup: { showSetup = true },
                    onOpenHistory: { showHistory = true }
                )
            }
        }
        .onAppear { showSetup = !setupStore.isComplete }
        .fullScreenCover(isPresented: $showSetup) { InterviewSetupView() }
        .sheet(isPresented: $showHistory) { InterviewHistoryView() }
        .task { await companyBank.loadCatalogIfNeeded() }
    }

    private func round(_ mode: InterviewMode) -> some View {
        VStack(spacing: 0) {
            header
            voiceWave
            transcript
            controls
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .task(id: mode) {
            await model.startIfNeeded(
                targetRole: resolvedRole,
                mode: mode,
                context: context(for: mode)
            )
        }
        .onChange(of: model.isFinished) { _, finished in
            guard finished else { return }
            streak.recordActivity()
            xp.awardStreakDay()
            guard !model.wasEndedByInterviewer else { return }
            showResults = true
            Task { await model.loadFeedback() }
        }
        .onChange(of: model.feedback) { _, feedback in
            guard
                let rating = feedback?.rating,
                let sessionID = model.sessionId,
                rating >= XPAward.interviewThreshold(for: model.mode)
            else { return }
            xp.award(.interviewCleared(sessionID: sessionID))
        }
        .sheet(isPresented: $showResults) {
            InterviewResultsView(
                model: model,
                onAnotherRound: {
                    showResults = false
                    leaveRound()
                },
                onClose: { showResults = false }
            )
        }
    }

    private func context(for mode: InterviewMode) -> InterviewContextPayload {
        var payload = InterviewContextPayload()
        switch mode {
        case .projects:
            payload.projectsText = setupStore.setup?.projectsText
        case .techStack:
            payload.skills = setupStore.setup?.skills
        case .dsaApproach:
            payload.dsaProblems = problemPool()
        case .hr, .coreCs, .panelDebate:
            break
        }
        return payload
    }

    private static let problemsPerDifficulty = 10

    private func problemPool() -> DSAProblemPool? {
        guard !companyBank.catalog.isEmpty else { return nil }
        let slugs = Dictionary(grouping: companyBank.catalog.keys) { companyBank.catalog[$0] }
        func sample(_ difficulty: DSADifficulty) -> [String] {
            (slugs[difficulty] ?? [])
                .shuffled()
                .prefix(Self.problemsPerDifficulty)
                .map(Self.speakableTitle)
        }
        return DSAProblemPool(easy: sample(.easy), medium: sample(.medium), hard: sample(.hard))
    }

    private static func speakableTitle(_ slug: String) -> String {
        slug
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func leaveRound() {
        model.endSession()
        mode = nil
    }

    private var voiceWave: some View {
        PPLiquidWave(level: model.level, mode: waveMode, height: 72)
            .padding(.bottom, PPSpacing.md)
    }

    private var waveMode: PPLiquidWave.Mode {
        if model.isRecording { return .listening }
        if model.isThinking { return .thinking }
        return .idle
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                Text(mode?.title ?? "Mock Interview").font(.ppTitle)
                Text(roundDetail)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .contentTransition(.numericText())
                    .animation(PPMotion.snappy, value: model.difficulty)
            }

            Spacer(minLength: PPSpacing.sm)

            FocusModeToggle(compact: true)

            PPIconButton(systemName: "xmark", diameter: 36) { leaveRound() }

            PPBadge("Q\(model.questionNumber)", tone: .accent)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.vertical, PPSpacing.lg)
        .ppContentColumn()
    }

    private var roundDetail: String {
        if model.isWarmUp { return "\(model.role) · Warm-up" }
        if let difficulty = model.difficulty {
            return "\(model.role) · \(difficulty.title) questions"
        }
        return model.role
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PPSpacing.lg) {
                    ForEach(model.turns) { turn in
                        bubble(turn)
                            .id(turn.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if model.isThinking {
                        thinkingBubble.id("thinking")
                    }

                }
                .padding(.horizontal, PPSpacing.xl)
                .padding(.bottom, PPSpacing.lg)
                .ppContentColumn()
            }
            .scrollIndicators(.hidden)
            .animation(PPMotion.settle, value: model.turns.count)
            .onChange(of: model.turns.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: model.isThinking) { _, _ in scrollToEnd(proxy) }
        }
    }

    @ViewBuilder
    private func bubble(_ turn: InterviewSessionModel.Turn) -> some View {
        HStack(alignment: .top, spacing: PPSpacing.sm) {
            if turn.speaker == .ai {
                aiAvatar

                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    if turn.isFollowUp {
                        Text("Follow-up").ppSectionLabelStyle()
                    }
                    Text(turn.text).font(.ppBody)
                }
                .padding(PPSpacing.lg)
                .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.lg))

                Spacer(minLength: PPSpacing.xxl)
            } else {
                Spacer(minLength: PPSpacing.xxl)

                Text(turn.text)
                    .font(.ppBody)
                    .padding(PPSpacing.lg)
                    .background(Color.ppAccentSection, in: .rect(cornerRadius: PPRadius.lg))
            }
        }
    }

    private var aiAvatar: some View {
        Text("AI")
            .font(.ppMicro)
            .foregroundStyle(Color.ppAccent300)
            .frame(width: 32, height: 32)
            .background(Color.ppAccentSection, in: .circle)
    }

    private var thinkingBubble: some View {
        HStack(spacing: PPSpacing.sm) {
            aiAvatar
            ProgressView()
                .tint(Color.ppMuted)
                .padding(PPSpacing.lg)
                .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.lg))
            Spacer()
        }
    }

    private var controls: some View {
        VStack(spacing: PPSpacing.md) {
            if model.isFinished {
                Text(model.wasEndedByInterviewer
                     ? "The interviewer ended this round early."
                     : "Interview complete — nice work.")
                    .font(.ppHeadline)
                    .multilineTextAlignment(.center)
                HStack(spacing: PPSpacing.md) {
                    if !model.wasEndedByInterviewer {
                        Button("See results") {
                            showResults = true
                            Task { await model.loadFeedback() }
                        }
                        .buttonStyle(PPButtonStyle(variant: .primary, expands: false))
                    }
                    Button("Another round") { leaveRound() }
                        .buttonStyle(PPButtonStyle(variant: .secondary, expands: false))
                    Button("Start over") { Task { await model.restart() } }
                        .buttonStyle(PPButtonStyle(variant: .secondary, expands: false))
                }
            } else if let error = model.errorMessage {
                errorState(error)
            } else {
                PPHoldToTalkButton(level: model.level, isRecording: model.isRecording) {
                    model.startRecording()
                } onStop: {
                    model.stopRecording()
                } onCancel: {
                    model.cancelRecording()
                }
                .disabled(model.isThinking)
                .opacity(model.isThinking ? 0.4 : 1)

                Text(promptText)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PPSpacing.xl)
        .ppContentColumn()
        .background(.ultraThinMaterial)
        .background(Color.ppGround.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ppBorder).frame(height: 1)
        }
        .animation(PPMotion.snappy, value: model.isRecording)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: PPSpacing.md) {
            HStack(alignment: .top, spacing: PPSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.ppHard)
                Text(message)
                    .font(.ppCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Try again") { Task { await model.recover() } }
                .buttonStyle(PPButtonStyle(variant: .secondary, expands: false))
        }
        .padding(.horizontal, PPSpacing.xl)
    }

    private var promptText: String {
        if model.phase == .transcribing { return "Transcribing your answer…" }
        if model.isThinking { return "Thinking…" }
        if model.isRecording { return "Release to send · slide left to discard" }
        if !model.micAuthorized { return "Hold to allow the microphone, then answer" }
        if model.didDiscardRecording { return "Discarded — hold to answer again" }
        return "Hold to answer"
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if model.isThinking {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = model.turns.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

#Preview {
    MockInterviewView()
        .environment(FocusModeStore.preview())
        .environment(StreakStore.preview())
        .environment(XPStore.preview())
        .environment(InterviewSetupStore.preview(
            InterviewSetup(targetRole: "Backend Engineer", projectsSummary: nil)
        ))
        .environmentObject(AuthViewModel())
}
