import XCTest

final class FriendFormalityTests: XCTestCase {
    private func analysis(partner: String, language: String, tone: String) -> ChatAnalysis {
        ChatAnalysis(
            quick: QuickRead(partner: partner, language: language, tone: tone, lastIncomingUz: ""), details: nil)
    }

    private func friend(formality: Friend.Formality?) -> Friend {
        Friend(name: "Christina", language: "Korean", tone: "casual", lastSeen: Date(timeIntervalSince1970: 0),
               formality: formality)
    }

    func testRememberKeepsTheFormalityTheUserChose() {
        var state = SharedState()
        state.friends = [friend(formality: .informal)]
        state.remember(analysis(partner: "Christi...", language: "Korean", tone: "polite, 존댓말"))
        XCTAssertEqual(state.friends?.count, 1)
        XCTAssertEqual(state.friends?.first?.formality, .informal)
        XCTAssertEqual(state.friends?.first?.tone, "polite, 존댓말")
    }

    func testANewFriendStartsWithoutAChosenFormality() {
        var state = SharedState()
        state.remember(analysis(partner: "Minho", language: "Korean", tone: "casual"))
        XCTAssertNil(state.friends?.first?.formality)
    }

    func testFormalityIsOnlyKeptForTheSamePerson() {
        var state = SharedState()
        state.friends = [friend(formality: .formal)]
        state.remember(analysis(partner: "Minho", language: "Korean", tone: "casual"))
        XCTAssertNil(state.friends?.first { $0.name == "Minho" }?.formality)
        XCTAssertEqual(state.friends?.first { $0.name == "Christina" }?.formality, .formal)
    }

    func testChosenFormalityFollowsTheActiveFriend() {
        var state = SharedState()
        state.friends = [friend(formality: .informal), Friend(name: "Minho", language: "Korean", tone: "", lastSeen: Date(), formality: .formal)]
        XCTAssertNil(state.chosenFormality)
        state.activeFriend = "Christina"
        XCTAssertEqual(state.chosenFormality, .informal)
        state.activeFriend = "Minho"
        XCTAssertEqual(state.chosenFormality, .formal)
        state.activeFriend = "Someone else"
        XCTAssertNil(state.chosenFormality)
    }

    func testFriendsSavedByAnOlderBuildStillLoad() throws {
        let json = #"{"friends":[{"name":"Anna","language":"English","tone":"casual","lastSeen":0}]}"#
        let state = try JSONDecoder().decode(SharedState.self, from: Data(json.utf8))
        XCTAssertEqual(state.friends?.first?.name, "Anna")
        XCTAssertNil(state.friends?.first?.formality)
    }

    func testTheUsersTranslationSettingsDefaultToNothing() {
        let state = SharedState()
        XCTAssertNil(state.translationStyle)
        XCTAssertNil(state.qualityMode)
        XCTAssertNil(state.rememberChats)
    }
}
