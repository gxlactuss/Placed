import SwiftUI

/// Mock interview transcript with a hold-to-talk control.
///
/// Speech recognition is not wired up yet, so holding the mic streams a canned
/// transcription and releasing commits it. Swap `SampleData.sampleTranscription`
/// for `SpeechRecognizerService` output when that lands — the view does not need
/// to change shape.
struct MockInterviewView: View {

    @State private var turns: [Turn] = [
        Turn(speaker: .ai, text: SampleData.interviewOpener, isFollowUp: false)
    ]
    @State private var isRecording = false
    @State private var liveText = ""
    @State private var round = 1
    @State private var isThinking = false
    @State private var level: Double = 0

    private let totalRounds = 5

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            controls
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                Text("Mock Interview").font(.ppTitle)
                Text(SampleData.targetRole)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }

            Spacer()

            PPBadge("Round \(round) of \(totalRounds)", tone: .accent)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.vertical, PPSpacing.lg)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PPSpacing.lg) {
                    ForEach(turns) { turn in
                        bubble(turn).id(turn.id)
                    }

                    if isThinking {
                        thinkingBubble.id("thinking")
                    }

                    if isRecording && !liveText.isEmpty {
                        liveBubble.id("live")
                    }
                }
                .padding(.horizontal, PPSpacing.xl)
                .padding(.bottom, PPSpacing.lg)
            }
            .scrollIndicators(.hidden)
            .onChange(of: turns.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: liveText) { _, _ in scrollToEnd(proxy) }
            .onChange(of: isThinking) { _, _ in scrollToEnd(proxy) }
        }
    }

    @ViewBuilder
    private func bubble(_ turn: Turn) -> some View {
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
            Text(liveText)
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
            if isFinished {
                Text("Interview complete — nice work.")
                    .font(.ppHeadline)
                Button("Start over") { reset() }
                    .buttonStyle(PPButtonStyle(variant: .secondary, expands: false))
            } else {
                PPHoldToTalkButton(level: level, isRecording: isRecording) {
                    startRecording()
                } onStop: {
                    stopRecording()
                }
                .disabled(isThinking)
                .opacity(isThinking ? 0.4 : 1)

                Text(isRecording ? "Listening… release when you're done" : "Hold to answer")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PPSpacing.xl)
        .background(Color.ppGround)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ppBorder).frame(height: 1)
        }
        .animation(.easeOut(duration: 0.2), value: isRecording)
    }

    // MARK: - Behaviour

    private var isFinished: Bool { round > totalRounds }

    private func startRecording() {
        guard !isThinking else { return }
        isRecording = true
        liveText = ""
        level = 0.5
        streamSampleTranscription()
    }

    /// Reveals the canned answer word by word so the live bubble behaves like a
    /// real streaming recogniser.
    private func streamSampleTranscription() {
        let words = SampleData.sampleTranscription.split(separator: " ").map(String.init)

        for (index, word) in words.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) {
                guard isRecording else { return }
                liveText += liveText.isEmpty ? word : " " + word
                // Fake an input level so the mic halo moves while "speaking".
                level = 0.35 + 0.4 * abs(sin(Double(index)))
            }
        }
    }

    private func stopRecording() {
        isRecording = false
        level = 0

        let answer = liveText.trimmingCharacters(in: .whitespaces)
        liveText = ""
        guard !answer.isEmpty else { return }

        turns.append(Turn(speaker: .user, text: answer, isFollowUp: false))
        respond()
    }

    private func respond() {
        isThinking = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            isThinking = false
            let followUpIndex = round - 1

            if followUpIndex < SampleData.interviewFollowUps.count {
                turns.append(
                    Turn(
                        speaker: .ai,
                        text: SampleData.interviewFollowUps[followUpIndex],
                        isFollowUp: true
                    )
                )
            }
            round += 1
        }
    }

    private func reset() {
        turns = [Turn(speaker: .ai, text: SampleData.interviewOpener, isFollowUp: false)]
        round = 1
        liveText = ""
        isRecording = false
        isThinking = false
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if isRecording && !liveText.isEmpty {
                proxy.scrollTo("live", anchor: .bottom)
            } else if isThinking {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = turns.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Local model

    struct Turn: Identifiable {
        enum Speaker { case ai, user }

        let id = UUID()
        let speaker: Speaker
        let text: String
        let isFollowUp: Bool
    }
}

#Preview {
    MockInterviewView()
}
