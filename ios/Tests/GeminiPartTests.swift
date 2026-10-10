import XCTest

final class GeminiPartTests: XCTestCase {
    func testAudioIsSentAsInlineDataWithItsMimeType() throws {
        let bytes = Data([1, 2, 3, 4])
        let json = GeminiPart.audio(bytes, mimeType: "audio/mp4").json
        let inline = try XCTUnwrap(json["inlineData"] as? [String: String])
        XCTAssertEqual(inline["mimeType"], "audio/mp4")
        XCTAssertEqual(inline["data"], bytes.base64EncodedString())
    }

    func testImageAndTextKeepTheirShape() throws {
        XCTAssertEqual(GeminiPart.text("salom").json["text"] as? String, "salom")
        let inline = try XCTUnwrap(GeminiPart.jpeg(Data([9])).json["inlineData"] as? [String: String])
        XCTAssertEqual(inline["mimeType"], "image/jpeg")
    }

    func testOnlyMediaCountsAsMedia() {
        XCTAssertTrue(GeminiPart.audio(Data(), mimeType: "audio/mp4").isMedia)
        XCTAssertTrue(GeminiPart.jpeg(Data()).isMedia)
        XCTAssertFalse(GeminiPart.text("x").isMedia)
    }
}
