import XCTest

final class GeminiRetryTests: XCTestCase {
    func testOverloadAndServerErrorsTryTheNextModel() {
        XCTAssertTrue(GeminiError.http(429, "quota").triesNextModel)
        XCTAssertTrue(GeminiError.http(500, "internal").triesNextModel)
        XCTAssertTrue(GeminiError.http(503, "high demand").triesNextModel)
        XCTAssertTrue(GeminiError.empty.triesNextModel)
    }

    func testRequestErrorsDoNotTryTheNextModel() {
        XCTAssertFalse(GeminiError.http(400, "bad request").triesNextModel)
        XCTAssertFalse(GeminiError.missingKey.triesNextModel)
    }

    func testTimeoutsAndDroppedConnectionsTryTheNextModel() {
        XCTAssertTrue(GeminiError.triesNextModel(after: URLError(.timedOut)))
        XCTAssertTrue(GeminiError.triesNextModel(after: URLError(.networkConnectionLost)))
        XCTAssertFalse(GeminiError.triesNextModel(after: URLError(.notConnectedToInternet)))
        XCTAssertFalse(GeminiError.triesNextModel(after: CancellationError()))
    }

    func testUnreadableJSONTriesTheNextModel() {
        let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "cut off"))
        XCTAssertTrue(GeminiError.triesNextModel(after: error))
    }
}
