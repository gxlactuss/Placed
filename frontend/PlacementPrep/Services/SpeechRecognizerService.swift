import AVFoundation
import Speech

/// Wraps Apple's Speech framework (speech-to-text) and AVSpeechSynthesizer
/// (text-to-speech) so the ViewModel layer only deals with plain callbacks.
final class SpeechRecognizerService: NSObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let synthesizer = AVSpeechSynthesizer()

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    /// Streams live partial transcriptions via `onPartialResult` until `stopListening()` is called.
    func startListening(
        onPartialResult: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if let result {
                onPartialResult(result.bestTranscription.formattedString)
            }
            if let error {
                onError(error)
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    /// Speaks the AI interviewer's response aloud.
    func speak(_ text: String, onFinish: (() -> Void)? = nil) {
        // TODO: if onFinish callbacks are needed, set `synthesizer.delegate` to a
        // helper conforming to AVSpeechSynthesizerDelegate and invoke it there.
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}
