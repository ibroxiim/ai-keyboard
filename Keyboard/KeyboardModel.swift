import SwiftUI
import UIKit

/// `@Observable` (not `ObservableObject`) so a keystroke only redraws the views that read what changed —
/// with `@Published` every insert re-rendered all ~35 keys and the suggestion bar, which made typing lag.
/// For the same reason observed properties are only written when their value actually changes.
@MainActor
@Observable
final class KeyboardModel {
    enum Layer { case letters, numbers, symbols }
    enum Shift { case off, once, locked }
    enum Alphabet: String { case latin, cyrillic }

    var layer: Layer = .letters
    /// Remembered in the extension's own defaults — works without Full Access.
    var alphabet = Alphabet(rawValue: UserDefaults.standard.string(forKey: "alphabet") ?? "") ?? .latin
    var shift: Shift = .off
    var state = SharedState()
    /// ✨ results for what the user typed; while non-empty they replace the screenshot suggestions.
    var variants: [Suggestion] = []
    var isRewriting = false
    var notice: String?
    var showsDetails = false
    var hasFullAccess = false
    var showsGlobe = false
    /// The friend/language chip row, opened from the collapsed "✨ → English ⌄" pill.
    var showsTargetPicker = false
    var showsEmoji = false
    /// Context freshness is time-based; views read it against this, refreshed on every appearance,
    /// so an expired screenshot also disappears (and the bar collapses) without any state change.
    var now = Date()

    @ObservationIgnored weak var controller: UIInputViewController?

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }
    @ObservationIgnored private var lastShiftTap: Date?
    @ObservationIgnored private var lastSpaceTap: Date?
    @ObservationIgnored private var rewriteTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private let haptics = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private let selectionHaptics = UISelectionFeedbackGenerator()

    enum Target: Identifiable, Hashable {
        case friend(Friend)
        case language(String)

        var id: String {
            switch self {
            case .friend(let friend): "friend:\(friend.name)"
            case .language(let language): "language:\(language)"
            }
        }
    }

    var context: ChatAnalysis? { state.freshContext(at: now) }
    var chips: [Suggestion] { variants.isEmpty ? (context?.suggestions ?? []) : variants }

    /// The chip row costs ~62pt of the chat above the keyboard; show it only when it has something in it.
    var barExpanded: Bool { !chips.isEmpty || state.isAnalyzing || showsTargetPicker }

    /// Without a fresh screenshot the chip row picks who we are writing to: recent friends first, then plain languages.
    var targets: [Target] {
        (state.friends ?? []).prefix(5).map(Target.friend) + Languages.common.map(Target.language)
    }

    func isSelected(_ target: Target) -> Bool {
        switch target {
        case .friend(let friend): state.activeFriend == friend.name
        case .language(let language): state.activeFriend == nil && state.language == language
        }
    }

    func reloadState() {
        let loaded = SharedStore.load()
        guard loaded != state else { return }
        let previousContextDate = state.contextDate
        state = loaded
        // ✨ variants belong to the chat they were made for.
        if state.contextDate != previousContextDate, !variants.isEmpty { variants = [] }
        if context == nil, showsDetails { showsDetails = false }
        // Suggestions take over the row once a screenshot lands.
        if context != nil, showsTargetPicker { showsTargetPicker = false }
    }

    func toggleTargetPicker() {
        keyDown()
        showsTargetPicker.toggle()
    }

    /// Setup checklist proof for the app. Only a keyboard with Full Access can write to the App Group.
    func confirmFullAccess() {
        guard hasFullAccess else { return }
        var cleaned = state
        cleaned.mergeDuplicateFriends()
        let needsWrite = state.keyboardFullAccessDate == nil || cleaned != state
        guard needsWrite else { return }
        SharedStore.update {
            if $0.keyboardFullAccessDate == nil { $0.keyboardFullAccessDate = Date() }
            $0.mergeDuplicateFriends()
        }
        reloadState()
    }

    func select(_ target: Target) {
        SharedStore.update {
            switch target {
            case .friend(let friend):
                $0.activeFriend = friend.name
                $0.targetLanguage = friend.language
            case .language(let language):
                $0.activeFriend = nil
                $0.targetLanguage = language
            }
        }
        keyDown()
        reloadState()
        showsTargetPicker = false
    }

    // MARK: Typing

    /// Touch-down on any key: haptic right away (not after the insert), then re-arm the Taptic Engine —
    /// an unprepared generator is what made the haptic lag.
    func keyDown() {
        // System key click; plays only if the user has "Keyboard Clicks" on (KeyboardInputView opts in).
        UIDevice.current.playInputClick()
        guard hasFullAccess else { return }
        haptics.impactOccurred()
        haptics.prepare()
    }

    func prepareHaptics() {
        if hasFullAccess { haptics.prepare() }
    }

    func type(_ text: String) {
        proxy?.insertText(shift == .off ? text : text.uppercased())
        if shift == .once { setShift(.off) }
        autoCapitalize()
    }

    func backspace() {
        proxy?.deleteBackward()
        autoCapitalize()
    }

    func space() {
        // Double space → ". " like the system keyboard.
        let before = proxy?.documentContextBeforeInput ?? ""
        if let last = lastSpaceTap, Date().timeIntervalSince(last) < 0.35,
           before.hasSuffix(" "), let previous = before.dropLast().last, previous.isLetter || previous.isNumber {
            proxy?.deleteBackward()
            proxy?.insertText(". ")
            lastSpaceTap = nil
        } else {
            proxy?.insertText(" ")
            lastSpaceTap = Date()
        }
        if layer != .letters { layer = .letters }
        autoCapitalize()
    }

    func newline() {
        proxy?.insertText("\n")
        autoCapitalize()
    }

    func tapShift() {
        let now = Date()
        if let last = lastShiftTap, now.timeIntervalSince(last) < 0.3 {
            setShift(.locked)
        } else {
            setShift(shift == .off ? .once : .off)
        }
        lastShiftTap = now
    }

    func insertEmoji(_ emoji: String) {
        keyDown()
        proxy?.insertText(emoji)
        EmojiRecents.add(emoji)
    }

    func setLayer(_ value: Layer) {
        if layer != value { layer = value }
        autoCapitalize()
    }

    func switchKeyboard() {
        controller?.advanceToNextInputMode()
    }

    func toggleAlphabet() {
        alphabet = alphabet == .latin ? .cyrillic : .latin
        UserDefaults.standard.set(alphabet.rawValue, forKey: "alphabet")
    }

    func moveCursor(by offset: Int) {
        proxy?.adjustTextPosition(byCharacterOffset: offset)
        if hasFullAccess { selectionHaptics.selectionChanged() }
    }

    func autoCapitalize() {
        guard layer == .letters, shift != .locked else { return }
        if proxy?.autocapitalizationType == UITextAutocapitalizationType.none {
            setShift(.off)
            return
        }
        let before = proxy?.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let sentenceEnded = trimmed.last.map { ".!?".contains($0) } ?? false
        let startsSentence = trimmed.isEmpty || before.hasSuffix("\n") || (sentenceEnded && before.hasSuffix(" "))
        setShift(startsSentence ? .once : .off)
    }

    private func setShift(_ value: Shift) {
        if shift != value { shift = value }
    }

    // MARK: AI

    /// ✨ — rewrite whatever is in the field into the conversation language, fitted to the screenshot context.
    func magic() {
        guard hasFullAccess else {
            flash("✨ uchun Settings'da AI Keyboard → Allow Full Access'ni yoqing")
            return
        }
        let draft = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            flash(context == nil
                ? "Avval o'zbekcha yozing, keyin ✨ ni bosing"
                : "Tayyor javoblardan birini tanlang yoki o'zbekcha yozib ✨ ni bosing")
            return
        }
        rewriteTask?.cancel()
        isRewriting = true
        let context = context
        let friend = state.activeFriendProfile
        let language = state.language
        rewriteTask = Task {
            defer { isRewriting = false }
            do {
                let result = try await Translator.rewrite(
                    draft: draft, context: context, friend: friend, language: language)
                guard !Task.isCancelled else { return }
                variants = result
            } catch {
                guard !Task.isCancelled else { return }
                flash(error.localizedDescription)
            }
        }
    }

    func pick(_ suggestion: Suggestion) {
        keyDown()
        replaceAllText(with: suggestion.text)
        variants = []
    }

    func dismissVariants() {
        variants = []
    }

    func dismissContext() {
        SharedStore.update {
            $0.context = nil
            $0.contextDate = nil
        }
        variants = []
        reloadState()
    }

    // MARK: Helpers

    private var currentText: String {
        (proxy?.documentContextBeforeInput ?? "") + (proxy?.documentContextAfterInput ?? "")
    }

    /// The DM field holds only the draft, so a picked reply replaces all of it.
    private func replaceAllText(with text: String) {
        guard let proxy else { return }
        let after = proxy.documentContextAfterInput ?? ""
        if !after.isEmpty { proxy.adjustTextPosition(byCharacterOffset: after.utf16.count) }
        // documentContextBeforeInput can be truncated by the host app, so keep deleting until it is empty.
        var rounds = 0
        while let before = proxy.documentContextBeforeInput, !before.isEmpty, rounds < 10 {
            for _ in 0..<before.count { proxy.deleteBackward() }
            rounds += 1
        }
        proxy.insertText(text)
    }

    private func flash(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }
}
