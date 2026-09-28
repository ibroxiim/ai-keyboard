import XCTest

final class TouchTrackerTests: XCTestCase {
    private typealias Record = TouchTracker.Record

    /// Stand-ins for UITouch: only their identity matters. Kept alive so the identifiers stay distinct.
    private final class Finger {}
    private let finger1 = Finger()
    private let finger2 = Finger()
    private var f1: ObjectIdentifier { ObjectIdentifier(finger1) }
    private var f2: ObjectIdentifier { ObjectIdentifier(finger2) }

    private let charA = 0, charB = 1, space = 2, backspace = 3, shift = 4, globe = 5, newline = 6

    private func makeTracker() -> TouchTracker {
        var tracker = TouchTracker()
        tracker.keys = [.character, .character, .space, .backspace, .shift, .function, .newline]
        return tracker
    }

    func testTapTypesOnTouchUp() {
        var tracker = makeTracker()
        let down = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        XCTAssertEqual(down.actions, [.keyDown, .showPopup(key: charA)])
        XCTAssertEqual(down.records, [])
        let up = tracker.handle(.ended(id: f1, time: 1.1))
        XCTAssertEqual(up.actions, [.type(key: charA), .hidePopup])
        XCTAssertEqual(up.records, [Record(key: charA, outcome: .typed, eventTime: 1.1)])
    }

    func testNewFingerCommitsHeldCharacterFirst() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        let second = tracker.handle(.began(id: f2, key: charB, x: 0, time: 1.05, alive: [f1, f2]))
        XCTAssertEqual(second.actions, [.type(key: charA), .hidePopup, .keyDown, .showPopup(key: charB)])
        XCTAssertEqual(second.records, [Record(key: charA, outcome: .rolledOver, eventTime: 1.05)])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.1)).actions, [])
        XCTAssertEqual(tracker.handle(.ended(id: f2, time: 1.2)).actions, [.type(key: charB), .hidePopup])
    }

    func testSpaceStillHeldWhenNextLetterLandsIsTypedFirst() {
        var tracker = makeTracker()
        XCTAssertEqual(
            tracker.handle(.began(id: f1, key: space, x: 100, time: 1, alive: [f1])).actions,
            [.keyDown, .press(key: space)])
        let letter = tracker.handle(.began(id: f2, key: charA, x: 0, time: 1.05, alive: [f1, f2]))
        XCTAssertEqual(letter.actions, [.space, .keyDown, .showPopup(key: charA)])
        XCTAssertEqual(letter.records, [Record(key: space, outcome: .function, eventTime: 1.05)])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.1)).actions, [.unpress(key: space)])
        XCTAssertEqual(tracker.handle(.ended(id: f2, time: 1.2)).actions, [.type(key: charA), .hidePopup])
    }

    func testDraggedSpaceMovesCursorAndIsNotRolledOver() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: space, x: 100, time: 1, alive: [f1]))
        XCTAssertEqual(tracker.handle(.moved(id: f1, key: space, x: 130)).actions, [.beginCursorDrag(key: space)])
        XCTAssertEqual(tracker.handle(.moved(id: f1, key: space, x: 150)).actions, [.moveCursor(2)])
        XCTAssertEqual(
            tracker.handle(.began(id: f2, key: charA, x: 0, time: 1.3, alive: [f1, f2])).actions,
            [.keyDown, .showPopup(key: charA)])
        XCTAssertEqual(
            tracker.handle(.ended(id: f1, time: 1.4)).actions,
            [.unpress(key: space), .endCursorDrag(key: space)])
    }

    func testRebuildTypesHeldCharacterInsteadOfDroppingIt() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        let rebuild = tracker.handle(.willRebuild)
        XCTAssertEqual(rebuild.actions, [.type(key: charA), .hidePopup])
        XCTAssertEqual(rebuild.records, [Record(key: charA, outcome: .committedOnRebuild, eventTime: nil)])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.2)).actions, [])
    }

    func testTouchThatLostItsEndIsTypedWhenTheNextOneBegins() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        let next = tracker.handle(.began(id: f2, key: charB, x: 0, time: 2, alive: [f2]))
        XCTAssertEqual(next.actions, [.type(key: charA), .hidePopup, .keyDown, .showPopup(key: charB)])
        XCTAssertEqual(next.records, [Record(key: charA, outcome: .recoveredMissingEnd, eventTime: nil)])
    }

    func testReusedTouchObjectDoesNotSwallowTheNewPress() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        let reused = tracker.handle(.began(id: f1, key: charB, x: 0, time: 2, alive: [f1]))
        XCTAssertEqual(reused.actions, [.type(key: charA), .hidePopup, .keyDown, .showPopup(key: charB)])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 2.1)).actions, [.type(key: charB), .hidePopup])
    }

    func testCancelledTouchIsRecordedAndNotTyped() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        let cancel = tracker.handle(.cancelled(id: f1))
        XCTAssertEqual(cancel.actions, [.hidePopup])
        XCTAssertEqual(cancel.records, [Record(key: charA, outcome: .cancelledBySystem, eventTime: nil)])
    }

    func testBackspaceActsOnTouchDownAndRepeatsWhileHeld() {
        var tracker = makeTracker()
        let down = tracker.handle(.began(id: f1, key: backspace, x: 0, time: 1, alive: [f1]))
        XCTAssertEqual(down.actions, [.keyDown, .press(key: backspace), .backspace, .startRepeat])
        XCTAssertEqual(down.records, [Record(key: backspace, outcome: .function, eventTime: 1)])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.5)).actions, [.unpress(key: backspace), .stopRepeat])
    }

    func testSlidingToAnotherLetterTypesThatLetter() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        XCTAssertEqual(tracker.handle(.moved(id: f1, key: charB, x: 40)).actions, [.showPopup(key: charB)])
        let up = tracker.handle(.ended(id: f1, time: 1.2))
        XCTAssertEqual(up.actions, [.type(key: charB), .hidePopup])
        XCTAssertEqual(up.records, [Record(key: charB, outcome: .slid, eventTime: 1.2)])
    }

    func testShiftActsOnTouchDownOnly() {
        var tracker = makeTracker()
        XCTAssertEqual(tracker.handle(.began(id: f1, key: shift, x: 0, time: 1, alive: [f1])).actions, [.keyDown, .shift])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.1)).actions, [.unpress(key: shift)])
    }

    func testFunctionKeyActsOnTouchUp() {
        var tracker = makeTracker()
        XCTAssertEqual(
            tracker.handle(.began(id: f1, key: globe, x: 0, time: 1, alive: [f1])).actions,
            [.keyDown, .press(key: globe)])
        let up = tracker.handle(.ended(id: f1, time: 1.1))
        XCTAssertEqual(up.actions, [.release(key: globe), .unpress(key: globe)])
        XCTAssertEqual(up.records, [Record(key: globe, outcome: .function, eventTime: 1.1)])
    }

    func testNewlineActsOnTouchUp() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: newline, x: 0, time: 1, alive: [f1]))
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.1)).actions, [.newline, .unpress(key: newline)])
    }
}
