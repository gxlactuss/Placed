import AVFoundation
import Speech

/// Wraps Apple's Speech framework (speech-to-text) and AVSpeechSynthesizer
/// (text-to-speech) so the ViewModel layer only deals with plain callbacks.
final class SpeechRecognizerService: NSObject {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private let synthesizer = AVSpeechSynthesizer()

    enum SpeechError: LocalizedError {
        case recognizerUnavailable
        case noAudioInput

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "Speech recognition isn't available right now — check your network connection and try again."
            case .noAudioInput:
                return "No microphone input was found. On the Simulator, enable I/O ▸ Audio Input and allow the mic in macOS System Settings ▸ Privacy ▸ Microphone."
            }
        }
    }

    /// Requests **both** speech-recognition and microphone permission. Both are
    /// required to record, and requesting them up front (rather than on the
    /// first hold) keeps the permission dialogs from racing the hold gesture.
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            guard speechStatus == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVAudioApplication.requestRecordPermission { micGranted in
                DispatchQueue.main.async { completion(micGranted) }
            }
        }
    }

    /// Streams live partial transcriptions via `onPartialResult` until `stopListening()` is called.
    /// `onLevel` (0...1) reports the microphone input level so the UI can animate a halo.
    /// Call only once permissions are granted (see `requestPermissions`).
    func startListening(
        onPartialResult: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void,
        onLevel: ((Double) -> Void)? = nil
    ) throws {
        task?.cancel()
        task = nil

        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer server recognition so it still works before the on-device model
        // is downloaded (notably on the Simulator).
        request.requiresOnDeviceRecognition = false
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // A zero sample rate means the input node has no audio route — starting
        // the tap would crash, so fail with a clear message instead.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechError.noAudioInput
        }

        task = recognizer.recognitionTask(with: request) { result, error in
            if let result { onPartialResult(result.bestTranscription.formattedString) }
            if let error { onError(error) }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)

            if let onLevel, let channel = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                guard frames > 0 else { return }
                var sumSquares: Float = 0
                for i in 0..<frames { sumSquares += channel[i] * channel[i] }
                let rms = (sumSquares / Float(frames)).squareRoot()
                // Map RMS to a lively 0...1 range; speech rarely exceeds ~0.3 RMS.
                let level = min(1.0, Double(rms) * 12)
                DispatchQueue.main.async { onLevel(level) }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        // Release the session so other audio resumes and the next recording can
        // reconfigure cleanly.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Speaks the AI interviewer's response aloud.
    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}
