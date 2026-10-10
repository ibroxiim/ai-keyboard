import XCTest

@MainActor
final class VoiceControllerTests: XCTestCase {
    private final class FakeRecorder: AudioRecording {
        var startError: Error?
        var file: URL?
        private(set) var startCount = 0

        func start() async throws {
            startCount += 1
            if let startError { throw startError }
        }

        func stop() -> URL? { file }
    }

    private final class Store {
        var state = SharedState()
    }

    private let recorder = FakeRecorder()
    private let store = Store()
    private var files: [URL] = []

    override func tearDown() {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private func audioFile(bytes: Int) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 7, count: bytes))
        files.append(url)
        return url
    }

    private func controller(
        limit: Duration = .seconds(90),
        transcriber: @escaping (Data) async throws -> String = { _ in "salom" }
    ) -> VoiceController {
        VoiceController(
            recorder: recorder, recordingLimit: limit, transcriber: transcriber,
            update: { [store] change in change(&store.state) })
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // MARK: Recording

    func testStartPublishesRecording() async {
        let controller = controller()
        await controller.start(id: "a")
        XCTAssertEqual(controller.state?.phase, .recording)
        XCTAssertEqual(store.state.voice?.id, "a")
        XCTAssertEqual(store.state.voice?.phase, .recording)
        XCTAssertEqual(recorder.startCount, 1)
    }

    func testSecondStartWhileRecordingIsIgnored() async {
        let controller = controller()
        await controller.start(id: "a")
        await controller.start(id: "b")
        XCTAssertEqual(controller.state?.id, "a")
        XCTAssertEqual(recorder.startCount, 1)
    }

    func testMicrophoneDeniedFailsWithItsExplanation() async {
        recorder.startError = VoiceError.microphoneDenied
        let controller = controller()
        await controller.start(id: "a")
        XCTAssertEqual(controller.state?.phase, .failed)
        XCTAssertTrue(controller.state?.error?.contains("Mikrofon") == true)
        XCTAssertEqual(store.state.voice?.phase, .failed)
    }

    // MARK: Transcription

    func testStopTranscribesPublishesTheTextAndDeletesTheFile() async {
        let file = audioFile(bytes: 5_000)
        recorder.file = file
        let controller = controller { data in
            XCTAssertEqual(data.count, 5_000)
            return "men bozorga bordim"
        }
        await controller.start(id: "a")
        controller.stop()
        XCTAssertEqual(controller.state?.phase, .transcribing)
        await controller.work?.value
        XCTAssertEqual(controller.state?.phase, .done)
        XCTAssertEqual(controller.state?.text, "men bozorga bordim")
        XCTAssertEqual(store.state.voice?.text, "men bozorga bordim")
        XCTAssertFalse(exists(file))
        XCTAssertFalse(controller.canRetry)
    }

    func testAlmostEmptyFileFailsAtOnceAndIsDeleted() async {
        let file = audioFile(bytes: 100)
        recorder.file = file
        let controller = controller()
        await controller.start(id: "a")
        controller.stop()
        XCTAssertEqual(controller.state?.phase, .failed)
        XCTAssertEqual(controller.state?.error, "Ovoz eshitilmadi")
        XCTAssertFalse(exists(file))
    }

    func testNoSpeechFromTheModelDeletesTheFile() async {
        let file = audioFile(bytes: 5_000)
        recorder.file = file
        let controller = controller { _ in throw VoiceError.noSpeech }
        await controller.start(id: "a")
        controller.stop()
        await controller.work?.value
        XCTAssertEqual(controller.state?.error, "Ovoz eshitilmadi")
        XCTAssertFalse(exists(file))
        XCTAssertFalse(controller.canRetry)
    }

    func testNetworkFailureKeepsTheFileSoItCanBeRetried() async {
        let file = audioFile(bytes: 5_000)
        recorder.file = file
        var calls = 0
        let controller = controller { _ in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return "yana urinib ko'rdim"
        }
        await controller.start(id: "a")
        controller.stop()
        await controller.work?.value
        XCTAssertEqual(controller.state?.phase, .failed)
        XCTAssertTrue(controller.state?.error?.contains("Internet") == true)
        XCTAssertTrue(controller.canRetry)
        XCTAssertTrue(exists(file))

        controller.retry()
        await controller.work?.value
        XCTAssertEqual(controller.state?.text, "yana urinib ko'rdim")
        XCTAssertFalse(exists(file))
    }

    func testRecordingLimitStopsAndTranscribesByItself() async throws {
        recorder.file = audioFile(bytes: 5_000)
        let controller = controller(limit: .milliseconds(50))
        await controller.start(id: "a")
        try await Task.sleep(for: .milliseconds(400))
        await controller.work?.value
        XCTAssertEqual(controller.state?.phase, .done)
    }

    func testOldTranscriptionDoesNotOverwriteANewSession() async {
        recorder.file = audioFile(bytes: 5_000)
        let controller = controller { _ in
            try await Task.sleep(for: .milliseconds(150))
            return "eski"
        }
        await controller.start(id: "a")
        controller.stop()
        await controller.start(id: "b")
        await controller.work?.value
        XCTAssertEqual(controller.state?.id, "b")
        XCTAssertEqual(controller.state?.phase, .recording)
        XCTAssertEqual(store.state.voice?.id, "b")
    }

    func testStopWithoutRecordingDoesNothing() {
        let controller = controller()
        controller.stop()
        XCTAssertNil(controller.state)
        XCTAssertNil(store.state.voice)
    }

    // MARK: Links

    func testVoiceLinkOpensTheScreenAndStartsRecording() async {
        let controller = controller()
        controller.handle(url: VoiceLink.url(id: "kb-1"))
        XCTAssertTrue(controller.showsScreen)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(controller.state?.id, "kb-1")
        XCTAssertEqual(controller.state?.phase, .recording)
    }

    func testForeignLinkChangesNothing() {
        let controller = controller()
        controller.handle(url: URL(string: "https://example.com")!)
        XCTAssertFalse(controller.showsScreen)
        XCTAssertNil(controller.state)
    }
}
