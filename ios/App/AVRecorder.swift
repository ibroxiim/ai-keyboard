import AVFoundation

/// `AudioRecording` on the real microphone. The session is activated while the app is in the foreground; with the
/// `audio` background mode iOS then lets the recording run on after the user returns to the chat.
@MainActor
final class AVRecorder: AudioRecording {
    private var recorder: AVAudioRecorder?
    private var interruptionObserver: NSObjectProtocol?

    /// A call or another app took the audio: the recording so far is what there will be.
    var onInterruption: (() -> Void)?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceError.microphoneDenied }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
            // Speech does not need more: 16 kHz mono at 32 kbit/s is ~260 KB for the longest (90 s) message.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else { throw VoiceError.recordingFailed }
            self.recorder = recorder
        } catch let error as VoiceError {
            throw error
        } catch {
            throw VoiceError.recordingFailed
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began
            else { return }
            MainActor.assumeIsolated { self?.onInterruption?() }
        }
    }

    func stop() -> URL? {
        let url = recorder?.url
        recorder?.stop()
        recorder = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }
}
