import XCTest

final class RefineAndLearnTests: XCTestCase {
    private func input(tweaks: [RewriteTweak] = [], examples: [Friend.Example] = []) -> String {
        Prompts.rewriteInput(
            draft: "salom", context: nil, friend: nil, language: "English", formality: nil, tweaks: tweaks,
            examples: examples)
    }

    // MARK: Tweaks

    func testNoTweaksNoAdjustLine() {
        XCTAssertFalse(input().contains("Adjust:"))
    }

    func testTweaksBecomeOneAdjustLine() {
        let text = input(tweaks: [.shorter, .warmer])
        XCTAssertTrue(text.contains("Adjust: shorter; warmer and more affectionate"))
        XCTAssertTrue(text.hasSuffix("Draft:\nsalom"))
    }

    func testEveryTweakHasALabelAndAnInstruction() {
        for tweak in RewriteTweak.allCases {
            XCTAssertFalse(tweak.label.isEmpty)
            XCTAssertFalse(tweak.instruction.isEmpty)
        }
        XCTAssertTrue(Prompts.rewriteSystem(style: nil).contains("\"Adjust\" line"))
    }

    // MARK: Learning

    func testAnEditedVariantIsAnExample() {
        let example = EditLearning.example(draft: "salom qalaysan", picked: "hey, how are you?", sent: "heyy how r u 😄")
        XCTAssertEqual(example, Friend.Example(draft: "salom qalaysan", suggested: "hey, how are you?", sent: "heyy how r u 😄"))
    }

    func testAnUnchangedVariantTeachesNothing() {
        XCTAssertNil(EditLearning.example(draft: "d", picked: "hey, how are you?", sent: "hey, how are you? "))
    }

    func testAHostAppShowingOnlyPartOfTheVariantIsNotAnEdit() {
        XCTAssertNil(EditLearning.example(draft: "d", picked: "hey, how are you doing today?", sent: "doing today?"))
        XCTAssertNil(EditLearning.example(draft: "d", picked: "hey, how are you doing today?", sent: "hey, how are"))
    }

    func testTooLittleTextTeachesNothing() {
        XCTAssertNil(EditLearning.example(draft: "d", picked: "hey", sent: ""))
        XCTAssertNil(EditLearning.example(draft: "d", picked: "hey", sent: "x"))
    }

    func testAFriendKeepsTheNewestExamplesOnly() {
        var friend = Friend(name: "Anna", language: "English", tone: "", lastSeen: Date())
        for i in 0..<(EditLearning.limit + 5) {
            friend.learn(Friend.Example(draft: "d\(i)", suggested: "s\(i)", sent: "t\(i)"))
        }
        XCTAssertEqual(friend.examples?.count, EditLearning.limit)
        XCTAssertEqual(friend.examples?.last?.draft, "d\(EditLearning.limit + 4)")
        XCTAssertEqual(friend.examples?.first?.draft, "d5")
    }

    func testTheSameExampleTwiceIsKeptOnce() {
        var friend = Friend(name: "Anna", language: "English", tone: "", lastSeen: Date())
        let example = Friend.Example(draft: "d", suggested: "s", sent: "t")
        friend.learn(example)
        friend.learn(example)
        XCTAssertEqual(friend.examples, [example])
    }

    func testTheStateLearnsForTheActiveFriendOnly() {
        var state = SharedState()
        state.friends = [Friend(name: "Anna", language: "English", tone: "", lastSeen: Date()),
                         Friend(name: "Minho", language: "Korean", tone: "", lastSeen: Date())]
        let example = Friend.Example(draft: "d", suggested: "s", sent: "t")
        state.learn(example)
        XCTAssertNil(state.friends?.first?.examples)
        state.activeFriend = "Anna"
        state.learn(example)
        XCTAssertEqual(state.friends?.first?.examples, [example])
        XCTAssertNil(state.friends?.last?.examples)
        XCTAssertEqual(state.rememberedExamples, [example])
    }

    func testNothingIsLearnedWhileMemoryIsOffAndTurningItOffForgets() {
        var state = SharedState()
        state.friends = [Friend(name: "Anna", language: "English", tone: "", lastSeen: Date())]
        state.activeFriend = "Anna"
        state.learn(Friend.Example(draft: "d", suggested: "s", sent: "t"))
        XCTAssertEqual(state.friends?.first?.examples?.count, 1)
        state.setRememberChats(false)
        XCTAssertNil(state.friends?.first?.examples)
        state.learn(Friend.Example(draft: "d", suggested: "s", sent: "t"))
        XCTAssertNil(state.friends?.first?.examples)
        XCTAssertEqual(state.rememberedExamples, [])
    }

    func testExamplesSurviveANewScreenshotOfTheSameFriend() {
        var state = SharedState()
        state.friends = [Friend(name: "Anna", language: "English", tone: "", lastSeen: Date(),
                                examples: [Friend.Example(draft: "d", suggested: "s", sent: "t")])]
        state.remember(ChatAnalysis(
            quick: QuickRead(partner: "Anna", language: "English", tone: "casual", lastIncomingUz: ""), details: nil))
        XCTAssertEqual(state.friends?.first?.examples?.count, 1)
    }

    func testExamplesReachTheRewritePromptNewestLast() {
        let examples = (0..<(EditLearning.promptLimit + 3)).map {
            Friend.Example(draft: "draft \($0)", suggested: "sugg \($0)", sent: "sent \($0)")
        }
        let text = input(examples: examples)
        XCTAssertTrue(text.contains("How the user changed earlier suggestions"))
        XCTAssertTrue(text.contains("- draft: draft 12\n  suggested: sugg 12\n  sent: sent 12"))
        XCTAssertFalse(text.contains("draft 2\n"))
        XCTAssertTrue(text.contains("draft 3\n"))
    }

    func testOldFriendRecordsStillLoad() throws {
        let json = #"{"friends":[{"name":"Anna","language":"English","tone":"casual","lastSeen":0}]}"#
        let state = try JSONDecoder().decode(SharedState.self, from: Data(json.utf8))
        XCTAssertNil(state.friends?.first?.examples)
    }
}
