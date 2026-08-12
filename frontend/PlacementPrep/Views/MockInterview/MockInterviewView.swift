import SwiftUI

/// Mock interview transcript with a hold-to-talk control.
///
/// The screen is a thin render of `InterviewSessionModel`, which runs the real
/// round-trip: `VoiceService` records the held answer, it's uploaded to
/// `/api/interview/transcribe` (Whisper) for text, and `/api/interview/*`
/// supplies the questions and follow-ups. There's no live word-by-word bubble —
/// the transcript only exists once the recording is sent, so the mic halo and
/// `promptText` carry the feedback while recording.
struct MockInterviewView: View {

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(InterviewSetupStore.self) private var setupStore
    @Environment(CompanyBank.self) private var companyBank
    @Environment(StreakStore.self) private var streak
    @State private var model = InterviewSessionModel()
    @State private var showSetup = false
    /// `nil` means no round is running, so the tab shows the picker.
    @State private var mode: InterviewMode?
    @State private var showResults = false
    @State private var showHistory = false

    /// The setup screen's answer wins — it's the more deliberate one, collected
    /// for this specific interview. Falls back to the account's role, then a
    /// generic default so the interview can always start.
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
        // First visit for this account: collect role (+ optional resume) before
        // anything else, so the rounds have something to be tailored to.
        .onAppear { showSetup = !setupStore.isComplete }
        .fullScreenCover(isPresented: $showSetup) { InterviewSetupView() }
        .sheet(isPresented: $showHistory) { InterviewHistoryView() }
        // The DSA round needs a problem to talk about, and the catalog is built
        // off the main actor on first use.
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
        // Keyed on the mode so switching rounds starts a fresh session.
        .task(id: mode) {
            await model.startIfNeeded(
                targetRole: resolvedRole,
                mode: mode,
                context: context(for: mode)
            )
        }
        // The debrief is the point of finishing, so it comes up on its own. Not
        // offered when the interviewer walked out: there's nothing to mark, and
        // a score would land as a second telling-off.
        .onChange(of: model.isFinished) { _, finished in
            guard finished else { return }
            // Counts toward the streak even when the interviewer walked out —
            // sitting the round is the practice; the grade is a separate matter.
            streak.recordActivity()
            guard !model.wasEndedByInterviewer else { return }
            showResults = true
            Task { await model.loadFeedback() }
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

    /// Only ever sends what the round actually needs — the projects round has no
    /// use for a DSA problem, and shipping unused resume text would widen what
    /// leaves the device for no benefit.
    private func context(for mode: InterviewMode) -> InterviewContextPayload {
        var payload = InterviewContextPayload()
        switch mode {
        case .projects:
            payload.projectsText = setupStore.setup?.projectsText
        case .techStack:
            payload.skills = setupStore.setup?.skills
        case .dsaApproach:
            payload.dsaProblem = randomProblemTitle()
        case .hr, .coreCs, .panelDebate:
            break
        }
        return payload
    }

    /// A problem drawn from the bundled company lists. The catalog is keyed by
    /// LeetCode slug, so the slug is title-cased back into something speakable.
    /// `nil` is fine — the prompt tells the model to choose its own.
    private func randomProblemTitle() -> String? {
        guard let slug = companyBank.catalog.keys.randomElement() else { return nil }
        return slug
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func leaveRound() {
        model.endSession()
        mode = nil
    }

    /// Sits between the header and the transcript so it reads as part of the
    /// chrome rather than as another message in the conversation.
    ///
    /// It is driven by the mic meter, so it only has something real to show while
    /// the student is holding to talk. The thinking state is not decoration for
    /// its own sake: the gap between releasing the button and the reply arriving
    /// covers an upload, a transcription and a generation, and a strip that keeps
    /// moving is the cheapest way to say the app has not stalled.
    private var voiceWave: some View {
        PPVoiceWave(level: model.level, mode: waveMode)
            .padding(.horizontal, PPSpacing.xl)
            .padding(.bottom, PPSpacing.md)
    }

    private var waveMode: PPVoiceWave.Mode {
        if model.isRecording { return .listening }
        if model.isThinking { return .thinking }
        return .idle
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                Text(mode?.title ?? "Mock Interview").font(.ppTitle)
                Text(model.role)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }

            Spacer(minLength: PPSpacing.sm)

            // Icon-only here: the title and round badge already claim this row.
            FocusModeToggle(compact: true)

            PPIconButton(systemName: "xmark", diameter: 36) { leaveRound() }

            PPBadge("Round \(min(model.round, model.totalRounds)) of \(model.totalRounds)", tone: .accent)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.vertical, PPSpacing.lg)
    }

    // MARK: - Transcript

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


    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: PPSpacing.md) {
            if model.isFinished {
                Text(model.wasEndedByInterviewer
                     ? "The interviewer ended this round early."
                     : "Interview complete — nice work.")
                    .font(.ppHeadline)
                    .multilineTextAlignment(.center)
                HStack(spacing: PPSpacing.md) {
                    // Reopens the debrief they were shown automatically, so
                    // dismissing it isn't the same as throwing it away.
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
        // Matches the quiz footer: one static blur region over the transcript.
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
        if model.isRecording { return "Recording… release when you're done" }
        if !model.micAuthorized { return "Hold to allow the microphone, then answer" }
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
        .environment(InterviewSetupStore.preview(
            InterviewSetup(targetRole: "Backend Engineer", projectsSummary: nil)
        ))
        .environmentObject(AuthViewModel())
}
