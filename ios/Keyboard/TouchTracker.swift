import Foundation

/// The key area's touch logic without UIKit, so it can be unit tested. `KeysUIView` turns UIKit touches into
/// `Event`s, performs the returned `Action`s in order and hands the `Record`s to the diagnostics journal.
/// - popup, haptic and click fire on touch-down, the character is inserted on touch-up (like iOS);
/// - fast typing rolls over: a new press commits a character — or a space — that is still held, so the text
///   keeps the order the keys were pressed in;
/// - sliding the finger moves the popup to the key under it; dragging space moves the cursor.
struct TouchTracker {
    enum KeyKind: String {
        case character, space, newline, backspace, shift
        /// Acts on touch-up: globe, КИР/LAT, emoji, 123/ABC/#+=.
        case function
    }

    enum Event {
        /// `alive` is every touch UIKit still tracks (`event.allTouches`); a remembered touch missing from it
        /// never delivered its end.
        case began(id: ObjectIdentifier, key: Int, x: CGFloat, time: TimeInterval, alive: Set<ObjectIdentifier>)
        case moved(id: ObjectIdentifier, key: Int?, x: CGFloat)
        case ended(id: ObjectIdentifier, time: TimeInterval)
        case cancelled(id: ObjectIdentifier)
        /// The keys are about to be rebuilt (layer or alphabet change); `keys` is replaced right after.
        case willRebuild
    }

    enum Action: Equatable {
        /// Haptic and key click.
        case keyDown
        case type(key: Int)
        case space
        case newline
        case backspace
        case shift
        /// Touch-up action of a `.function` key.
        case release(key: Int)
        case press(key: Int)
        case unpress(key: Int)
        case startRepeat
        case stopRepeat
        case beginCursorDrag(key: Int)
        case endCursorDrag(key: Int)
        case moveCursor(Int)
        case showPopup(key: Int)
        case hidePopup
    }

    struct Record: Equatable {
        var key: Int
        var outcome: TouchOutcome
        /// When the touch event that caused the action happened (`UITouch.timestamp`). Nil when no touch event
        /// did — a rebuild, a recovered end, a cancellation — so it stays out of the latency figures.
        var eventTime: TimeInterval?
    }

    struct Output: Equatable {
        var actions: [Action] = []
        var records: [Record] = []
    }

    private struct Touch {
        let id: ObjectIdentifier
        var key: Int
        let startX: CGFloat
        var committed = false
        var slid = false
        var dragging = false
        var consumed: CGFloat = 0
    }

    /// Kind of each key, by index. Set after every rebuild.
    var keys: [KeyKind] = []
    private var touches: [Touch] = []
    private var popupOwner: ObjectIdentifier?

    mutating func handle(_ event: Event) -> Output {
        var out = Output()
        switch event {
        case let .began(id, key, x, time, alive):
            began(id: id, key: key, x: x, time: time, alive: alive, into: &out)
        case let .moved(id, key, x):
            moved(id: id, key: key, x: x, into: &out)
        case let .ended(id, time):
            ended(id: id, time: time, into: &out)
        case let .cancelled(id):
            cancelled(id: id, into: &out)
        case .willRebuild:
            willRebuild(into: &out)
        }
        return out
    }

    private mutating func began(
        id: ObjectIdentifier, key: Int, x: CGFloat, time: TimeInterval, alive: Set<ObjectIdentifier>,
        into out: inout Output
    ) {
        // UIKit reuses UITouch objects, so a remembered touch with this id, or one UIKit no longer tracks, lost
        // its end somewhere. The user did press it: type what it still holds instead of letting it swallow
        // the presses that follow.
        for stale in touches where stale.id == id || !alive.contains(stale.id) {
            if !stale.committed, keys[stale.key] == .character {
                out.actions.append(.type(key: stale.key))
                out.records.append(Record(key: stale.key, outcome: .recoveredMissingEnd, eventTime: nil))
            }
            finish(stale, into: &out)
        }
        // Rollover: the new finger commits what the others still hold.
        for index in touches.indices where !touches[index].committed {
            let held = touches[index]
            switch keys[held.key] {
            case .character:
                out.actions.append(.type(key: held.key))
                out.records.append(Record(key: held.key, outcome: .rolledOver, eventTime: time))
                if popupOwner == held.id {
                    out.actions.append(.hidePopup)
                    popupOwner = nil
                }
            case .space where !held.dragging:
                out.actions.append(.space)
                out.records.append(Record(key: held.key, outcome: .function, eventTime: time))
            default:
                continue
            }
            touches[index].committed = true
        }

        var touch = Touch(id: id, key: key, startX: x)
        out.actions.append(.keyDown)
        switch keys[key] {
        case .character:
            out.actions.append(.showPopup(key: key))
            popupOwner = id
        case .shift:
            // Like iOS: shift reacts on touch-down.
            touch.committed = true
            out.actions.append(.shift)
            out.records.append(Record(key: key, outcome: .function, eventTime: time))
        case .backspace:
            touch.committed = true
            out.actions += [.press(key: key), .backspace, .startRepeat]
            out.records.append(Record(key: key, outcome: .function, eventTime: time))
        case .space, .newline, .function:
            out.actions.append(.press(key: key))
        }
        touches.append(touch)
    }

    private mutating func moved(id: ObjectIdentifier, key: Int?, x: CGFloat, into out: inout Output) {
        guard let index = touches.firstIndex(where: { $0.id == id }) else { return }
        let touch = touches[index]
        switch keys[touch.key] {
        case .space:
            dragCursor(index, x: x, into: &out)
        case .character where !touch.committed:
            guard let key, key != touch.key, keys[key] == .character else { return }
            touches[index].key = key
            touches[index].slid = true
            out.actions.append(.showPopup(key: key))
        default:
            break
        }
    }

    private mutating func dragCursor(_ index: Int, x: CGFloat, into out: inout Output) {
        let step: CGFloat = 9
        let dx = x - touches[index].startX
        if !touches[index].dragging {
            // A space already typed by a rollover must not start moving the cursor as well.
            guard abs(dx) > 12, !touches[index].committed else { return }
            touches[index].dragging = true
            touches[index].consumed = dx
            out.actions.append(.beginCursorDrag(key: touches[index].key))
        }
        let steps = Int((dx - touches[index].consumed) / step)
        if steps != 0 {
            out.actions.append(.moveCursor(steps))
            touches[index].consumed += CGFloat(steps) * step
        }
    }

    private mutating func ended(id: ObjectIdentifier, time: TimeInterval, into out: inout Output) {
        guard let touch = touches.first(where: { $0.id == id }) else { return }
        if !touch.committed {
            switch keys[touch.key] {
            case .character:
                out.actions.append(.type(key: touch.key))
                out.records.append(Record(key: touch.key, outcome: touch.slid ? .slid : .typed, eventTime: time))
            case .space:
                if !touch.dragging {
                    out.actions.append(.space)
                    out.records.append(Record(key: touch.key, outcome: .function, eventTime: time))
                }
            case .newline:
                out.actions.append(.newline)
                out.records.append(Record(key: touch.key, outcome: .function, eventTime: time))
            case .function:
                out.actions.append(.release(key: touch.key))
                out.records.append(Record(key: touch.key, outcome: .function, eventTime: time))
            case .shift, .backspace:
                break
            }
        }
        finish(touch, into: &out)
    }

    private mutating func cancelled(id: ObjectIdentifier, into out: inout Output) {
        guard let touch = touches.first(where: { $0.id == id }) else { return }
        if !touch.committed, !touch.dragging {
            out.records.append(Record(key: touch.key, outcome: .cancelledBySystem, eventTime: nil))
        }
        finish(touch, into: &out)
    }

    private mutating func willRebuild(into out: inout Output) {
        for touch in touches {
            if !touch.committed, keys[touch.key] == .character {
                out.actions.append(.type(key: touch.key))
                out.records.append(Record(key: touch.key, outcome: .committedOnRebuild, eventTime: nil))
            }
            if keys[touch.key] == .backspace { out.actions.append(.stopRepeat) }
        }
        if popupOwner != nil {
            out.actions.append(.hidePopup)
            popupOwner = nil
        }
        touches.removeAll()
    }

    private mutating func finish(_ touch: Touch, into out: inout Output) {
        switch keys[touch.key] {
        case .character:
            break
        case .backspace:
            out.actions += [.unpress(key: touch.key), .stopRepeat]
        case .space, .newline, .shift, .function:
            out.actions.append(.unpress(key: touch.key))
        }
        if touch.dragging { out.actions.append(.endCursorDrag(key: touch.key)) }
        if popupOwner == touch.id {
            out.actions.append(.hidePopup)
            popupOwner = nil
        }
        touches.removeAll { $0.id == touch.id }
    }
}
