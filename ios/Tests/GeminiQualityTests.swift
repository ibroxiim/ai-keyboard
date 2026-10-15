import XCTest

final class GeminiQualityTests: XCTestCase {
    func testFastKeepsTheLiteModelFirst() {
        XCTAssertEqual(GeminiQuality.fast.models.first, "gemini-3.5-flash-lite")
        XCTAssertEqual(GeminiQuality.fast.thinkingLevel, "minimal")
    }

    func testCarefulStartsWithTheStrongerModels() {
        XCTAssertEqual(Array(GeminiQuality.careful.models.prefix(2)), ["gemini-3.6-flash", "gemini-3.5-flash"])
        XCTAssertEqual(GeminiQuality.careful.thinkingLevel, "low")
    }

    func testBothTryTheSameModelsInTheEnd() {
        XCTAssertEqual(Set(GeminiQuality.fast.models), Set(GeminiQuality.careful.models))
    }

    func testCarefulWaitsLongerForASecondModelAndForTheFirstAnswer() {
        XCTAssertEqual(GeminiQuality.fast.hedgeDelay(media: false), .seconds(4))
        XCTAssertEqual(GeminiQuality.fast.hedgeDelay(media: true), .seconds(6))
        XCTAssertEqual(GeminiQuality.careful.hedgeDelay(media: false), .seconds(8))
        XCTAssertEqual(GeminiQuality.careful.hedgeDelay(media: true), .seconds(12))
        XCTAssertGreaterThan(GeminiQuality.careful.attemptTimeout, GeminiQuality.fast.attemptTimeout)
    }

    func testTheSettingPicksTheQuality() {
        var state = SharedState()
        XCTAssertEqual(state.quality, .fast)
        state.qualityMode = false
        XCTAssertEqual(state.quality, .fast)
        state.qualityMode = true
        XCTAssertEqual(state.quality, .careful)
    }
}
