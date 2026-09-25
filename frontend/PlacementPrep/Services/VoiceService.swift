import AVFoundation

final class VoiceService: NSObject {

    enum VoiceError: LocalizedError {
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .couldNotStart:
                return "Couldn't start recording. Check microphone access. On the Simulator, enable I/O ▸ Microphone and allow it in macOS System Settings ▸ Privacy ▸ Microphone."
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var recordingURL: URL?
    private var onLevel: ((Double) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func startRecording(onLevel: @escaping (Double) -> Void) throws {
        self.onLevel = onLevel

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("answer-\(UUID().uuidString).m4a")

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
            let decibels = Double(recorder.averagePower(forChannel: 0))
            onLevel(max(0, min(1, (decibels + 50) / 45)))
        }
    }

    @discardableResult
    func stopRecording() -> URL? {
        onLevel = nil
        levelTimer?.invalidate()
        levelTimer = nil
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let url = recordingURL
        recordingURL = nil
        return url
    }

    func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}
