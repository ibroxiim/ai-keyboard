import XCTest

final class VoiceStateTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 810_000_000)

    private func voice(_ phase: VoiceState.Phase, since: TimeInterval = 0) -> VoiceState {
        VoiceState(
            id: "a", phase: phase, since: now + since,
            text: phase == .done ? "salom" : nil, error: phase == .failed ? "xato" : nil)
    }

    func testEachPhaseHasItsOwnLifetime() {
        XCTAssertTrue(voice(.recording).isLive(at: now + 99))
        XCTAssertFalse(voice(.recording).isLive(at: now + 100))
        XCTAssertTrue(voice(.transcribing).isLive(at: now + 59))
        XCTAssertFalse(voice(.transcribing).isLive(at: now + 60))
        XCTAssertTrue(voice(.done).isLive(at: now + 599))
        XCTAssertFalse(voice(.done).isLive(at: now + 600))
        XCTAssertTrue(voice(.failed).isLive(at: now + 29))
        XCTAssertFalse(voice(.failed).isLive(at: now + 30))
    }

    func testRecordingOutlastsTheRecordingLimit() {
        XCTAssertEqual(VoiceState.recordingLimit, 90)
        XCTAssertGreaterThan(VoiceState.lifetime(of: .recording), VoiceState.recordingLimit)
    }

    func testActiveVoiceHidesADeadSession() {
        var state = SharedState()
        state.voice = voice(.recording)
        XCTAssertNotNil(state.activeVoice(at: now + 50))
        XCTAssertNil(state.activeVoice(at: now + 100))
        XCTAssertNil(SharedState().activeVoice(at: now))
    }

    func testNextDeadlineIncludesTheVoiceExpiry() {
        var state = SharedState()
        state.voice = voice(.recording)
        XCTAssertEqual(state.nextDeadline(after: now), now + 100)
        state.contextDate = now - 880 // goes stale at now + 20, sooner than the voice session
        XCTAssertEqual(state.nextDeadline(after: now), now + 20)
    }

    func testVoiceSurvivesTheSharedFileRoundTrip() throws {
        var state = SharedState()
        state.voice = voice(.done)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(SharedState.self, from: data).voice, state.voice)
    }

    func testStateFilesWithoutVoiceStillLoad() throws {
        let data = try JSONEncoder().encode(SharedState())
        XCTAssertNil(try JSONDecoder().decode(SharedState.self, from: data).voice)
    }

    // MARK: Link

    func testLinkRoundTripsTheSessionID() {
        XCTAssertEqual(VoiceLink.parse(VoiceLink.url(id: "abc-123")), "abc-123")
    }

    func testForeignLinksAreIgnored() {
        XCTAssertNil(VoiceLink.parse(URL(string: "https://example.com/voice?id=1")!))
        XCTAssertNil(VoiceLink.parse(URL(string: "aikeyboard://other?id=1")!))
    }

    func testLinkWithoutIDGetsAFreshOne() throws {
        let id = try XCTUnwrap(VoiceLink.parse(URL(string: "aikeyboard://voice")!))
        XCTAssertFalse(id.isEmpty)
    }
}
