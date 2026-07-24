import SwiftUI

/// Mock interview transcript with a hold-to-talk control.
///
/// The screen is a thin render of `InterviewSessionModel`, which runs the real
/// round-trip: Apple's on-device speech recogniser transcribes the held answer,
/// and the Gemini-backed `/api/interview/*` routes supply the questions and
/// follow-ups. Holding the mic streams the live transcription; releasing submits.
struct MockInterviewView: View {

    @EnvironmentObject private var auth: AuthViewModel
    @State private var model = InterviewSessionModel()

    private var resolvedRole: String {
        let role = auth.currentUser?.targetRole?.trimmingCharacters(in: .whitespaces) ?? ""
        return role.isEmpty ? "Software Engineer" : role
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            controls
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .task { await model.startIfNeeded(targetRole: resolvedRole) }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                Text("Mock Interview").font(.ppTitle)
                Text(model.role)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }

            Spacer()

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

                    if model.isRecording && !model.liveText.isEmpty {
                        liveBubble.id("live")
                    }
                }
                .padding(.horizontal, PPSpacing.xl)
                .padding(.bottom, PPSpacing.lg)
            }
            .scrollIndicators(.hidden)
            .animation(PPMotion.settle, value: model.turns.count)
            .onChange(of: model.turns.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: model.liveText) { _, _ in scrollToEnd(proxy) }
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

    private var liveBubble: some View {
        HStack(spacing: PPSpacing.sm) {
            Image(systemName: "waveform")
                .foregroundStyle(Color.ppAccent400)
            Text(model.liveText)
                .font(.ppBody)
                .italic()
                .foregroundStyle(Color.ppMuted)
            Spacer()
        }
        .padding(PPSpacing.lg)
        .background(Color.ppElevated, in: .rect(cornerRadius: PPRadius.lg))
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: PPSpacing.md) {
            if model.isFinished {
                Text("Interview complete — nice work.")
                    .font(.ppHeadline)
                Button("Start over") { Task { await model.restart() } }
                    .buttonStyle(PPButtonStyle(variant: .secondary, expands: false))
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
        if model.isThinking { return "Thinking…" }
        if model.isRecording { return "Listening… release when you're done" }
        if !model.micAuthorized { return "Hold to allow the microphone, then answer" }
        return "Hold to answer"
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if model.isRecording && !model.liveText.isEmpty {
                proxy.scrollTo("live", anchor: .bottom)
            } else if model.isThinking {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = model.turns.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

#Preview {
    MockInterviewView()
        .environmentObject(AuthViewModel())
}
