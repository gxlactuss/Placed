import Foundation

/// The one piece of real state logic behind the mock interview, mirroring
/// `QuizSessionModel`: `@MainActor @Observable` so the view is a thin render of
/// it. It drives the round-trip between the mic and the `/api/interview/*`
/// routes.
///
/// Flow: `startIfNeeded` opens a session in the picked `InterviewMode` and shows
/// the opening question → the user holds to talk → releasing uploads the
/// recording, which comes back as text, and the model appends the follow-up.
/// There's no live transcript because none exists until that upload returns.
///
/// The mode and its resume context are fixed for the life of a round: the
/// backend stores both on the session, so only `start` carries them. `endSession`
/// tears the round down so the picker can start a different one.
///
/// A round ends one of three ways: the backend reports the interviewer walked out
/// (`wasEndedByInterviewer`), the backend reports a natural close (the group
/// discussion's moderator), or the round cap here runs out — the interviewer
/// rounds have no natural end of their own, so the cap is what gives them one.
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
        case connecting   // opening the session / awaiting the first question
        case ready        // idle, waiting for the user to hold-to-talk
        case recording    // mic live, capturing to file
        case transcribing // recording uploaded, awaiting text
        case thinking     // answer submitted, awaiting the follow-up
        case finished
        case error(String)
    }

    private(set) var turns: [Turn] = []
    private(set) var round = 1
    private(set) var phase: Phase = .connecting
    private(set) var role = "Software Engineer"
    private(set) var level: Double = 0
    private(set) var micAuthorized = false
    /// The interviewer ended this round rather than it running its course. Only
    /// changes the closing copy — being thrown out shouldn't read "nice work".
    private(set) var wasEndedByInterviewer = false

    // MARK: - Debrief

    private(set) var feedback: InterviewFeedback?
    private(set) var isLoadingFeedback = false
    private(set) var feedbackError: String?

    /// Fetches the mark out of 10 and the notes on what to fix.
    ///
    /// Costs one model call the first time and nothing after — the backend caches
    /// it on the session — so the guard here is about not firing two concurrent
    /// requests, not about saving quota.
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

    let totalRounds = 5

    private var sessionId: Int?
    private var mode: InterviewMode = .coreCs
    private var context = InterviewContextPayload()
    /// Guards `startIfNeeded` against re-entry: `.task` re-runs each time the
    /// Interview tab reappears, and the opener request may still be in flight
    /// (sessionId nil, turns empty) — without this a second session could start.
    private var hasRequestedStart = false
    private let network = NetworkManager.shared
    private let voice = VoiceService()

    // MARK: - Derived state the view reads

    var isRecording: Bool { phase == .recording }
    /// Both the pre-first-question wait and the post-answer wait show a spinner.
    var isThinking: Bool { phase == .connecting || phase == .thinking || phase == .transcribing }
    var isFinished: Bool { phase == .finished }
    var errorMessage: String? { if case let .error(m) = phase { return m }; return nil }
    /// The mic is only offered when we're settled and waiting for an answer.
    var canRecord: Bool { phase == .ready }

    // MARK: - Session lifecycle

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
        // Ask for mic permission early so the first hold-to-talk just works
        // instead of racing the permission dialog.
        requestMicPermission()
        await start()
    }

    /// Tears the round down so the picker can start a different one. The mode
    /// and context are per-round, so they reset with everything else.
    func endSession() {
        if let url = voice.stopRecording() { voice.discard(url) }
        hasRequestedStart = false
        sessionId = nil
        turns = []
        round = 1
        level = 0
        wasEndedByInterviewer = false
        resetFeedback()
        phase = .connecting
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
            round = 1
            phase = .ready
        } catch {
            phase = .error(Self.friendly(error))
        }
    }

    func restart() async {
        // Drop any half-finished recording rather than leaving it in temp.
        if let url = voice.stopRecording() { voice.discard(url) }
        turns = []
        level = 0
        round = 1
        sessionId = nil
        wasEndedByInterviewer = false
        resetFeedback()
        await start()
    }

    /// Recover from an error banner: retry the opener if we never connected,
    /// otherwise drop back to waiting for another answer.
    func recover() async {
        if sessionId == nil {
            await start()
        } else {
            phase = .ready
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard canRecord else { return }

        // If permission hasn't been granted yet, ask now and let the user hold
        // again once granted, rather than starting with a dead mic.
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
            phase = .recording
        } catch {
            phase = .error(Self.friendly(error))
        }
    }

    func stopRecording() {
        guard case .recording = phase else { return }
        level = 0

        guard let url = voice.stopRecording() else { phase = .ready; return }
        phase = .transcribing
        Task { await transcribeThenRespond(url) }
    }

    /// Upload the held audio, then treat the returned text as the answer.
    private func transcribeThenRespond(_ url: URL) async {
        defer { voice.discard(url) }
        do {
            let resp: TranscriptionResponse = try await network.upload(
                path: "/api/interview/transcribe",
                fileURL: url,
                fieldName: "audio",
                mimeType: "audio/m4a"
            )
            let answer = resp.text.trimmingCharacters(in: .whitespaces)
            // Nothing audible — drop back to ready rather than submit silence.
            guard !answer.isEmpty else { phase = .ready; return }
            await appendAndRespond(answer)
        } catch {
            phase = .error(Self.friendly(error))
        }
    }

    private func appendAndRespond(_ answer: String) async {
        turns.append(Turn(speaker: .user, text: answer, isFollowUp: false))
        await respond(answer: answer)
    }


    // MARK: - Networking the answer

    private func respond(answer: String) async {
        guard let sessionId else {
            phase = .error("The interview session was lost. Start over to continue.")
            return
        }
        phase = .thinking
        do {
            let resp: InterviewAiResponse = try await network.request(
                path: "/api/interview/respond",
                method: .post,
                body: InterviewAnswerSubmitRequest(sessionId: sessionId, transcribedAnswer: answer)
            )
            turns.append(Turn(speaker: .ai, text: resp.aiMessage, isFollowUp: true))
            round += 1
            wasEndedByInterviewer = resp.endedEarly ?? false
            phase = (resp.interviewComplete || round > totalRounds) ? .finished : .ready
        } catch {
            phase = .error(Self.friendly(error))
        }
    }

    // MARK: - Error text

    /// Prefer the backend's `detail` string over the wrapped "Server error (n)".
    private static func friendly(_ error: Error) -> String {
        if case let NetworkError.server(_, body) = error,
           let data = body.data(using: .utf8),
           let detail = try? JSONDecoder().decode(ServerDetail.self, from: data) {
            return detail.detail
        }
        if case NetworkError.unauthorized = error {
            return "Your session expired. Log in again to continue."
        }
        return error.localizedDescription
    }

    private struct ServerDetail: Decodable { let detail: String }
}
