import XCTest

final class ClipboardTests: XCTestCase {
    func testOnlyRealTextIsUsable() {
        XCTAssertNil(ClipboardOffer.usable(nil))
        XCTAssertNil(ClipboardOffer.usable("  \n"))
        XCTAssertNil(ClipboardOffer.usable("a"))
        XCTAssertEqual(ClipboardOffer.usable("  hey there \n"), "hey there")
    }

    func testACopiedArticleIsCut() {
        let text = ClipboardOffer.usable(String(repeating: "a", count: ClipboardOffer.textLimit + 10))
        XCTAssertEqual(text?.count, ClipboardOffer.textLimit)
    }

    func testTheReadBecomesAnAnalysisTheKeyboardUnderstands() throws {
        let json = """
        {"language":"English","tone":"casual, emojis","last_incoming_uz":"Qalaysan?\\nErtaga ko'rishamizmi?",
         "summary_uz":"Ertaga uchrashmoqchi.","suggestions":[{"text":"yes!","uz":"ha!"},{"text":"can't","uz":"bo'lmaydi"},{"text":"when?","uz":"qachon?"}]}
        """
        let read = try JSONDecoder().decode(ClipboardRead.self, from: Data(json.utf8))
        let analysis = read.analysis(partner: "Anna", text: "how are you?\n\n see you tomorrow? ")
        XCTAssertEqual(analysis.partner, "Anna")
        XCTAssertEqual(analysis.language, "English")
        XCTAssertEqual(analysis.lastIncomingUz, "Qalaysan?\nErtaga ko'rishamizmi?")
        XCTAssertEqual(analysis.summaryUz, "Ertaga uchrashmoqchi.")
        XCTAssertEqual(analysis.transcript, [.init(from: "them", text: "how are you?"), .init(from: "them", text: "see you tomorrow?")])
        XCTAssertEqual(analysis.lastIncoming, "how are you? see you tomorrow?")
        XCTAssertEqual(analysis.suggestions.count, 3)
    }

    func testWithoutAFriendThePartnerIsEmpty() throws {
        let json = #"{"language":"Korean","tone":"casual","last_incoming_uz":"x","summary_uz":"y","suggestions":[]}"#
        let read = try JSONDecoder().decode(ClipboardRead.self, from: Data(json.utf8))
        XCTAssertEqual(read.analysis(partner: "", text: "안녕").partner, "")
    }

    func testTheRememberedChatGrowsFromACopiedMessage() throws {
        let json = #"{"language":"English","tone":"casual","last_incoming_uz":"x","summary_uz":"y","suggestions":[]}"#
        let read = try JSONDecoder().decode(ClipboardRead.self, from: Data(json.utf8))
        var state = SharedState()
        state.friends = [Friend(name: "Anna", language: "English", tone: "", lastSeen: Date())]
        state.remember(read.analysis(partner: "Anna", text: "are you free friday?"))
        XCTAssertEqual(state.friends?.first?.history?.map(\.text), ["are you free friday?"])
        XCTAssertEqual(state.activeFriend, "Anna")
    }

    func testThePromptKeepsTheTranslationRules() {
        let prompt = Prompts.clipboardSystem(style: "oddiy yoz")
        XCTAssertTrue(prompt.contains("one line per message or paragraph"))
        XCTAssertTrue(prompt.contains("never a word-for-word machine translation"))
        XCTAssertTrue(prompt.contains("exactly 3 replies"))
        XCTAssertTrue(prompt.hasSuffix("oddiy yoz"))
        XCTAssertEqual((Prompts.clipboardSchema["required"] as? [String])?.count, 5)
    }
}
