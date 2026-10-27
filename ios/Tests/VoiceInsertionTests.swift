import XCTest

final class VoiceInsertionTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 810_000_000)

    private func voice(_ phase: VoiceState.Phase, id: String = "a", text: String? = nil, error: String? = nil,
                       since: TimeInterval = 0) -> VoiceState {
        VoiceState(id: id, phase: phase, since: now + since, text: text, error: error)
    }

    // MARK: Decision

    func testOwnFinishedSessionIsInsertedAtOnce() {
        XCTAssertEqual(
            VoiceInsertion.decision(voice: voice(.done, text: "salom"), pendingID: "a", now: now),
            .insert("salom"))
    }

    func testSomeoneElsesResultIsOnlyOffered() {
        XCTAssertEqual(
            VoiceInsertion.decision(voice: voice(.done, id: "b", text: "salom"), pendingID: "a", now: now),
            .offer("salom"))
        XCTAssertEqual(
            VoiceInsertion.decision(voice: voice(.done, text: "salom"), pendingID: nil, now: now),
            .offer("salom"))
    }

    func testNothingToDoUntilTheSessionIsDone() {
        XCTAssertEqual(VoiceInsertion.decision(voice: nil, pendingID: "a", now: now), .none)
        XCTAssertEqual(VoiceInsertion.decision(voice: voice(.recording), pendingID: "a", now: now), .none)
        XCTAssertEqual(VoiceInsertion.decision(voice: voice(.transcribing), pendingID: "a", now: now), .none)
    }

    func testFailureIsReportedWhoeverAskedForIt() {
        XCTAssertEqual(
            VoiceInsertion.decision(voice: voice(.failed, error: "Ovoz eshitilmadi"), pendingID: "a", now: now),
            .failed("Ovoz eshitilmadi"))
        XCTAssertEqual(
            VoiceInsertion.decision(voice: voice(.failed, id: "b", error: "x"), pendingID: nil, now: now), .failed("x"))
        XCTAssertEqual(VoiceInsertion.decision(voice: voice(.failed), pendingID: "a", now: now), .failed("Ovozdan matn: xato"))
    }

    func testAnOldFailureIsForgotten() {
        XCTAssertEqual(VoiceInsertion.decision(voice: voice(.failed, error: "x"), pendingID: "a", now: now + 31), .none)
    }

    func testExpiredOrEmptyResultsAreIgnored() {
        XCTAssertEqual(
            VoiceInsertion.decision(voice: voice(.done, text: "salom"), pendingID: "a", now: now + 601), .none)
        XCTAssertEqual(VoiceInsertion.decision(voice: voice(.done, text: ""), pendingID: "a", now: now), .none)
        XCTAssertEqual(VoiceInsertion.decision(voice: voice(.done), pendingID: "a", now: now), .none)
    }

    // MARK: Text

    func testDictationContinuesTheSentenceWithASpace() {
        XCTAssertEqual(VoiceInsertion.prepared("salom", before: "men"), " salom")
    }

    func testNoSpaceAtTheStartAfterASpaceOrANewLine() {
        XCTAssertEqual(VoiceInsertion.prepared("salom", before: nil), "salom")
        XCTAssertEqual(VoiceInsertion.prepared("salom", before: ""), "salom")
        XCTAssertEqual(VoiceInsertion.prepared("salom", before: "men "), "salom")
        XCTAssertEqual(VoiceInsertion.prepared("salom", before: "men\n"), "salom")
    }

    func testSurroundingWhitespaceOfTheTranscriptIsDropped() {
        XCTAssertEqual(VoiceInsertion.prepared("  salom \n", before: "men"), " salom")
    }

    // MARK: Status

    private func status(_ voice: VoiceState?, pending: String? = "a", opening: TimeInterval? = nil,
                        at offset: TimeInterval = 0) -> VoiceStatus {
        VoiceStatus.of(
            voice: voice, pendingID: pending, openingSince: opening.map { now + $0 }, now: now + offset)
    }

    func testStatusFollowsTheLiveSession() {
        XCTAssertEqual(status(voice(.recording)), .recording)
        XCTAssertEqual(status(voice(.transcribing)), .transcribing)
        XCTAssertEqual(status(voice(.failed, error: "Ovoz eshitilmadi")), .failed("Ovoz eshitilmadi"))
    }

    func testFinishedResultIsReadyUnlessItIsOursToInsert() {
        XCTAssertEqual(status(voice(.done, id: "b", text: "salom")), .ready("salom"))
        XCTAssertEqual(status(voice(.done, text: "salom")), .idle)
    }

    func testWaitingForTheAppToAnswer() {
        XCTAssertEqual(status(nil, opening: 0, at: 2), .opening)
        XCTAssertEqual(status(nil, opening: 0, at: 6), .openFailed)
        XCTAssertEqual(status(nil), .idle)
    }

    func testAnsweringAppEndsTheWait() {
        XCTAssertEqual(status(voice(.recording), opening: 0, at: 2), .recording)
    }

    func testDeadSessionLooksLikeNone() {
        XCTAssertEqual(status(voice(.recording), at: 200), .idle)
    }
}
