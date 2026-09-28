import SwiftUI
import UIKit

/// SwiftUI slot for the UIKit key area. Only the layout inputs are passed in, so typing
/// (which changes none of them) never goes through SwiftUI at all.
struct KeysRepresentable: UIViewRepresentable {
    let model: KeyboardModel
    let config: KeysUIView.Config

    func makeUIView(context: Context) -> KeysUIView { KeysUIView(model: model) }

    func updateUIView(_ view: KeysUIView, context: Context) { view.apply(config) }
}

/// The key area in plain UIKit. SwiftUI gestures added a noticeable delay per press and the key
/// popup often never rendered on a quick tap; here touches arrive in `touchesBegan` directly.
/// What a touch does is decided by `TouchTracker`; this view draws the keys and carries out its actions.
final class KeysUIView: UIView {
    struct Config: Equatable {
        var layer: KeyboardModel.Layer
        var shift: KeyboardModel.Shift
        var alphabet: KeyboardModel.Alphabet
        var showsGlobe: Bool
        /// App setting: an emoji key replaces КИР/LAT.
        var emojiKey: Bool
    }

    enum Key: Equatable {
        case char(String)
        case shift, backspace, globe, space, newline, alphabet, emoji
        case layer(KeyboardModel.Layer, String)

        var kind: TouchTracker.KeyKind {
            switch self {
            case .char: .character
            case .space: .space
            case .newline: .newline
            case .backspace: .backspace
            case .shift: .shift
            case .globe, .alphabet, .emoji, .layer: .function
            }
        }
    }

    private static let latin = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
    /// Uzbek Cyrillic on the ЙЦУКЕН base; ғ and ҳ sit in the bottom row, like oʻ/gʻ in Latin.
    private static let cyrillic = [
        ["й", "ц", "у", "к", "е", "н", "г", "ш", "ў", "з", "х", "ъ"],
        ["ф", "қ", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
        ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"],
    ]
    private static let numbers = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
    ]
    private static let symbols = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
    ]
    private static let punctuation = [".", ",", "?", "!", "'"]

    private let model: KeyboardModel
    private var config: Config?
    private var needsRebuild = true
    private var builtWidth: CGFloat = 0
    private var caps: [KeyCapView] = []
    private var hitFrames: [CGRect] = []
    private var positions: [TouchJournal.KeyPosition] = []
    private var tracker = TouchTracker()
    private let popup = KeyPopupView()
    private var repeatTimer: Timer?

    init(model: KeyboardModel) {
        self.model = model
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ new: Config) {
        let old = config
        guard new != old else { return }
        config = new
        if old?.layer != new.layer || old?.alphabet != new.alphabet || old?.showsGlobe != new.showsGlobe
            || old?.emojiKey != new.emojiKey {
            needsRebuild = true
            setNeedsLayout()
        } else {
            updateLabels()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard config != nil, bounds.width > 0, needsRebuild || builtWidth != bounds.width else { return }
        rebuild()
    }

    // MARK: Layout

    private func rows(width: CGFloat, config: Config) -> [[(Key, CGFloat)]] {
        let gap = KeyboardMetrics.keyGap
        let full = width - KeyboardMetrics.sideInset * 2
        let baseUnit = (full - gap * 9) / 10
        var rows: [[(Key, CGFloat)]] = []

        switch config.layer {
        case .letters:
            let letters = config.alphabet == .latin ? Self.latin : Self.cyrillic
            let columns = CGFloat(letters[0].count)
            let unit = (full - gap * (columns - 1)) / columns
            let bottomLetters = CGFloat(letters[2].count)
            let side = (full - unit * bottomLetters - gap * (bottomLetters + 1)) / 2
            rows.append(letters[0].map { (.char($0), unit) })
            rows.append(letters[1].map { (.char($0), unit) })
            rows.append([(.shift, side)] + letters[2].map { (.char($0), unit) } + [(.backspace, side)])
        case .numbers, .symbols:
            let chars = config.layer == .numbers ? Self.numbers : Self.symbols
            let toggle: Key = config.layer == .numbers ? .layer(.symbols, "#+=") : .layer(.numbers, "123")
            let side = baseUnit * 1.5 + gap / 2
            let punctuationWidth = (full - side * 2 - gap * 6) / 5
            rows.append(chars[0].map { (.char($0), baseUnit) })
            rows.append(chars[1].map { (.char($0), baseUnit) })
            rows.append([(toggle, side)] + Self.punctuation.map { (.char($0), punctuationWidth) } + [(.backspace, side)])
        }

        var bottom: [(Key, CGFloat)] = []
        bottom.append((config.layer == .letters ? .layer(.numbers, "123") : .layer(.letters, "ABC"), baseUnit * 1.25))
        if config.showsGlobe { bottom.append((.globe, baseUnit * 1.1)) }
        if config.layer == .letters {
            bottom.append((config.emojiKey ? .emoji : .alphabet, baseUnit * 1.25))
            let extras = config.alphabet == .latin ? ["oʻ", "gʻ"] : ["ғ", "ҳ"]
            bottom += extras.map { (.char($0), baseUnit) }
        }
        let returnWidth = baseUnit * 2
        let used = bottom.reduce(0) { $0 + $1.1 } + returnWidth + gap * CGFloat(bottom.count + 1)
        bottom.append((.space, max(baseUnit * 2, full - used)))
        bottom.append((.newline, returnWidth))
        rows.append(bottom)
        return rows
    }

    private func rebuild() {
        guard let config else { return }
        // Types what a finger still holds on the old keys before they go away (it used to be dropped).
        run(.willRebuild)
        caps.forEach { $0.removeFromSuperview() }
        caps = []
        hitFrames = []
        positions = []

        let gap = KeyboardMetrics.keyGap
        let rowGap = KeyboardMetrics.rowGap
        let keyHeight = KeyboardMetrics.keyHeight
        let rows = rows(width: bounds.width, config: config)
        var y = KeyboardMetrics.keysTopInset
        for (rowIndex, row) in rows.enumerated() {
            let total = row.reduce(0) { $0 + $1.1 } + gap * CGFloat(row.count - 1)
            var x = (bounds.width - total) / 2
            for (column, (key, width)) in row.enumerated() {
                let cap = KeyCapView(key: key)
                cap.frame = CGRect(x: x, y: y, width: width, height: keyHeight)
                addSubview(cap)
                caps.append(cap)
                // Gaps belong to the nearest key; the outer keys own everything up to the edges.
                let left = column == 0 ? 0 : x - gap / 2
                let right = column == row.count - 1 ? bounds.width : x + width + gap / 2
                let top = rowIndex == 0 ? 0 : y - rowGap / 2
                let bottomEdge = rowIndex == rows.count - 1 ? bounds.height : y + keyHeight + rowGap / 2
                hitFrames.append(CGRect(x: left, y: top, width: right - left, height: bottomEdge - top))
                positions.append(TouchJournal.KeyPosition(
                    row: rowIndex, column: column, rowLength: row.count, isBottomRow: rowIndex == rows.count - 1))
                x += width + gap
            }
            y += keyHeight + rowGap
        }
        tracker.keys = caps.map(\.key.kind)
        builtWidth = bounds.width
        needsRebuild = false
        updateLabels()
    }

    private func updateLabels() {
        guard let config else { return }
        for cap in caps { cap.configure(config) }
    }

    private func keyIndex(at point: CGPoint) -> Int? {
        hitFrames.firstIndex { $0.contains(point) }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let alive = Set((event?.allTouches ?? touches).map { ObjectIdentifier($0) })
        for touch in touches {
            let point = touch.location(in: self)
            guard let key = keyIndex(at: point) else { continue }
            run(.began(id: ObjectIdentifier(touch), key: key, x: point.x, time: touch.timestamp, alive: alive))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            run(.moved(id: ObjectIdentifier(touch), key: keyIndex(at: point), x: point.x))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            run(.ended(id: ObjectIdentifier(touch), time: touch.timestamp))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            run(.cancelled(id: ObjectIdentifier(touch)))
        }
    }

    /// Feeds one event to the tracker and carries out its actions. With Diagnostika on, the outcomes and their
    /// timing go to the session journal (`systemUptime` is the clock `UITouch.timestamp` uses).
    private func run(_ event: TouchTracker.Event) {
        let handledAt = ProcessInfo.processInfo.systemUptime
        let output = Signposts.measure("touch") { () -> TouchTracker.Output in
            let output = tracker.handle(event)
            output.actions.forEach(perform)
            return output
        }
        guard !output.records.isEmpty, let diagnostics = model.diagnostics else { return }
        let doneAt = ProcessInfo.processInfo.systemUptime
        for record in output.records where record.key < positions.count {
            diagnostics.journal.record(
                record, at: positions[record.key], kind: tracker.keys[record.key],
                handledAt: handledAt, doneAt: doneAt)
        }
    }

    private func perform(_ action: TouchTracker.Action) {
        switch action {
        case .keyDown:
            model.keyDown()
        case .type(let key):
            if case .char(let character) = caps[key].key { model.type(character) }
        case .space:
            model.space()
        case .newline:
            model.newline()
        case .backspace:
            model.backspace()
        case .shift:
            model.tapShift()
        case .release(let key):
            release(caps[key].key)
        case .press(let key):
            caps[key].isPressed = true
        case .unpress(let key):
            if key < caps.count { caps[key].isPressed = false }
        case .startRepeat:
            startRepeat()
        case .stopRepeat:
            stopRepeat()
        case .beginCursorDrag(let key):
            caps[key].showDragHint()
        case .endCursorDrag(let key):
            if key < caps.count, let config { caps[key].configure(config) }
        case .moveCursor(let offset):
            model.moveCursor(by: offset)
        case .showPopup(let key):
            showPopup(key)
        case .hidePopup:
            popup.isHidden = true
        }
    }

    private func release(_ key: Key) {
        switch key {
        case .globe: model.switchKeyboard()
        case .alphabet: model.toggleAlphabet()
        case .emoji: model.showsEmoji = true
        case .layer(let layer, _): model.setLayer(layer)
        case .char, .shift, .backspace, .space, .newline: break
        }
    }

    private func startRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.model.backspace() }
                }
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    // MARK: Popup

    /// Drawn in the keyboard's root view so the top row's popup can rise over the suggestion bar.
    private func showPopup(_ key: Int) {
        guard let host = model.controller?.view ?? superview else { return }
        let cap = caps[key]
        popup.show(text: cap.displayText, keyFrame: convert(cap.frame, to: host), in: host)
    }
}

// MARK: - Key cap

private final class KeyCapView: UIView {
    let key: KeysUIView.Key
    private(set) var displayText = ""
    private let plate = UIView()
    private let label = UILabel()
    private let icon = UIImageView()
    private var isFunction = false

    var isPressed = false {
        didSet { if isPressed != oldValue { updateColor() } }
    }

    init(key: KeysUIView.Key) {
        self.key = key
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        plate.layer.cornerRadius = 5
        plate.layer.cornerCurve = .continuous
        // Cheap 1pt drop shadow: an explicit shadowPath avoids the offscreen pass `.shadow` needed.
        plate.layer.shadowColor = UIColor.black.cgColor
        plate.layer.shadowOpacity = 0.3
        plate.layer.shadowOffset = CGSize(width: 0, height: 1)
        plate.layer.shadowRadius = 0
        addSubview(plate)
        label.textAlignment = .center
        label.textColor = .label
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        addSubview(label)
        icon.contentMode = .center
        icon.tintColor = .label
        addSubview(icon)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        plate.frame = bounds
        plate.layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 5).cgPath
        label.frame = bounds.insetBy(dx: 2, dy: 0)
        icon.frame = bounds
    }

    func configure(_ config: KeysUIView.Config) {
        switch key {
        case .char(let character):
            let upper = config.layer == .letters && config.shift != .off
            displayText = upper ? character.uppercased() : character
            let isLetter = config.layer == .letters && character.count == 1
            setTitle(displayText, size: isLetter ? 23 : 19)
            isFunction = false
        case .shift:
            let name = config.shift == .locked ? "capslock.fill" : config.shift == .once ? "shift.fill" : "shift"
            setSymbol(name)
            isFunction = config.shift == .off
        case .backspace:
            setSymbol("delete.left")
            isFunction = true
        case .globe:
            setSymbol("globe", weight: .regular)
            isFunction = true
        case .newline:
            setSymbol("return")
            isFunction = true
        case .space:
            setTitle("space", size: 16)
            isFunction = false
        case .alphabet:
            setTitle(config.alphabet == .latin ? "КИР" : "LAT", size: 15, weight: .medium)
            isFunction = true
        case .emoji:
            setSymbol("face.smiling", weight: .regular)
            isFunction = true
        case .layer(_, let title):
            setTitle(title, size: 16)
            isFunction = true
        }
        updateColor()
    }

    func showDragHint() {
        setTitle("◀︎   ▶︎", size: 16)
    }

    private func setTitle(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular) {
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.isHidden = false
        icon.isHidden = true
    }

    private func setSymbol(_ name: String, weight: UIImage.SymbolWeight = .medium) {
        icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: weight))
        icon.isHidden = false
        label.isHidden = true
    }

    private func updateColor() {
        plate.backgroundColor = isPressed
            ? KeyboardColors.pressedUI
            : isFunction ? KeyboardColors.functionKeyUI : KeyboardColors.keyUI
    }
}

// MARK: - Popup

/// The iOS-style balloon: the pressed key grows upwards into a wider bubble with the enlarged character.
private final class KeyPopupView: UIView {
    private let shape = CAShapeLayer()
    private let label = UILabel()
    // bubble + neck + top-row key must fit under the collapsed 46pt bar (the keyboard cannot draw above itself).
    private let bubbleHeight: CGFloat = 48
    private let neck: CGFloat = 6
    private let widen: CGFloat = 11

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = 0.28
        shape.shadowOffset = CGSize(width: 0, height: 1)
        shape.shadowRadius = 1.5
        layer.addSublayer(shape)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 32, weight: .regular)
        label.textColor = .label
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(text: String, keyFrame key: CGRect, in host: UIView) {
        // Widen evenly but never past the keyboard edges.
        let left = min(widen, max(0, key.minX - 1))
        let right = min(widen, max(0, host.bounds.width - key.maxX - 1))
        let bubbleWidth = key.width + left + right
        let height = bubbleHeight + neck + key.height
        frame = CGRect(x: key.minX - left, y: key.maxY - height, width: bubbleWidth, height: height)

        // Local coordinates: bubble on top, key-sized stem at the bottom.
        let stem = CGRect(x: left, y: height - key.height, width: key.width, height: key.height)
        let r: CGFloat = 8
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), controlPoint: .zero)
        path.addLine(to: CGPoint(x: bubbleWidth - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: bubbleWidth, y: r), controlPoint: CGPoint(x: bubbleWidth, y: 0))
        path.addLine(to: CGPoint(x: bubbleWidth, y: bubbleHeight - r))
        path.addQuadCurve(to: CGPoint(x: stem.maxX, y: bubbleHeight + neck), controlPoint: CGPoint(x: stem.maxX, y: bubbleHeight))
        path.addLine(to: CGPoint(x: stem.maxX, y: stem.maxY - 5))
        path.addQuadCurve(to: CGPoint(x: stem.maxX - 5, y: stem.maxY), controlPoint: CGPoint(x: stem.maxX, y: stem.maxY))
        path.addLine(to: CGPoint(x: stem.minX + 5, y: stem.maxY))
        path.addQuadCurve(to: CGPoint(x: stem.minX, y: stem.maxY - 5), controlPoint: CGPoint(x: stem.minX, y: stem.maxY))
        path.addLine(to: CGPoint(x: stem.minX, y: bubbleHeight + neck))
        path.addQuadCurve(to: CGPoint(x: 0, y: bubbleHeight - r), controlPoint: CGPoint(x: stem.minX, y: bubbleHeight))
        path.close()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path.cgPath
        shape.shadowPath = path.cgPath
        shape.fillColor = KeyboardColors.keyUI.resolvedColor(with: host.traitCollection).cgColor
        CATransaction.commit()

        label.text = text
        label.frame = CGRect(x: 0, y: 4, width: bubbleWidth, height: bubbleHeight - 8)
        if superview !== host { host.addSubview(self) } else { host.bringSubviewToFront(self) }
        isHidden = false
    }
}
