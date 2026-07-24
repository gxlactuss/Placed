import Foundation

/// The one piece of real state logic behind the mock interview, mirroring
/// `QuizSessionModel`: `@MainActor @Observable` so the view is a thin render of
/// it. It drives the round-trip between Apple's on-device speech recogniser and
/// the Gemini-backed `/api/interview/*` routes.
///
/// Flow: `startIfNeeded` opens a session and shows the AI's opening question →
/// the user holds to talk (live partial transcription) → releasing submits the
/// transcript, and the model appends Gemini's follow-up. The backend never
/// signals completion yet (see gemini_service TODO), so the round count is
/// capped here to give the interview a real ending.
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
        case recording    // mic live, streaming partial transcription
        case thinking     // answer submitted, awaiting the follow-up
        case finished
        case error(String)
    }

    private(set) var turns: [Turn] = []
    private(set) var round = 1
    private(set) var phase: Phase = .connecting
    private(set) var role = "Software Engineer"
    var liveText = ""
    private(set) var level: Double = 0
    private(set) var micAuthorized = false

    let totalRounds = 5

    private var sessionId: Int?
    private let network = NetworkManager.shared
    private let speech = SpeechRecognizerService()

    // MARK: - Derived state the view reads

    var isRecording: Bool { phase == .recording }
    /// Both the pre-first-question wait and the post-answer wait show a spinner.
    var isThinking: Bool { phase == .connecting || phase == .thinking }
    var isFinished: Bool { phase == .finished }
    var errorMessage: String? { if case let .error(m) = phase { return m }; return nil }
    /// The mic is only offered when we're settled and waiting for an answer.
    var canRecord: Bool { phase == .ready }

    // MARK: - Session lifecycle

    func startIfNeeded(targetRole: String) async {
        guard sessionId == nil, turns.isEmpty else { return }
        role = targetRole
        // Ask for mic + speech permission early so the first hold-to-talk just
        // works instead of racing the permission dialogs.
        requestMicPermission()
        await start()
    }

    private func requestMicPermission() {
        speech.requestPermissions { [weak self] granted in
            Task { @MainActor in self?.micAuthorized = granted }
        }
    }

    private func start() async {
        phase = .connecting
        do {
            let resp: InterviewAiResponse = try await network.request(
                path: "/api/interview/start",
                method: .post,
                body: InterviewStartRequest(targetRole: role)
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
        speech.stopListening()
        turns = []
        liveText = ""
        level = 0
        round = 1
        sessionId = nil
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
            speech.requestPermissions { [weak self] granted in
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
        liveText = ""
        do {
            try speech.startListening(
                onPartialResult: { [weak self] text in
                    Task { @MainActor in self?.liveText = text }
                },
                onError: { [weak self] error in
                    Task { @MainActor in self?.handleRecordingError(error) }
                },
                onLevel: { [weak self] value in
                    Task { @MainActor in self?.level = value }
                }
            )
            phase = .recording
        } catch {
            phase = .error(Self.friendly(error))
        }
    }

    func stopRecording() {
        guard case .recording = phase else { return }

        // Leave the recording phase *before* tearing down the recogniser, so any
        // late teardown error is ignored by `handleRecordingError` and doesn't
        // clobber the answer we're about to submit.
        let answer = liveText.trimmingCharacters(in: .whitespaces)
        phase = answer.isEmpty ? .ready : .thinking
        speech.stopListening()
        level = 0
        liveText = ""

        guard !answer.isEmpty else { return }
        turns.append(Turn(speaker: .user, text: answer, isFollowUp: false))
        Task { await respond(answer: answer) }
    }

    /// Only fires for a failure *during* live recording (teardown errors are
    /// filtered by the phase guard) — so it's a real problem worth surfacing.
    private func handleRecordingError(_ error: Error) {
        guard case .recording = phase else { return }
        speech.stopListening()
        level = 0
        liveText = ""
        phase = .error(Self.friendly(error))
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
