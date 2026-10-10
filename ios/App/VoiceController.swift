import Combine
import Foundation

/// The microphone side of `VoiceController`, behind a protocol so the flow is tested without a microphone.
@MainActor
protocol AudioRecording: AnyObject {
    /// Starts recording into a fresh file; throws `VoiceError.microphoneDenied` or `.recordingFailed`.
    func start() async throws
    /// Ends the recording and returns its file; nil when nothing was recorded.
    func stop() -> URL?
}

/// Records a voice message, has it transcribed and publishes each step in `SharedState.voice` so the keyboard can
/// follow along and pick the text up.
@MainActor
final class VoiceController: ObservableObject {
    typealias StoreUpdate = ((inout SharedState) -> Void) -> Void

    /// What this controller last published; the "Gapirish" screen reads it.
    @Published private(set) var state: VoiceState?
    /// The "Gapirish" sheet.
    @Published var showsScreen = false

    /// A file smaller than this holds no speech worth sending — a tap, a muted microphone.
    static let minimumBytes = 3_000

    private let recorder: AudioRecording
    private let recordingLimit: Duration
    private let transcriber: (Data) async throws -> String
    private let update: StoreUpdate
    private let runInBackground: (@escaping () async -> Void) async -> Void

    private var limitTask: Task<Void, Never>?
    /// The latest transcription, for tests to wait on.
    private(set) var work: Task<Void, Never>?
    /// Kept after a failed transcription so "Qayta urinish" can send the same recording again.
    private var heldFile: URL?
    private var starting = false
    /// Bumped by every new session; a transcription of an older one must not overwrite the newer.
    private var generation = 0

    init(
        recorder: AudioRecording,
        recordingLimit: Duration = .seconds(VoiceState.recordingLimit),
        transcriber: @escaping (Data) async throws -> String,
        update: @escaping StoreUpdate,
        // The app may be in the background when the keyboard's ⏹ arrives; the real one asks iOS for time to finish.
        runInBackground: @escaping (@escaping () async -> Void) async -> Void = { await $0() }
    ) {
        self.recorder = recorder
        self.recordingLimit = recordingLimit
        self.transcriber = transcriber
        self.update = update
        self.runInBackground = runInBackground
    }

    var canRetry: Bool { heldFile != nil }

    // MARK: Entry points

    /// `aikeyboard://voice?id=…` from the keyboard.
    func handle(url: URL) {
        guard let id = VoiceLink.parse(url) else { return }
        showsScreen = true
        Task { await start(id: id) }
    }

    /// The "Gapirish" row in the app.
    func startManually() {
        showsScreen = true
        Task { await start(id: UUID().uuidString) }
    }

    // MARK: Recording

    func start(id: String) async {
        guard state?.phase != .recording, !starting else { return }
        starting = true
        defer { starting = false }
        generation += 1
        discardHeldFile()
        do {
            try await recorder.start()
        } catch {
            publish(VoiceState(id: id, phase: .failed, since: Date(), error: Self.message(for: error)))
            return
        }
        publish(VoiceState(id: id, phase: .recording, since: Date()))
        let limit = recordingLimit
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// From the screen, the keyboard's ⏹, the limit or an interruption.
    func stop() {
        guard let current = state, current.phase == .recording else { return }
        limitTask?.cancel()
        limitTask = nil
        let recorded = recorder.stop()
        guard let file = recorded, Self.size(of: file) >= Self.minimumBytes else {
            if let recorded { remove(recorded) }
            publish(VoiceState(id: current.id, phase: .failed, since: Date(), error: VoiceError.noSpeech.localizedDescription))
            return
        }
        publish(VoiceState(id: current.id, phase: .transcribing, since: Date()))
        beginTranscription(of: file, id: current.id)
    }

    func retry() {
        guard let current = state, current.phase == .failed, let file = heldFile else { return }
        publish(VoiceState(id: current.id, phase: .transcribing, since: Date()))
        beginTranscription(of: file, id: current.id)
    }

    // MARK: Transcription

    private func beginTranscription(of file: URL, id: String) {
        let generation = generation
        work = Task { [weak self] in
            guard let self else { return }
            await runInBackground { [weak self] in
                await self?.finish(file: file, id: id, generation: generation)
            }
        }
    }

    private func finish(file: URL, id: String, generation: Int) async {
        let outcome: Result<String, Error>
        do {
            outcome = .success(try await transcriber(try Data(contentsOf: file)))
        } catch {
            outcome = .failure(error)
        }
        let current = generation == self.generation
        switch outcome {
        case .success(let text):
            remove(file)
            heldFile = nil
            if current { publish(VoiceState(id: id, phase: .done, since: Date(), text: text)) }
        case .failure(let error):
            // "No speech" would come out the same again; anything else (network, overload) is worth another try.
            if current, (error as? VoiceError) != .noSpeech {
                heldFile = file
            } else {
                remove(file)
                if current { heldFile = nil }
            }
            if current {
                publish(VoiceState(id: id, phase: .failed, since: Date(), error: Self.message(for: error)))
            }
        }
    }

    // MARK: Helpers

    private func publish(_ new: VoiceState?) {
        state = new
        update { $0.voice = new }
    }

    private func discardHeldFile() {
        if let heldFile { remove(heldFile) }
        heldFile = nil
    }

    private func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
    }

    private static func size(of file: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
    }

    private static func message(for error: Error) -> String {
        if error is URLError { return "Internet bilan muammo — qayta urinib ko'ring" }
        return error.localizedDescription
    }
}
