import XCTest

final class PromptsTests: XCTestCase {
    func testNoStyleAddsNothing() {
        XCTAssertEqual(Prompts.styleBlock(nil), "")
        XCTAssertEqual(Prompts.styleBlock(""), "")
        XCTAssertEqual(Prompts.styleBlock("  \n "), "")
        XCTAssertFalse(Prompts.quickSystem(style: nil).contains("own instructions"))
    }

    func testStyleReachesEveryTranslationPrompt() {
        let style = "Juda rasmiy bo'lma, ko'cha tilida yoz"
        XCTAssertTrue(Prompts.quickSystem(style: style).contains(style))
        XCTAssertTrue(Prompts.rewriteSystem(style: style).contains(style))
    }

    func testStyleIsTrimmedAndCapped() {
        XCTAssertTrue(Prompts.styleBlock("  oddiy  ").hasSuffix("\noddiy"))
        let block = Prompts.styleBlock(String(repeating: "a", count: Prompts.styleLimit + 500))
        XCTAssertTrue(block.hasSuffix(String(repeating: "a", count: Prompts.styleLimit)))
        XCTAssertFalse(block.contains(String(repeating: "a", count: Prompts.styleLimit + 1)))
    }

    func testTranslationCoversTheWholeUnansweredRun() {
        let prompt = Prompts.quickSystem(style: nil)
        XCTAssertTrue(prompt.contains("EVERY message from \"them\" after the last message from \"me\""))
        XCTAssertTrue(prompt.contains("one line per message"))
    }

    func testToneCarriesTheSpeechLevel() {
        XCTAssertTrue(Prompts.quickSystem(style: nil).contains("speech level"))
    }

    func testTranscriptKeepsTwelveMessages() {
        XCTAssertTrue(Prompts.detailsSystem.contains("last up to 12 messages"))
    }

    func testRewriteInputNamesTheFormalityTheUserChose() {
        let formal = Prompts.rewriteInput(
            draft: "salom", context: nil, friend: nil, language: "Korean", formality: .formal)
        XCTAssertTrue(formal.contains("Formality chosen by the user: formal"))
        let informal = Prompts.rewriteInput(
            draft: "salom", context: nil, friend: nil, language: "Korean", formality: .informal)
        XCTAssertTrue(informal.contains("Formality chosen by the user: informal"))
    }

    func testRewriteInputWithoutAChoiceLeavesFormalityToTheModel() {
        let input = Prompts.rewriteInput(draft: "salom", context: nil, friend: nil, language: "Korean", formality: nil)
        XCTAssertFalse(input.contains("Formality"))
    }

    func testRewriteInputKeepsTheDraftLast() {
        let input = Prompts.rewriteInput(
            draft: "salom, qalaysan", context: nil, friend: nil, language: "English", formality: nil)
        XCTAssertTrue(input.hasSuffix("Draft:\nsalom, qalaysan"))
        XCTAssertTrue(input.hasPrefix("Target language: English"))
    }
}
