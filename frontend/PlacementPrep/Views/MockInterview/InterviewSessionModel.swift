import Foundation

@MainActor
@Observable
final class InterviewSessionModel {

    struct Turn: Identifiable {
        enum Speaker { case ai, user }
        let id = UUID()
        let speaker: Speaker
        let text: String
        let isFollowUp: Bool
    }

    enum Phase: Equatable {
        case connecting
        case ready
        case recording
        case transcribing
        case thinking
        case finished
        case error(String)
    }

    private(set) var turns: [Turn] = []
    private(set) var questionNumber = 1
    private(set) var difficulty: InterviewDifficulty?
    private(set) var isWarmUp = false
    private(set) var phase: Phase = .connecting
    private(set) var role = "Software Engineer"
    private(set) var level: Double = 0
    private(set) var micAuthorized = false
    private(set) var wasEndedByInterviewer = false

    private(set) var feedback: InterviewFeedback?
    private(set) var isLoadingFeedback = false
    private(set) var feedbackError: String?

    func loadFeedback() async {
        guard let sessionId, feedback == nil, !isLoadingFeedback else { return }
        isLoadingFeedback = true
        feedbackError = nil
        defer { isLoadingFeedback = false }
        do {
            feedback = try await network.request(
                path: "/api/interview/\(sessionId)/feedback",
                method: .post
            )
        } catch {
            feedbackError = Self.friendly(error)
        }
    }

    private func resetFeedback() {
        feedback = nil
        feedbackError = nil
        isLoadingFeedback = false
    }

    private(set) var didDiscardRecording = false

    var answeredCount: Int { turns.filter { $0.speaker == .user }.count }

    private var questionReadyAt: Date?
    private var thinkSeconds: Double?
    private var recordingStartedAt: Date?

    private(set) var sessionId: Int?
    private(set) var mode: InterviewMode = .coreCs
    private var context = InterviewContextPayload()
    private var hasRequestedStart = false
    private let network = NetworkManager.shared
    private let voice = VoiceService()

    var isRecording: Bool { phase == .recording }
    var isThinking: Bool { phase == .connecting || phase == .thinking || phase == .transcribing }
    var isFinished: Bool { phase == .finished }
    var errorMessage: String? { if case let .error(m) = phase { return m }; return nil }
    var canRecord: Bool { phase == .ready }

    func startIfNeeded(
        targetRole: String,
        mode: InterviewMode,
        context: InterviewContextPayload
    ) async {
        guard !hasRequestedStart else { return }
        hasRequestedStart = true
        role = targetRole
        self.mode = mode
        self.context = context
        requestMicPermission()
        await start()
    }

    func endSession() {
        if let url = voice.stopRecording() { voice.discard(url) }
        hasRequestedStart = false
        sessionId = nil
        turns = []
        level = 0
        resetProgress()
        wasEndedByInterviewer = false
        resetFeedback()
        phase = .connecting
    }

    private func resetProgress() {
        questionNumber = 1
        difficulty = nil
        isWarmUp = false
        didDiscardRecording = false
        questionReadyAt = nil
        thinkSeconds = nil
        recordingStartedAt = nil
    }

    private func markQuestionReady() {
        questionReadyAt = .now
        thinkSeconds = nil
    }

    private func apply(_ resp: InterviewAiResponse) {
        if let number = resp.questionNumber { questionNumber = number }
        if let level = resp.difficulty { difficulty = InterviewDifficulty(level: level) }
        isWarmUp = resp.calibrating ?? false
    }

    private func requestMicPermission() {
        voice.requestPermissions { [weak self] granted in
            Task { @MainActor in self?.micAuthorized = granted }
        }
    }

    private func start() async {
        phase = .connecting
        do {
            let resp: InterviewAiResponse = try await network.request(
                path: "/api/interview/start",
                method: .post,
                body: InterviewStartRequest(
                    targetRole: role,
                    mode: mode.rawValue,
                    context: context.isEmpty ? nil : context
                )
            )
            sessionId = resp.sessionId
            turns = [Turn(speaker: .ai, text: resp.aiMessage, isFollowUp: false)]
            resetProgress()
            apply(resp)
            phase = .ready
            markQuestionReady()
        } catch {
            phase = .error(Self.friendly(error))
        }
    }

    func restart() async {
        if let url = voice.stopRecording() { voice.discard(url) }
        turns = []
        level = 0
        resetProgress()
        sessionId = nil
        wasEndedByInterviewer = false
        resetFeedback()
        await start()
    }

    func recover() async {
        if sessionId == nil {
            await start()
        } else {
            phase = .ready
            markQuestionReady()
        }
    }

    func startRecording() {
        guard canRecord else { return }

        guard micAuthorized else {
            voice.requestPermissions { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.micAuthorized = granted
                    if !granted {
                        self.phase = .error("Microphone or speech access is off. Enable both for Placement Prep in Settings, then hold to answer again.")
                    }
                }
            }
            return
        }

        beginListening()
    }

    private func beginListening() {
        do {
            try voice.startRecording { [weak self] value in
                Task { @MainActor in self?.level = value }
            }
            if thinkSeconds == nil, let questionReadyAt {
                thinkSeconds = Date.now.timeIntervalSince(questionReadyAt)
            }
            recordingStartedAt = .now
            didDiscardRecording = false
            phase = .recording
        } catch {
            phase = .error(Self.friendly(error))
        }
    }

    func stopRecording() {
        guard case .recording = phase else { return }
        level = 0
        let speakingSeconds = recordingStartedAt.map { Date.now.timeIntervalSince($0) }
        recordingStartedAt = nil

        guard let url = voice.stopRecording() else { phase = .ready; return }
        phase = .transcribing
        Task { await transcribeThenRespond(url, speakingSeconds: speakingSeconds) }
    }

    func cancelRecording() {
        guard case .recording = phase else { return }
        level = 0
        recordingStartedAt = nil
        if let url = voice.stopRecording() { voice.discard(url) }
        didDiscardRecording = true
        phase = .ready
    }

    private func transcribeThenRespond(_ url: URL, speakingSeconds: Double?) async {
        defer { voice.discard(url) }
        do {
            let resp: TranscriptionResponse = try await network.upload(
                path: "/api/interview/transcribe",
                fileURL: url,
                fieldName: "audio",
                mimeType: "audio/m4a"
            )
            let answer = resp.text.trimmingCharacters(in: .whitespaces)
            guard !answer.isEmpty else { phase = .ready; return }
            await appendAndRespond(answer, speakingSeconds: speakingSeconds)
        } catch {
            phase = .error(Self.friendly(error))
        }
    }

    private func appendAndRespond(_ answer: String, speakingSeconds: Double?) async {
        turns.append(Turn(speaker: .user, text: answer, isFollowUp: false))
        await respond(answer: answer, speakingSeconds: speakingSeconds)
    }

    private func respond(answer: String, speakingSeconds: Double?) async {
        guard let sessionId else {
            phase = .error("The interview session was lost. Start over to continue.")
            return
        }
        phase = .thinking
        do {
            let resp: InterviewAiResponse = try await network.request(
                path: "/api/interview/respond",
                method: .post,
                body: InterviewAnswerSubmitRequest(
                    sessionId: sessionId,
                    transcribedAnswer: answer,
                    thinkSeconds: thinkSeconds,
                    speakingSeconds: speakingSeconds
                )
            )
            turns.append(Turn(speaker: .ai, text: resp.aiMessage, isFollowUp: true))
            apply(resp)
            wasEndedByInterviewer = resp.endedEarly ?? false
            if resp.interviewComplete {
                phase = .finished
            } else {
                phase = .ready
                markQuestionReady()
            }
        } catch {
            phase = .error(Self.friendly(error))
        }
    }

    private static func friendly(_ error: Error) -> String {
        NetworkError.userMessage(for: error)
    }
}
