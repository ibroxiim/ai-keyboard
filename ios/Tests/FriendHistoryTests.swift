import XCTest

final class FriendHistoryTests: XCTestCase {
    private func analysis(partner: String, _ lines: [(String, String)]) -> ChatAnalysis {
        var result = ChatAnalysis(
            quick: QuickRead(partner: partner, language: "English", tone: "casual", lastIncomingUz: ""), details: nil)
        result.transcript = lines.map { .init(from: $0.0, text: $0.1) }
        return result
    }

    func testEachScreenshotExtendsTheFriendsHistory() {
        var state = SharedState()
        state.remember(analysis(partner: "Anna", [("them", "are you free friday?"), ("me", "maybe, what time?")]))
        state.remember(analysis(partner: "Anna", [("me", "maybe, what time?"), ("them", "around seven")]))
        XCTAssertEqual(
            state.friends?.first?.history?.map(\.text), ["are you free friday?", "maybe, what time?", "around seven"])
    }

    func testHistoryBelongsToOneFriend() {
        var state = SharedState()
        state.remember(analysis(partner: "Anna", [("them", "hello from anna")]))
        state.remember(analysis(partner: "Minho", [("them", "hello from minho")]))
        XCTAssertEqual(state.friends?.first { $0.name == "Anna" }?.history?.map(\.text), ["hello from anna"])
        XCTAssertEqual(state.friends?.first { $0.name == "Minho" }?.history?.map(\.text), ["hello from minho"])
    }

    func testAMisreadNameStillReachesTheSameHistory() {
        var state = SharedState()
        state.remember(analysis(partner: "Christina", [("them", "good morning to you")]))
        state.remember(analysis(partner: "Christi...", [("them", "good morning to you"), ("me", "morning!")]))
        XCTAssertEqual(state.friends?.count, 1)
        XCTAssertEqual(state.friends?.first?.history?.map(\.text), ["good morning to you", "morning!"])
    }

    func testNothingIsSavedWhileMemoryIsOff() {
        var state = SharedState()
        state.setRememberChats(false)
        state.remember(analysis(partner: "Anna", [("them", "hello from anna")]))
        XCTAssertNil(state.friends?.first?.history)
        XCTAssertEqual(state.rememberedMessages, [])
    }

    func testTurningMemoryOffForgetsWhatWasSaved() {
        var state = SharedState()
        state.remember(analysis(partner: "Anna", [("them", "hello from anna")]))
        XCTAssertEqual(state.rememberedMessages.count, 1)
        state.setRememberChats(false)
        XCTAssertNil(state.friends?.first?.history)
        XCTAssertEqual(state.rememberedMessages, [])
        state.setRememberChats(true)
        XCTAssertEqual(state.rememberChats, true)
    }

    func testRememberedMessagesAreTheActiveFriendsOnly() {
        var state = SharedState()
        state.remember(analysis(partner: "Anna", [("them", "hello from anna")]))
        state.remember(analysis(partner: "Minho", [("them", "hello from minho")]))
        XCTAssertEqual(state.rememberedMessages.map(\.text), ["hello from minho"])
        state.activeFriend = "Anna"
        XCTAssertEqual(state.rememberedMessages.map(\.text), ["hello from anna"])
        state.activeFriend = nil
        XCTAssertEqual(state.rememberedMessages, [])
    }

    func testMergingDuplicateFriendsKeepsTheirHistory() {
        var state = SharedState()
        let line = ChatAnalysis.Line(from: "them", text: "hello from anna")
        state.friends = [
            Friend(name: "Anna", language: "English", tone: "", lastSeen: Date()),
            Friend(name: "Anna L.", language: "English", tone: "", lastSeen: Date(), history: [line]),
        ]
        state.mergeDuplicateFriends()
        XCTAssertEqual(state.friends?.count, 1)
        XCTAssertEqual(state.friends?.first?.history, [line])
    }

    func testRewriteInputWithoutAScreenshotUsesTheRememberedChat() {
        let friend = Friend(name: "Anna", language: "English", tone: "casual", lastSeen: Date())
        let history = [ChatAnalysis.Line(from: "them", text: "are you free friday?"),
                       ChatAnalysis.Line(from: "me", text: "maybe, what time?")]
        let input = Prompts.rewriteInput(
            draft: "yaxshi", context: nil, friend: friend, language: "English", formality: nil, history: history)
        XCTAssertTrue(input.contains("Earlier messages, from past screenshots"))
        XCTAssertTrue(input.contains("them: are you free friday?\nme: maybe, what time?"))
        XCTAssertFalse(input.contains("No recent messages available."))
    }

    func testRewriteInputWithAScreenshotPrefersTheLongerRememberedChat() {
        var context = ChatAnalysis(
            quick: QuickRead(partner: "Anna", language: "English", tone: "casual", lastIncomingUz: ""), details: nil)
        context.transcript = [.init(from: "them", text: "newest message")]
        let history = [ChatAnalysis.Line(from: "me", text: "an older message"),
                       ChatAnalysis.Line(from: "them", text: "newest message")]
        let input = Prompts.rewriteInput(
            draft: "yaxshi", context: context, friend: nil, language: "English", formality: nil, history: history)
        XCTAssertTrue(input.contains("me: an older message\nthem: newest message"))
    }

    func testRewriteInputSendsOnlyTheLatestRememberedMessages() {
        let friend = Friend(name: "Anna", language: "English", tone: "casual", lastSeen: Date())
        let history = (0..<40).map { ChatAnalysis.Line(from: "them", text: "message \($0)") }
        let input = Prompts.rewriteInput(
            draft: "yaxshi", context: nil, friend: friend, language: "English", formality: nil, history: history)
        XCTAssertTrue(input.contains("message 39"))
        XCTAssertTrue(input.contains("message \(40 - Prompts.historyLimit)"))
        XCTAssertFalse(input.contains("message \(39 - Prompts.historyLimit)\n"))
    }
}
