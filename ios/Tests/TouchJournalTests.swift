import XCTest

final class TouchJournalTests: XCTestCase {
    private typealias Position = TouchJournal.KeyPosition

    private let center = Position(row: 0, column: 3, rowLength: 10, isBottomRow: false)
    private let edge = Position(row: 1, column: 0, rowLength: 9, isBottomRow: false)
    private let bottom = Position(row: 3, column: 4, rowLength: 7, isBottomRow: true)

    func testZoneOfPosition() {
        XCTAssertEqual(center.zone, .center)
        XCTAssertEqual(edge.zone, .edge)
        XCTAssertEqual(Position(row: 0, column: 9, rowLength: 10, isBottomRow: false).zone, .edge)
        XCTAssertEqual(bottom.zone, .bottom)
    }

    func testCountsOutcomesZonesAndTypedCharacters() {
        var journal = TouchJournal(keepsDetail: false, start: 0)
        journal.record(.init(key: 3, outcome: .typed, eventTime: 1), at: center, kind: .character, handledAt: 1, doneAt: 1)
        journal.record(.init(key: 10, outcome: .cancelledBySystem, eventTime: nil), at: edge, kind: .character, handledAt: 2, doneAt: 2)
        journal.record(.init(key: 30, outcome: .function, eventTime: 3), at: bottom, kind: .space, handledAt: 3, doneAt: 3)
        XCTAssertEqual(journal.touches, 3)
        XCTAssertEqual(journal.typed, 1)
        XCTAssertEqual(journal.outcomes, ["typed": 1, "cancelledBySystem": 1, "function": 1])
        XCTAssertEqual(journal.zones["center"], DiagnosticSession.ZoneCount(touches: 1, lost: 0))
        XCTAssertEqual(journal.zones["edge"], DiagnosticSession.ZoneCount(touches: 1, lost: 1))
        XCTAssertEqual(journal.zones["bottom"], DiagnosticSession.ZoneCount(touches: 1, lost: 0))
    }

    func testLatencyIsMeasuredFromTheTouchEvent() {
        var journal = TouchJournal(keepsDetail: false, start: 0)
        journal.record(.init(key: 3, outcome: .typed, eventTime: 10), at: center, kind: .character, handledAt: 10.002, doneAt: 10.005)
        XCTAssertEqual(journal.deliveryMs.first ?? -1, 2, accuracy: 0.001)
        XCTAssertEqual(journal.upToInsertMs.first ?? -1, 5, accuracy: 0.001)
    }

    func testRecordsWithoutEventTimeStayOutOfLatency() {
        var journal = TouchJournal(keepsDetail: false, start: 0)
        journal.record(.init(key: 3, outcome: .committedOnRebuild, eventTime: nil), at: center, kind: .character, handledAt: 5, doneAt: 5)
        XCTAssertEqual(journal.typed, 1)
        XCTAssertEqual(journal.upToInsertMs, [])
        XCTAssertEqual(journal.deliveryMs, [])
    }

    func testDetailIsKeptOnlyInTestMode() {
        var chat = TouchJournal(keepsDetail: false, start: 100)
        chat.record(.init(key: 3, outcome: .typed, eventTime: 101), at: center, kind: .character, handledAt: 101, doneAt: 101)
        XCTAssertEqual(chat.detail, [])

        var test = TouchJournal(keepsDetail: true, start: 100)
        test.record(.init(key: 3, outcome: .typed, eventTime: 101), at: center, kind: .character, handledAt: 101.5, doneAt: 101.5)
        XCTAssertEqual(test.detail.count, 1)
        XCTAssertEqual(test.detail.first?.key, [0, 3])
        XCTAssertEqual(test.detail.first?.kind, "character")
        XCTAssertEqual(test.detail.first?.outcome, "typed")
        XCTAssertEqual(test.detail.first?.t ?? -1, 1.5, accuracy: 0.0001)
    }
}
