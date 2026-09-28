import XCTest

final class SharedStateDeadlineTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testNoDeadlineWithoutTimedState() {
        XCTAssertNil(SharedState().nextDeadline(after: now))
    }

    func testEarliestFutureDeadlineWins() {
        var state = SharedState()
        state.analyzingSince = now.addingTimeInterval(-10) // times out at now + 50
        state.lastErrorDate = now.addingTimeInterval(-100) // expires at now + 20
        state.contextDate = now // goes stale at now + 900
        XCTAssertEqual(state.nextDeadline(after: now), now.addingTimeInterval(20))
    }

    func testPassedDeadlinesAreSkipped() {
        var state = SharedState()
        state.analyzingSince = now.addingTimeInterval(-120) // already timed out
        state.contextDate = now.addingTimeInterval(-60) // goes stale at now + 840
        XCTAssertEqual(state.nextDeadline(after: now), now.addingTimeInterval(840))
    }

    func testStuckAnalysisStopsAtTimeout() {
        var state = SharedState()
        state.analyzingSince = now
        XCTAssertTrue(state.isAnalyzing(at: now.addingTimeInterval(59)))
        XCTAssertFalse(state.isAnalyzing(at: now.addingTimeInterval(60)))
    }

    func testErrorLineExpires() {
        var state = SharedState()
        state.lastError = "Gemini 503"
        state.lastErrorDate = now
        XCTAssertEqual(state.recentError(at: now.addingTimeInterval(119)), "Gemini 503")
        XCTAssertNil(state.recentError(at: now.addingTimeInterval(120)))
    }
}
