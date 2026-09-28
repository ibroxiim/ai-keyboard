import Foundation

/// Collects what `TouchTracker` reports during one keyboard session. Outside the diagnostics test field it keeps
/// counters only: a sequence of key positions would spell out what the user typed.
struct TouchJournal {
    struct KeyPosition: Equatable {
        var row: Int
        var column: Int
        var rowLength: Int
        var isBottomRow: Bool

        var zone: DiagnosticZone {
            if isBottomRow { return .bottom }
            return column == 0 || column == rowLength - 1 ? .edge : .center
        }
    }

    let keepsDetail: Bool
    private let start: TimeInterval
    private(set) var touches = 0
    private(set) var typed = 0
    private(set) var outcomes: [String: Int] = [:]
    private(set) var zones: [String: DiagnosticSession.ZoneCount] = [:]
    private(set) var upToInsertMs: [Double] = []
    private(set) var deliveryMs: [Double] = []
    private(set) var detail: [DiagnosticSession.Touch] = []

    /// `start`: session start on the `systemUptime` clock, the one `UITouch.timestamp` uses.
    init(keepsDetail: Bool, start: TimeInterval) {
        self.keepsDetail = keepsDetail
        self.start = start
    }

    /// `handledAt`: when our touch handler started; `doneAt`: when its actions (the insert) had finished.
    mutating func record(
        _ record: TouchTracker.Record, at position: KeyPosition, kind: TouchTracker.KeyKind,
        handledAt: TimeInterval, doneAt: TimeInterval
    ) {
        touches += 1
        if record.outcome.producedCharacter { typed += 1 }
        outcomes[record.outcome.rawValue, default: 0] += 1
        let zone = position.zone.rawValue
        zones[zone, default: .init()].touches += 1
        if record.outcome == .cancelledBySystem { zones[zone, default: .init()].lost += 1 }

        var delivery: Double?
        var upToInsert: Double?
        if let eventTime = record.eventTime {
            let handled = max(0, (handledAt - eventTime) * 1000)
            let done = max(0, (doneAt - eventTime) * 1000)
            deliveryMs.append(handled)
            upToInsertMs.append(done)
            delivery = handled
            upToInsert = done
        }
        guard keepsDetail else { return }
        detail.append(DiagnosticSession.Touch(
            t: handledAt - start, key: [position.row, position.column], kind: kind.rawValue,
            outcome: record.outcome.rawValue, deliveryMs: delivery, upToInsertMs: upToInsert))
    }
}
