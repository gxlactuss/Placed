import Foundation

enum InterviewUIState: Equatable {
    case idle
    case aiSpeaking
    case listeningForAnswer
    case submittingAnswer
    case finished
    case error(String)
}

@MainActor
final class MockInterviewViewModel: ObservableObject {
    @Published var uiState: InterviewUIState = .idle
    @Published var transcript: [InterviewTurn] = []
    @Published var liveTranscription: String = ""

    private var sessionId: Int?
    private let speechService = SpeechRecognizerService()
    private let network = NetworkManager.shared

    func startInterview(targetRole: String) async {
        uiState = .aiSpeaking
        do {
            let response: InterviewAiResponse = try await network.request(
                path: "/api/interview/start",
                method: .post,
                body: InterviewStartRequest(targetRole: targetRole)
            )
            sessionId = response.sessionId
            appendTurn(speaker: "ai", text: response.aiMessage)
            speakAndThenListen(response.aiMessage)
        } catch {
            uiState = .error(error.localizedDescription)
        }
    }

    /// Called once the user taps "Speak" — begins live mic transcription.
    func beginListening() {
        uiState = .listeningForAnswer
        liveTranscription = ""

        speechService.requestAuthorization { [weak self] authorized in
            guard let self, authorized else {
                self?.uiState = .error("Microphone/speech permission denied.")
                return
            }
            do {
                try self.speechService.startListening(
                    onPartialResult: { [weak self] text in
                        self?.liveTranscription = text
                    },
                    onError: { [weak self] error in
                        self?.uiState = .error(error.localizedDescription)
                    }
                )
            } catch {
                self.uiState = .error(error.localizedDescription)
            }
        }
    }

    /// Called when the user taps "Done Speaking" — stops the mic and submits the answer.
    func finishAnsweringAndSubmit() async {
        speechService.stopListening()
        let answer = liveTranscription
        guard !answer.isEmpty, let sessionId else { return }

        appendTurn(speaker: "user", text: answer)
        uiState = .submittingAnswer

        do {
            let response: InterviewAiResponse = try await network.request(
                path: "/api/interview/respond",
                method: .post,
                body: InterviewAnswerSubmitRequest(sessionId: sessionId, transcribedAnswer: answer)
            )
            appendTurn(speaker: "ai", text: response.aiMessage)

            if response.interviewComplete {
                speakAndThenFinish(response.aiMessage)
            } else {
                speakAndThenListen(response.aiMessage)
            }
        } catch {
            uiState = .error(error.localizedDescription)
        }
    }

    private func speakAndThenListen(_ text: String) {
        uiState = .aiSpeaking
        // TODO: use AVSpeechSynthesizerDelegate completion instead of a fixed
        // "speaking" state transition, so listening only begins once TTS finishes.
        speechService.speak(text)
        uiState = .idle
    }

    private func speakAndThenFinish(_ text: String) {
        uiState = .aiSpeaking
        speechService.speak(text)
        uiState = .finished
    }

    private func appendTurn(speaker: String, text: String) {
        transcript.append(InterviewTurn(speaker: speaker, text: text, at: Date()))
    }
}
