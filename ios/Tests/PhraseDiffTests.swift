import XCTest

final class PhraseDiffTests: XCTestCase {
    func testIdenticalTextIsPerfect() {
        XCTAssertTrue(PhraseDiff.compare(expected: "salom dunyo", typed: "salom dunyo").isPerfect)
    }

    func testMissingLetterIsCounted() {
        XCTAssertEqual(PhraseDiff.compare(expected: "salom dunyo", typed: "salm dunyo"), PhraseDiff(missing: 1))
    }

    func testExtraLetterIsCounted() {
        XCTAssertEqual(PhraseDiff.compare(expected: "salom", typed: "saloom"), PhraseDiff(extra: 1))
    }

    func testWrongLetterIsCounted() {
        XCTAssertEqual(PhraseDiff.compare(expected: "salom", typed: "salim"), PhraseDiff(substituted: 1))
    }

    func testApostropheVariantsAndCaseDoNotCount() {
        XCTAssertTrue(PhraseDiff.compare(expected: "Do'st", typed: "doʻst").isPerfect)
        XCTAssertTrue(PhraseDiff.compare(expected: "do'st", typed: "do’st ").isPerfect)
    }

    func testEmptyTypedTextMissesEverything() {
        XCTAssertEqual(PhraseDiff.compare(expected: "abc", typed: ""), PhraseDiff(missing: 3))
    }

    func testTestPhraseIsAboutTwoHundredCharacters() {
        XCTAssertTrue((150...230).contains(PhraseDiff.testPhrase.count))
    }
}
