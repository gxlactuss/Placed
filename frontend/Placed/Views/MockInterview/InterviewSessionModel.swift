import Foundation

/// Owns a recorded answer on disk and deletes it when released, so a kept
/// recording can never outlive the answer it belongs to (including on deinit).
private final class RecordingFile {
    let url: URL
    init(url: URL) { self.url = url }
    deinit { try? FileManager.default.removeItem(at: url) }
}

@MainActor
@Observable
final class InterviewSessionModel {

    /// An answer that has not reached the interviewer yet. Kept after a
    /// retryable failure so "Try again" resends it instead of losing it.
    /// Before transcription it holds the recording; afterwards only the text.
    private struct PendingAnswer {
        let id = UUID()
        let speakingSeconds: Double?
        var recording: RecordingFile?
        var transcript: String?
        var transcriptTurnID: UUID?
    }

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
    /// Set when the system cut a recording short and it was too short to keep;
    /// shown in place of the usual prompt until the next recording starts.
    private(set) var interruptionNotice: String?
    private var pendingAnswer: PendingAnswer?

    /// An interrupted recording at least this long is sent as a normal answer
    /// instead of being thrown away.
    private static let minimumKeptInterruptedSeconds: TimeInterval = 1

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
    /// True when the error phase is holding an unsent answer that "Try again" can resend.
    var canRetryAnswer: Bool { errorMessage != nil && pendingAnswer != nil }

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
        pendingAnswer = nil
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
        interruptionNotice = nil
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
        pendingAnswer = nil
        turns = []
        level = 0
        resetProgress()
        sessionId = nil
        wasEndedByInterviewer = false
        resetFeedback()
        await start()
    }

    func recover() async {
        pendingAnswer = nil
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
                        self.phase = .error("Microphone access is off. Turn it on for Placed in Settings, then hold to answer again.")
                    }
                }
            }
            return
        }

        beginListening()
    }

    private func beginListening() {
        voice.onInterrupted = { [weak self] kind in
            Task { @MainActor in self?.handleInterruption(kind) }
        }
        do {
            try voice.startRecording { [weak self] value in
                Task { @MainActor in self?.level = value }
            }
            if thinkSeconds == nil, let questionReadyAt {
                thinkSeconds = Date.now.timeIntervalSince(questionReadyAt)
            }
            recordingStartedAt = .now
            didDiscardRecording = false
            interruptionNotice = nil
            pendingAnswer = nil
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
        let pending = PendingAnswer(speakingSeconds: speakingSeconds, recording: RecordingFile(url: url))
        pendingAnswer = pending
        phase = .transcribing
        Task { await submit(pending) }
    }

    /// "Try again" on a failed answer: re-uploads the kept recording, or, if it
    /// was already transcribed, resends just the text.
    func retryPendingAnswer() async {
        guard canRetryAnswer, let pendingAnswer else { return }
        phase = pendingAnswer.transcript == nil ? .transcribing : .thinking
        await submit(pendingAnswer)
    }

    /// "Record again" on a failed answer: drops the kept answer and returns to ready.
    func discardPendingAnswerAndRecordAgain() {
        guard errorMessage != nil else { return }
        if let turnID = pendingAnswer?.transcriptTurnID {
            turns.removeAll { $0.id == turnID }
        }
        pendingAnswer = nil
        didDiscardRecording = true
        phase = .ready
    }

    func cancelRecording() {
        guard case .recording = phase else { return }
        level = 0
        recordingStartedAt = nil
        if let url = voice.stopRecording() { voice.discard(url) }
        didDiscardRecording = true
        phase = .ready
    }

    /// The system cut the recording short (call, Siri, alarm, headphones
    /// unplugged, recorder failure). Never resumes recording on its own.
    private func handleInterruption(_ kind: VoiceService.InterruptionKind) {
        voice.stopSpeaking()
        guard case .recording = phase else { return }

        // Keep what was said so far if it's long enough to be an answer: this is
        // exactly a normal release, so it goes through pendingAnswer/submit.
        // A failed recorder's file can't be trusted, so it is always dropped.
        if kind != .recorderFailed, voice.recordedSeconds >= Self.minimumKeptInterruptedSeconds {
            stopRecording()
            return
        }

        level = 0
        recordingStartedAt = nil
        if let url = voice.stopRecording() { voice.discard(url) }
        interruptionNotice = kind == .recorderFailed
            ? "Recording stopped unexpectedly. Hold to answer again."
            : "Recording stopped because of an interruption (call or audio device change). Hold to answer again."
        phase = .ready
    }

    /// Sends a pending answer: transcribes the recording if needed, then submits
    /// the text. Retryable failures keep `pendingAnswer`; anything else drops it.
    private func submit(_ pending: PendingAnswer) async {
        var pending = pending
        if pending.transcript == nil {
            guard let recording = pending.recording else {
                pendingAnswer = nil
                phase = .ready
                return
            }
            phase = .transcribing
            do {
                let resp: TranscriptionResponse = try await network.upload(
                    path: "/api/interview/transcribe",
                    fileURL: recording.url,
                    fieldName: "audio",
                    mimeType: "audio/m4a"
                )
                // The user may have left or restarted while this was in flight.
                guard pendingAnswer?.id == pending.id else { return }
                let answer = resp.text.trimmingCharacters(in: .whitespaces)
                guard !answer.isEmpty else {
                    pendingAnswer = nil
                    phase = .ready
                    return
                }
                let turn = Turn(speaker: .user, text: answer, isFollowUp: false)
                turns.append(turn)
                // Keep only the text from here on; releasing the recording deletes the file.
                pending.recording = nil
                pending.transcript = answer
                pending.transcriptTurnID = turn.id
                pendingAnswer = pending
            } catch {
                guard pendingAnswer?.id == pending.id else { return }
                fail(with: error, keeping: pending)
                return
            }
        }
        await respond(pending)
    }

    private func respond(_ pending: PendingAnswer) async {
        guard let answer = pending.transcript else { return }
        guard let sessionId else {
            pendingAnswer = nil
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
                    speakingSeconds: pending.speakingSeconds
                )
            )
            guard pendingAnswer?.id == pending.id else { return }
            pendingAnswer = nil
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
            guard pendingAnswer?.id == pending.id else { return }
            fail(with: error, keeping: pending)
        }
    }

    /// Network drops and server-side failures keep the answer for "Try again";
    /// client errors (e.g. 400/413 empty or too-long recording) discard it as before.
    private func fail(with error: Error, keeping pending: PendingAnswer) {
        let message = Self.friendly(error)
        if Self.isRetryable(error) {
            pendingAnswer = pending
            let sentence = message.hasSuffix(".") ? message : message + "."
            phase = .error("\(sentence) Your answer is saved, so you can try sending it again.")
        } else {
            pendingAnswer = nil
            phase = .error(message)
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        switch error as? NetworkError {
        case .transport:
            return true
        case .server(let statusCode, _):
            // -1 = no HTTP response; 408/429 are transient; 5xx (incl. 503) is the server's fault.
            return statusCode < 0 || statusCode == 408 || statusCode == 429 || statusCode >= 500
        default:
            return false
        }
    }

    private static func friendly(_ error: Error) -> String {
        NetworkError.userMessage(for: error)
    }
}
