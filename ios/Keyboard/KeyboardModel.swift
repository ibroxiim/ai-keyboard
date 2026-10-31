import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// `@Observable` (not `ObservableObject`) so a keystroke only redraws the views that read what changed —
/// with `@Published` every insert would re-render all ~35 keys and the suggestion bar, and typing would lag.
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
    /// ✨ results for what the user typed; while non-empty they replace the screenshot suggestions. They stay
    /// after one is picked, so another one — or the original draft — can be put in instead.
    var variants: [Suggestion] = []
    /// What was in the field when ✨ was tapped, so a picked variant is not a one-way door. Lives with `variants`.
    var originalDraft: String?
    /// The variant now in the field, for the highlight; nil while the field holds the original draft.
    var pickedVariantID: Suggestion.ID?
    /// "qisqaroq", "iliqroq"… asked of the current variants; every change asks for them again.
    var tweaks: [RewriteTweak] = []
    /// 📋: the pasteboard holds text the keyboard has not offered yet (see `checkClipboard`).
    var clipboardOffered = false
    @ObservationIgnored private var clipboardChecked = Date.distantPast
    /// The field's last non-empty text while a variant was in it — what the user sent once it is empty.
    @ObservationIgnored private var lastSeenText: String?
    var isRewriting = false
    var notice: String?
    var showsDetails = false
    /// A chip cuts a reply at two lines; this is the full-size list of every reply over the keys.
    var showsVariantList = false
    /// The reply the list scrolls to when it opens (long press on a chip); nil — the top.
    var variantListFocus: Suggestion.ID?
    /// Voice dictation: when 🎤 was tapped and the app has not started recording yet (see `VoiceStatus`).
    var voiceOpeningSince: Date?
    var hasFullAccess = false
    var showsGlobe = false
    /// The friend/language chip row, opened from the collapsed "✨ → English ⌄" pill.
    var showsTargetPicker = false
    var showsEmoji = false
    /// GIF search in place of the bar; while it is open the keys type into `gifQuery`, not the host app.
    var showsGif = false
    var gifQuery = ""
    var gifs: [Gif] = []
    var gifLoading = false
    /// What the empty strip says: an error, or "nothing found".
    var gifStatus: String?
    @ObservationIgnored private var gifTask: Task<Void, Never>?
    /// Context freshness is time-based; views read it against this, refreshed on every appearance,
    /// so an expired screenshot also disappears (and the bar collapses) without any state change.
    var now = Date()
    /// "⏳ 2 kun" beside the target pill while the signing profile is about to run out (see `ProvisioningExpiry`).
    var expiryNote: String?

    @ObservationIgnored weak var controller: UIInputViewController?
    /// Opens a URL in the app; set by the view controller (an extension cannot use `UIApplication.shared`).
    @ObservationIgnored var openApp: ((URL) -> Void)?
    /// The voice session this keyboard asked the app for; its result is inserted without asking. Kept in the
    /// extension's own defaults: iOS often ends a keyboard's process while the app is in front, and the id has to
    /// outlive that for the text to land by itself when the user comes back.
    var pendingVoiceID: String? {
        get { UserDefaults.standard.string(forKey: "pendingVoiceID") }
        set { UserDefaults.standard.set(newValue, forKey: "pendingVoiceID") }
    }
    @ObservationIgnored private var voiceOpenTask: Task<Void, Never>?
    /// Set while the Diagnostika switch records this appearance; `KeysUIView` writes touches into its journal.
    @ObservationIgnored var diagnostics: KeyboardDiagnostics?

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }
    @ObservationIgnored private var lastShiftTap: Date?
    @ObservationIgnored private var lastSpaceTap: Date?
    @ObservationIgnored private var rewriteTask: Task<Void, Never>?
    /// `replaceAllText` empties the field on its way; `textChanged` must not take that for a sent message.
    @ObservationIgnored private var isReplacingText = false
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
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
    /// Read against `now`, like `context`, so a timed-out spinner or an old error goes away on its own.
    var isAnalyzing: Bool { state.isAnalyzing(at: now) }
    var recentError: String? { state.recentError(at: now) }
    var voiceStatus: VoiceStatus {
        VoiceStatus.of(voice: state.voice, pendingID: pendingVoiceID, openingSince: voiceOpeningSince, now: now)
    }
    var chips: [Suggestion] { variants.isEmpty ? (context?.suggestions ?? []) : variants }

    /// The chip row costs ~62pt of the chat above the keyboard; show it only when it has something in it.
    var barExpanded: Bool { !chips.isEmpty || isAnalyzing || showsTargetPicker }

    var barMode: KeyboardMetrics.BarMode { showsGif ? .gif : (barExpanded ? .expanded : .compact) }

    /// Without a fresh screenshot the chip row picks who we are writing to: recent friends first, then the languages the user picked in the app.
    var targets: [Target] {
        (state.friends ?? []).prefix(5).map(Target.friend) + state.languageList.map(Target.language)
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
        if state.contextDate != previousContextDate { clearVariants() }
        if context == nil, showsDetails { showsDetails = false }
        closeVariantListIfEmpty()
        // Suggestions take over the row once a screenshot lands.
        if context != nil, showsTargetPicker { showsTargetPicker = false }
        reconcileVoice()
        scheduleRefresh()
    }

    func openVariantList(focus: Suggestion? = nil) {
        guard !chips.isEmpty else { return }
        keyDown()
        if showsDetails { showsDetails = false }
        if showsEmoji { showsEmoji = false }
        if showsTargetPicker { showsTargetPicker = false }
        if variantListFocus != focus?.id { variantListFocus = focus?.id }
        if !showsVariantList { showsVariantList = true }
    }

    /// Written only when it changes, like every observed property.
    func closeVariantList() {
        if showsVariantList { showsVariantList = false }
        if variantListFocus != nil { variantListFocus = nil }
    }

    /// The replies expire or get dismissed; a list left open would reappear with the next ones.
    private func closeVariantListIfEmpty() {
        if chips.isEmpty { closeVariantList() }
    }

    func toggleDetails() {
        if !showsDetails { closeVariantList() }
        showsDetails.toggle()
    }

    // MARK: Voice

    /// 🎤: starts a session, stops the running one or puts a waiting result in.
    func tapMic() {
        guard hasFullAccess else {
            flash("🎤 uchun Settings'da AI Keyboard → Allow Full Access'ni yoqing")
            return
        }
        switch voiceStatus {
        case .recording:
            keyDown()
            DarwinNotification.post(AppGroup.voiceStopRequested)
        case .transcribing, .opening:
            break
        case .ready(let text):
            insertVoiceText(text)
        case .idle, .openFailed, .failed:
            startVoice()
        }
    }

    private func startVoice() {
        keyDown()
        let id = UUID().uuidString
        pendingVoiceID = id
        voiceOpeningSince = Date()
        openApp?(VoiceLink.url(id: id))
        // After the wait the status turns into "the app did not open"; nothing else would move `now` then.
        voiceOpenTask?.cancel()
        voiceOpenTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(VoiceStatus.openingTimeout + 0.2))
            guard !Task.isCancelled, let self else { return }
            now = Date()
        }
    }

    /// Called whenever the shared state or the time moves: the app answered, or our own session finished.
    func reconcileVoice() {
        if voiceOpeningSince != nil, state.activeVoice(at: now) != nil { voiceOpeningSince = nil }
        switch VoiceInsertion.decision(voice: state.voice, pendingID: pendingVoiceID, now: now) {
        case .insert(let text):
            insertVoiceText(text)
        case .failed(let message):
            // Told once, like any notice. Left in the state it kept the bar on the error — and the target pill
            // out of reach — for as long as the session lived.
            flash(message, for: 6)
            pendingVoiceID = nil
            if voiceOpeningSince != nil { voiceOpeningSince = nil }
            SharedStore.update { $0.voice = nil }
            reloadState()
        case .offer, .none:
            break
        }
    }

    private func insertVoiceText(_ text: String) {
        proxy?.insertText(VoiceInsertion.prepared(text, before: proxy?.documentContextBeforeInput))
        pendingVoiceID = nil
        if voiceOpeningSince != nil { voiceOpeningSince = nil }
        // Consumed: the next session starts clean, and a second keyboard does not offer it again.
        SharedStore.update { $0.voice = nil }
        reloadState()
        autoCapitalize()
    }

    /// The spinner, the error line and the context expire by time alone, and nothing else re-renders the bar
    /// when they do — a stuck `analyzingSince` kept the spinner turning at the display's refresh rate. Sleep
    /// until the next deadline instead of polling, then move `now`.
    func scheduleRefresh() {
        refreshTask?.cancel()
        guard let deadline = state.nextDeadline(after: now) else { return }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            now = Date()
            closeVariantListIfEmpty()
            reconcileVoice()
            scheduleRefresh()
        }
    }

    func stopRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        voiceOpenTask?.cancel()
        voiceOpenTask = nil
    }

    func toggleTargetPicker() {
        keyDown()
        showsTargetPicker.toggle()
    }

    // MARK: Clipboard

    /// A keyboard with Full Access may read the pasteboard, and iOS tells the user when it does. `changeCount`
    /// and `hasStrings` are not reading, so the offer costs nothing until it is tapped. Throttled: it is also
    /// called on text changes, and the pasteboard is another process.
    func checkClipboard(force: Bool = false) {
        guard force || clipboardChecked.timeIntervalSinceNow < -2 else { return }
        clipboardChecked = Date()
        let board = UIPasteboard.general
        let offered = hasFullAccess && board.changeCount != UserDefaults.standard.integer(forKey: "clipboardSeen")
            && board.hasStrings
        if clipboardOffered != offered { clipboardOffered = offered }
    }

    /// 📋 Tarjima — the copied message, read like a screenshot but from its exact text.
    func translateClipboard() {
        guard hasFullAccess else { return }
        keyDown()
        let board = UIPasteboard.general
        UserDefaults.standard.set(board.changeCount, forKey: "clipboardSeen")
        if clipboardOffered { clipboardOffered = false }
        guard let text = ClipboardOffer.usable(board.string) else {
            flash("Nusxada matn yo'q")
            return
        }
        let partner = state.activeFriendRecord
        let style = state.translationStyle
        let quality = state.quality
        // The same state the Back Tap intent writes, so the spinner, the line, the card and ✨ just follow.
        SharedStore.update {
            $0.analyzingSince = Date()
            $0.context = nil
            $0.contextDate = nil
        }
        reloadState()
        Task {
            do {
                let analysis = try await Signposts.measureAsync("clipboard") {
                    try await Translator.readClipboard(text: text, partner: partner, style: style, quality: quality)
                }
                SharedStore.update {
                    $0.context = analysis
                    $0.contextDate = Date()
                    $0.analyzingSince = nil
                    $0.lastError = nil
                    $0.lastErrorDate = nil
                    $0.remember(analysis)
                }
            } catch {
                SharedStore.update {
                    $0.analyzingSince = nil
                    $0.lastError = error.localizedDescription
                    $0.lastErrorDate = Date()
                }
            }
            reloadState()
        }
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
        if showsGif {
            editGifQuery { $0 += text }
            if shift == .once { setShift(.off) }
            return
        }
        proxy?.insertText(shift == .off ? text : text.uppercased())
        if shift == .once { setShift(.off) }
        autoCapitalize()
    }

    func backspace() {
        if showsGif {
            editGifQuery { if !$0.isEmpty { $0.removeLast() } }
            return
        }
        proxy?.deleteBackward()
        autoCapitalize()
    }

    func space() {
        if showsGif {
            editGifQuery { if !$0.isEmpty, $0.last != " " { $0 += " " } }
            return
        }
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
        if showsGif {
            searchGifs()
            return
        }
        proxy?.insertText("\n")
        autoCapitalize()
    }

    // MARK: GIF

    /// GIF — KLIPY search above the keys. Needs Full Access for the network and the pasteboard.
    func openGif() {
        guard hasFullAccess else {
            flash("GIF uchun Settings'da AI Keyboard → Allow Full Access'ni yoqing")
            return
        }
        keyDown()
        if showsEmoji { showsEmoji = false }
        if showsTargetPicker { showsTargetPicker = false }
        if showsDetails { showsDetails = false }
        closeVariantList()
        gifQuery = ""
        showsGif = true
        searchGifs()
    }

    func closeGif() {
        gifTask?.cancel()
        gifTask = nil
        if showsGif { showsGif = false }
        gifs = []
        gifStatus = nil
        if gifLoading { gifLoading = false }
    }

    /// Searches as the user types, a moment after the last key — one request per pause, not per letter.
    private func editGifQuery(_ change: (inout String) -> Void) {
        var query = gifQuery
        change(&query)
        guard query != gifQuery else { return }
        gifQuery = query
        searchGifs(after: .milliseconds(350))
    }

    private func searchGifs(after delay: Duration = .zero) {
        gifTask?.cancel()
        let query = gifQuery
        gifLoading = true
        gifTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            do {
                let found = try await Klipy.search(query, key: Secrets.klipyAPIKey)
                guard !Task.isCancelled, self.gifQuery == query else { return }
                gifs = found
                gifStatus = found.isEmpty ? "Hech narsa topilmadi" : nil
            } catch {
                guard !Task.isCancelled else { return }
                gifs = []
                gifStatus = error.localizedDescription
            }
            gifLoading = false
        }
    }

    /// Copies the GIF: iOS does not let a keyboard put an image into the host app's field, so the user pastes
    /// it — the same two steps as Gboard.
    func pick(_ gif: Gif) {
        keyDown()
        gifTask?.cancel()
        gifLoading = true
        gifTask = Task { [weak self] in
            do {
                let data = try await Klipy.download(gif.full)
                guard !Task.isCancelled, let self else { return }
                UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
                closeGif()
                flash("GIF nusxalandi — maydonni bosib turib «Paste» ni bosing", for: 6)
            } catch {
                guard !Task.isCancelled, let self else { return }
                gifLoading = false
                gifStatus = "GIF yuklanmadi: \(error.localizedDescription)"
            }
        }
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
        let original = currentText
        let draft = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            flash(context == nil
                ? "Avval o'zbekcha yozing, keyin ✨ ni bosing"
                : "Tayyor javoblardan birini tanlang yoki o'zbekcha yozib ✨ ni bosing")
            return
        }
        // A new ✨ starts plain; the tweaks belonged to the previous variants.
        if !tweaks.isEmpty { tweaks = [] }
        rewrite(original: original, replacingField: false)
    }

    /// qisqaroq / iliqroq / …: toggles the tweak and asks for the variants of the same draft again — the way the
    /// user would say "biroz qisqaroq" to a chat model. A variant already in the field is swapped for the new
    /// first one, so the request changes the text like it would in the chat.
    func refine(_ tweak: RewriteTweak) {
        guard let originalDraft else { return }
        keyDown()
        if let index = tweaks.firstIndex(of: tweak) { tweaks.remove(at: index) } else { tweaks.append(tweak) }
        rewrite(original: originalDraft, replacingField: pickedVariantID != nil)
    }

    private func rewrite(original: String, replacingField: Bool) {
        let draft = original.trimmingCharacters(in: .whitespacesAndNewlines)
        rewriteTask?.cancel()
        isRewriting = true
        let context = context
        let friend = state.activeFriendProfile
        let language = state.language
        let formality = state.chosenFormality
        let history = state.rememberedMessages
        let notes = state.activeFriendRecord?.notes
        let style = state.translationStyle
        let quality = state.quality
        let tweaks = tweaks
        let examples = state.rememberedExamples
        rewriteTask = Task {
            defer { isRewriting = false }
            do {
                let result = try await Signposts.measureAsync("rewrite") {
                    try await Translator.rewrite(
                        draft: draft, context: context, friend: friend, language: language,
                        formality: formality, history: history, notes: notes, style: style, tweaks: tweaks,
                        examples: examples, quality: quality)
                }
                guard !Task.isCancelled else { return }
                variants = result
                originalDraft = original
                if replacingField, let first = result.first {
                    pick(first)
                } else if pickedVariantID != nil {
                    pickedVariantID = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                flash(error.localizedDescription)
            }
        }
    }

    #if DEBUG
    /// The Simulator has no Full Access, so ✨ cannot run there; this shows the bar as it looks after one.
    func simulateVariants() {
        originalDraft = "salom, ertaga ko'rishamizmi? soat 7 da kafe oldida kutaman"
        variants = [
            Suggestion(text: "hey, are we meeting tomorrow? I'll wait for you in front of the cafe at 7", uz: "salom, ertaga ko'rishamizmi? soat 7 da kafe oldida kutaman"),
            Suggestion(text: "내일 볼까? 7시에 카페 앞에서 기다릴게", uz: "ertaga ko'rishamizmi? 7 da kafe oldida kutaman", read: "naeil bolkka? ilgopsie kape apeseo gidarilge"),
            Suggestion(text: "tomorrow? cafe, 7pm 😊", uz: "ertaga? kafe, kechki 7 😊"),
        ]
        pickedVariantID = nil
        tweaks = [.warmer]
    }
    #endif

    func pick(_ suggestion: Suggestion) {
        keyDown()
        replaceAllText(with: suggestion.text)
        // The screenshot replies always stayed on the row; now the ✨ variants do too.
        if !variants.isEmpty, pickedVariantID != suggestion.id { pickedVariantID = suggestion.id }
        lastSeenText = suggestion.text
        closeVariantList()
    }

    /// ↩︎ Asli — what the user had typed before ✨.
    func restoreOriginal() {
        guard let originalDraft else { return }
        keyDown()
        replaceAllText(with: originalDraft)
        if pickedVariantID != nil { pickedVariantID = nil }
        closeVariantList()
    }

    func dismissVariants() {
        clearVariants()
        closeVariantListIfEmpty()
    }

    /// The host app changed the text. A sent message empties the field: the variants were for that message, and
    /// what the user changed in the picked one before sending is worth remembering.
    func textChanged() {
        checkClipboard()
        guard !isReplacingText, !variants.isEmpty else { return }
        let text = currentText
        if !text.isEmpty {
            if pickedVariantID != nil { lastSeenText = text }
            return
        }
        learnFromSentMessage()
        clearVariants()
        closeVariantListIfEmpty()
    }

    private func learnFromSentMessage() {
        guard let pickedVariantID, let picked = variants.first(where: { $0.id == pickedVariantID }),
              let sent = lastSeenText, let originalDraft,
              let example = EditLearning.example(draft: originalDraft, picked: picked.text, sent: sent)
        else { return }
        SharedStore.update { $0.learn(example) }
        reloadState()
    }

    private func clearVariants() {
        if !variants.isEmpty { variants = [] }
        if originalDraft != nil { originalDraft = nil }
        if pickedVariantID != nil { pickedVariantID = nil }
        if !tweaks.isEmpty { tweaks = [] }
        lastSeenText = nil
    }

    func dismissContext() {
        SharedStore.update {
            $0.context = nil
            $0.contextDate = nil
        }
        clearVariants()
        closeVariantList()
        reloadState()
    }

    // MARK: Helpers

    private var currentText: String {
        (proxy?.documentContextBeforeInput ?? "") + (proxy?.documentContextAfterInput ?? "")
    }

    /// The DM field holds only the draft, so a picked reply replaces all of it.
    private func replaceAllText(with text: String) {
        guard let proxy else { return }
        isReplacingText = true
        defer { isReplacingText = false }
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

    private func flash(_ text: String, for seconds: Double = 4) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }
}
