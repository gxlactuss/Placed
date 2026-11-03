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

    /// Why an in-progress recording stopped without the user releasing.
    enum InterruptionKind: Equatable {
        /// The audio session was interrupted: phone/FaceTime call, Siri, an alarm,
        /// or another app taking the audio session.
        case sessionInterrupted
        /// The input device went away, e.g. headphones or AirPods disconnected.
        case audioDeviceLost
        /// The recorder itself failed (encoder error or an unsuccessful finish).
        case recorderFailed
    }

    /// Fired on the main queue, at most once per recording, when a recording is
    /// cut short by the system. The recording is not stopped for you: call
    /// `stopRecording()` to finalize the file (and keep or discard it).
    var onInterrupted: ((InterruptionKind) -> Void)?

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var recordingURL: URL?
    private var onLevel: ((Double) -> Void)?
    private var recordingObservers: [NSObjectProtocol] = []
    private var didSignalInterruption = false
    private var speechInterruptionObserver: NSObjectProtocol?

    /// Seconds of audio actually captured so far, sampled from the recorder while
    /// it is running. Unlike wall-clock time, this stops growing once the system
    /// interrupts the recorder.
    private(set) var recordedSeconds: TimeInterval = 0

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        // The interviewer voice must never talk over a phone call, whether or
        // not a recording is running.
        speechInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard Self.interruptionType(note) == .began else { return }
            self?.stopSpeaking()
        }
    }

    deinit {
        if let speechInterruptionObserver {
            NotificationCenter.default.removeObserver(speechInterruptionObserver)
        }
        removeRecordingObservers()
    }

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
        recorder.delegate = self
        guard recorder.record() else { throw VoiceError.couldNotStart }

        self.recorder = recorder
        recordingURL = url
        recordedSeconds = 0
        didSignalInterruption = false
        addRecordingObservers()

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder, let onLevel = self.onLevel else { return }
            if recorder.isRecording { self.recordedSeconds = recorder.currentTime }
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
        removeRecordingObservers()
        if let recorder, recorder.isRecording { recordedSeconds = recorder.currentTime }
        // Our own stop is not a failure; don't let it reach the delegate.
        recorder?.delegate = nil
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

    func stopSpeaking() {
        guard synthesizer.isSpeaking || synthesizer.isPaused else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Interruptions

    private func addRecordingObservers() {
        removeRecordingObservers()
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        recordingObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            // Only the start matters: recording is never resumed automatically
            // when the interruption ends.
            guard Self.interruptionType(note) == .began else { return }
            self?.signalInterruption(.sessionInterrupted)
        })

        recordingObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
            else { return }
            self?.signalInterruption(.audioDeviceLost)
        })
    }

    private func removeRecordingObservers() {
        for observer in recordingObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        recordingObservers = []
    }

    /// Must run on the main queue.
    private func signalInterruption(_ kind: InterruptionKind) {
        guard recorder != nil, !didSignalInterruption else { return }
        didSignalInterruption = true
        stopSpeaking()
        onInterrupted?(kind)
    }

    private static func interruptionType(_ note: Notification) -> AVAudioSession.InterruptionType? {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return nil }
        return AVAudioSession.InterruptionType(rawValue: raw)
    }
}

extension VoiceService: AVAudioRecorderDelegate {
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, recorder === self.recorder else { return }
            self.signalInterruption(.recorderFailed)
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // stopRecording() detaches the delegate first, so this only fires when
        // the recorder finished on its own.
        guard !flag else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, recorder === self.recorder else { return }
            self.signalInterruption(.recorderFailed)
        }
    }
}
