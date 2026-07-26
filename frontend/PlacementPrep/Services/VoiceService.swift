import AVFoundation

/// Records the candidate's spoken answer, and speaks the interviewer's replies
/// back.
///
/// Deliberately does **not** transcribe. It hands the finished recording to the
/// caller, which uploads it to `POST /api/interview/transcribe` (Groq Whisper).
/// Keeping the network out of here leaves this class single-purpose.
///
/// This used to wrap Apple's `SFSpeechRecognizer`, which transcribed on-device
/// and streamed partial text as you spoke — strictly nicer when it worked. It
/// was removed because it cannot initialise in the Simulator: no on-device model
/// ships there, and the server recogniser fails with `kAFAssistantErrorDomain
/// 1101 "Failed to initialize recognizer"`. Carrying a second path that only
/// worked on physical hardware cost more than the live text was worth. If you
/// ever reinstate it, gate it on `supportsOnDeviceRecognition` — the *server*
/// recogniser is the part that doesn't work.
final class VoiceService: NSObject {

    enum VoiceError: LocalizedError {
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .couldNotStart:
                return "Couldn't start recording. Check microphone access — on the Simulator, enable I/O ▸ Microphone and allow it in macOS System Settings ▸ Privacy ▸ Microphone."
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var recordingURL: URL?
    private var onLevel: ((Double) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    /// Microphone only — nothing here uses the Speech framework, so asking for
    /// speech-recognition authorisation would be a prompt we never need (and one
    /// that can fail on the Simulator for no good reason).
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Starts capturing. `onLevel` (0...1) drives the mic halo.
    func startRecording(onLevel: @escaping (Double) -> Void) throws {
        self.onLevel = onLevel

        let session = AVAudioSession.sharedInstance()
        // `.default` rather than `.measurement`: measurement mode disables input
        // processing, which makes for a noticeably worse recording to upload.
        try session.setCategory(.record, mode: .default, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("answer-\(UUID().uuidString).m4a")

        // 16 kHz mono AAC: Whisper resamples to 16 kHz anyway, so anything more
        // is upload weight for no accuracy.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw VoiceError.couldNotStart }

        self.recorder = recorder
        recordingURL = url

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder, let onLevel = self.onLevel else { return }
            recorder.updateMeters()
            // averagePower is dBFS (-160...0); speech sits around -35...-5.
            let decibels = Double(recorder.averagePower(forChannel: 0))
            onLevel(max(0, min(1, (decibels + 50) / 45)))
        }
    }

    /// Ends the hold and returns the recording, or `nil` if nothing was captured.
    /// The caller owns the file and should `discard` it once uploaded.
    @discardableResult
    func stopRecording() -> URL? {
        onLevel = nil
        levelTimer?.invalidate()
        levelTimer = nil
        recorder?.stop()
        recorder = nil
        // Release the session so other audio resumes and the next recording can
        // reconfigure cleanly.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let url = recordingURL
        recordingURL = nil
        return url
    }

    func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Speaks the AI interviewer's response aloud.
    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}
