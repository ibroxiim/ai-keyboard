import XCTest

final class VoiceTranscriptTests: XCTestCase {
    private func result(_ json: String) throws -> VoiceTranscript.Result {
        try JSONDecoder().decode(VoiceTranscript.Result.self, from: Data(json.utf8))
    }

    func testTranscriptIsTrimmed() throws {
        XCTAssertEqual(try VoiceTranscript.text(from: result(#"{"text": "  salom dunyo \n"}"#)), "salom dunyo")
    }

    func testEmptyTranscriptMeansNoSpeech() throws {
        XCTAssertThrowsError(try VoiceTranscript.text(from: result(#"{"text": "   "}"#))) {
            XCTAssertEqual($0 as? VoiceError, .noSpeech)
        }
    }

    func testEveryErrorExplainsItselfInUzbek() {
        for error in [VoiceError.microphoneDenied, .recordingFailed, .noSpeech] {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertEqual(VoiceError.noSpeech.localizedDescription, "Ovoz eshitilmadi")
        XCTAssertTrue(VoiceError.microphoneDenied.localizedDescription.contains("Mikrofon"))
    }
}
