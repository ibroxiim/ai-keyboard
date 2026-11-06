import XCTest

final class APIKeyTests: XCTestCase {
    func testPastedKeysLoseSpacesAndLineBreaks() {
        XCTAssertEqual(APIKey.normalized("  AIza Sy-12_3\n"), "AIzaSy-12_3")
        XCTAssertNil(APIKey.normalized(" \n\t "))
        XCTAssertNil(APIKey.normalized(""))
    }

    func testTheUsersKeyWinsOverTheBuildKey() {
        XCTAssertEqual(APIKey.resolve(user: " mine ", build: "build"), "mine")
        XCTAssertEqual(APIKey.resolve(user: nil, build: "build"), "build")
        XCTAssertEqual(APIKey.resolve(user: "  ", build: "build"), "build")
        XCTAssertEqual(APIKey.resolve(user: nil, build: ""), "")
    }

    func testMaskingShowsOnlyTheLastFour() {
        XCTAssertEqual(APIKey.masked("AIzaSyABCDwxyz"), "••••wxyz")
        XCTAssertEqual(APIKey.masked("abc"), "•••")
        XCTAssertFalse(APIKey.masked("AIzaSyABCDwxyz").contains("AIza"))
    }

    func testGoogleRefusingTheKeyMeansDoNotSave() {
        for code in [400, 401, 403] {
            let outcome = APIKey.outcome(of: GeminiError.http(code, "API key not valid"))
            XCTAssertEqual(outcome, .rejected("Kalit noto'g'ri yoki faol emas"))
            XCTAssertFalse(outcome.shouldSave)
        }
        XCTAssertFalse(APIKey.outcome(of: GeminiError.missingKey).shouldSave)
    }

    func testAnythingUncertainStillSavesButSaysSo() {
        XCTAssertEqual(APIKey.outcome(of: nil), .valid)
        XCTAssertTrue(APIKey.outcome(of: nil).shouldSave)
        let quota = APIKey.outcome(of: GeminiError.http(429, "quota"))
        XCTAssertEqual(quota, .unverified("Gemini 429: quota"))
        XCTAssertTrue(quota.shouldSave)
        let offline = APIKey.outcome(of: URLError(.notConnectedToInternet))
        guard case .unverified = offline else { return XCTFail("offline should be unverified") }
        XCTAssertTrue(offline.shouldSave)
    }
}
