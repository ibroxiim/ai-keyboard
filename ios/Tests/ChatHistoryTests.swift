import XCTest

final class ChatHistoryTests: XCTestCase {
    private func line(_ from: String, _ text: String) -> ChatAnalysis.Line { .init(from: from, text: text) }

    private func lines(_ items: (String, String)...) -> [ChatAnalysis.Line] {
        items.map { line($0.0, $0.1) }
    }

    func testFirstScreenshotBecomesTheHistory() {
        let new = lines(("them", "hey there"), ("me", "hello!"))
        XCTAssertEqual(ChatHistory.merged([], with: new), new)
    }

    func testNothingNewKeepsTheHistory() {
        let old = lines(("them", "hey there"))
        XCTAssertEqual(ChatHistory.merged(old, with: []), old)
    }

    func testNewMessagesAreAppendedAfterTheOverlap() {
        let old = lines(("them", "are you free friday?"), ("me", "maybe, what time?"), ("them", "around seven"))
        let new = lines(("me", "maybe, what time?"), ("them", "around seven"), ("me", "works for me"), ("them", "great"))
        XCTAssertEqual(
            ChatHistory.merged(old, with: new),
            lines(("them", "are you free friday?"), ("me", "maybe, what time?"), ("them", "around seven"),
                  ("me", "works for me"), ("them", "great")))
    }

    func testTheSameScreenshotTwiceChangesNothing() {
        let shot = lines(("them", "are you free friday?"), ("me", "maybe, what time?"), ("them", "around seven"))
        let once = ChatHistory.merged([], with: shot)
        XCTAssertEqual(ChatHistory.merged(once, with: shot), once)
    }

    func testAnOlderScreenfulInsideTheHistoryChangesNothing() {
        let old = lines(("them", "first message here"), ("me", "second message here"), ("them", "third message here"),
                        ("me", "fourth message here"))
        let scrolledUp = lines(("me", "second message here"), ("them", "third message here"))
        XCTAssertEqual(ChatHistory.merged(old, with: scrolledUp), old)
    }

    func testWithoutAnyOverlapTheNewScreenshotIsTheNewerOne() {
        let old = lines(("them", "see you tomorrow"))
        let new = lines(("them", "a week later, hello again"), ("me", "hi!"))
        XCTAssertEqual(ChatHistory.merged(old, with: new), old + new)
    }

    func testTheTopMessageCutOffByTheScreenStillOverlaps() {
        let old = lines(("them", "we had so much fun at the party last night"), ("me", "yes we did!"))
        let new = lines(("them", "so much fun at the party last night"), ("me", "yes we did!"), ("them", "again soon?"))
        let merged = ChatHistory.merged(old, with: new)
        XCTAssertEqual(merged.map(\.text), ["we had so much fun at the party last night", "yes we did!", "again soon?"])
    }

    func testTheFullerWordingWinsWhenTheNewScreenshotHasIt() {
        let old = lines(("them", "so much fun at the party last night"), ("me", "yes we did!"))
        let new = lines(("them", "we had so much fun at the party last night"), ("me", "yes we did!"), ("them", "again?"))
        XCTAssertEqual(
            ChatHistory.merged(old, with: new).map(\.text),
            ["we had so much fun at the party last night", "yes we did!", "again?"])
    }

    func testCaseAndPunctuationDoNotBreakTheOverlap() {
        let old = lines(("them", "OK cool!!"), ("me", "see you at 7"))
        let new = lines(("them", "ok cool"), ("me", "See you at 7."), ("them", "👍"))
        XCTAssertEqual(ChatHistory.merged(old, with: new).count, 3)
    }

    func testTheSameWordsFromTheOtherPersonAreNotTheSameMessage() {
        let old = lines(("them", "see you tomorrow, my friend"), ("me", "sounds good to me"))
        let new = lines(("me", "see you tomorrow, my friend"), ("them", "sounds good to me"))
        XCTAssertEqual(ChatHistory.merged(old, with: new), old + new)
    }

    func testOneShortLineIsNotEnoughToAnchor() {
        let old = lines(("them", "hi"), ("me", "ok"))
        let new = lines(("me", "ok"), ("them", "bye"))
        XCTAssertEqual(ChatHistory.merged(old, with: new).count, 4)
    }

    func testOnlyTheLatestMessagesAreKept() {
        let old = (0..<ChatHistory.limit).map { line("them", "message number \($0)") }
        let new = [line("me", "a brand new reply"), line("them", "another new message")]
        let merged = ChatHistory.merged(old, with: new)
        XCTAssertEqual(merged.count, ChatHistory.limit)
        XCTAssertEqual(merged.last?.text, "another new message")
        XCTAssertEqual(merged.first?.text, "message number 2")
    }
}
