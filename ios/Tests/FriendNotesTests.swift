import XCTest

final class FriendNotesTests: XCTestCase {
    private func friend(_ name: String, notes: String? = nil) -> Friend {
        Friend(name: name, language: "English", tone: "casual", lastSeen: Date(), notes: notes)
    }

    private func analysis(partner: String) -> ChatAnalysis {
        ChatAnalysis(
            quick: QuickRead(partner: partner, language: "English", tone: "casual", lastIncomingUz: ""), details: nil)
    }

    // MARK: What the screenshot requests get

    func testNoFriendsMeansNoPart() {
        XCTAssertNil(Prompts.knownFriendsPart([]))
    }

    func testFriendsWithoutNotesAreJustListed() {
        XCTAssertEqual(Prompts.knownFriendsPart([friend("Anna"), friend("Minho")]), "Known friends: Anna, Minho")
    }

    func testNotesFollowTheListUnderTheFriendsName() {
        let part = Prompts.knownFriendsPart([friend("Anna", notes: "my classmate, we joke a lot"), friend("Minho")])
        XCTAssertEqual(part, """
        Known friends: Anna, Minho

        The user's notes about Anna (follow them when the partner is Anna):
        my classmate, we joke a lot
        """)
    }

    func testBlankNotesAreLeftOut() {
        XCTAssertEqual(Prompts.knownFriendsPart([friend("Anna", notes: "  \n")]), "Known friends: Anna")
    }

    func testNotesAreCapped() {
        let part = Prompts.knownFriendsPart([friend("Anna", notes: String(repeating: "x", count: 9000))]) ?? ""
        XCTAssertTrue(part.hasSuffix(String(repeating: "x", count: Prompts.styleLimit)))
        XCTAssertFalse(part.contains(String(repeating: "x", count: Prompts.styleLimit + 1)))
    }

    func testTheScreenshotPromptsSayToApplyTheNotes() {
        XCTAssertTrue(Prompts.quickSystem(style: nil).contains("notes about"))
        XCTAssertTrue(Prompts.detailsSystem.contains("notes about"))
    }

    // MARK: What ✨ gets

    func testRewriteInputCarriesTheNotesAboutTheFriend() {
        let input = Prompts.rewriteInput(
            draft: "salom", context: nil, friend: friend("Anna"), language: "English", formality: nil,
            notes: "my classmate, we joke a lot")
        XCTAssertTrue(input.contains("The user's notes about this friend (follow them):\nmy classmate, we joke a lot"))
        XCTAssertTrue(input.hasSuffix("Draft:\nsalom"))
    }

    func testRewriteInputWithoutNotesSaysNothingAboutThem() {
        let input = Prompts.rewriteInput(
            draft: "salom", context: nil, friend: friend("Anna"), language: "English", formality: nil, notes: "  ")
        XCTAssertFalse(input.contains("notes about"))
    }

    func testRewriteInputCarriesTheNotesEvenWithAFreshScreenshot() {
        let input = Prompts.rewriteInput(
            draft: "salom", context: analysis(partner: "Anna"), friend: nil, language: "English", formality: nil,
            notes: "my classmate")
        XCTAssertTrue(input.contains("notes about this friend"))
    }

    // MARK: Keeping them

    func testRememberKeepsTheNotesTheUserWrote() {
        var state = SharedState()
        state.friends = [friend("Christina", notes: "my classmate")]
        state.remember(analysis(partner: "Christi..."))
        XCTAssertEqual(state.friends?.count, 1)
        XCTAssertEqual(state.friends?.first?.notes, "my classmate")
    }

    func testMergingDuplicatesKeepsTheNotes() {
        var state = SharedState()
        state.friends = [friend("Anna"), friend("Anna L.", notes: "my classmate")]
        state.mergeDuplicateFriends()
        XCTAssertEqual(state.friends?.first?.notes, "my classmate")
    }

    func testActiveFriendsNotesGoToTheRewrite() {
        var state = SharedState()
        state.friends = [friend("Anna", notes: "my classmate"), friend("Minho")]
        state.activeFriend = "Anna"
        XCTAssertEqual(state.activeFriendRecord?.notes, "my classmate")
        state.activeFriend = "Minho"
        XCTAssertNil(state.activeFriendRecord?.notes)
    }

    func testTheLimitGrewToFourThousand() {
        XCTAssertEqual(Prompts.styleLimit, 4000)
    }
}
