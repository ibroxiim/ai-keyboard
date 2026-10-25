import XCTest

final class InstructionsImportTests: XCTestCase {
    func testUTF8FileComesBackTrimmed() {
        let text = InstructionsImport.text(from: Data("\n# Uslub\n\nOddiy yoz.\n\n".utf8))
        XCTAssertEqual(text, "# Uslub\n\nOddiy yoz.")
    }

    func testWindowsLineEndingsAreNormalised() {
        XCTAssertEqual(InstructionsImport.text(from: Data("bir\r\nikki".utf8)), "bir\nikki")
    }

    func testAByteOrderMarkIsDropped() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("salom".utf8))
        XCTAssertEqual(InstructionsImport.text(from: data), "salom")
    }

    func testUTF16FileIsRead() {
        let data = "salom dunyo".data(using: .utf16)!
        XCTAssertEqual(InstructionsImport.text(from: data), "salom dunyo")
    }

    func testALongFileIsCutAtTheLimit() {
        let text = InstructionsImport.text(from: Data(String(repeating: "a", count: 10_000).utf8))
        XCTAssertEqual(text?.count, Prompts.styleLimit)
    }

    func testBinaryGarbageIsRefused() {
        XCTAssertNil(InstructionsImport.text(from: Data([0xFF, 0xFE, 0x00, 0xD8, 0xFF, 0xE0, 0x00, 0x10])))
    }

    func testAnEmptyFileIsRefused() {
        XCTAssertNil(InstructionsImport.text(from: Data()))
        XCTAssertNil(InstructionsImport.text(from: Data("  \n ".utf8)))
    }
}
