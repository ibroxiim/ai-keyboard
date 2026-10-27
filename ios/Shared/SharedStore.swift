import Foundation

enum AppGroup {
    static let id = "group.com.ibrokhim.dmtranslator"
    /// Darwin notification: the app (Back Tap intent) changed the state, the keyboard should reload.
    static let stateChanged = "com.ibrokhim.dmtranslator.stateChanged"
    /// Darwin notification: the keyboard's ⏹ asks the app to stop recording and transcribe.
    static let voiceStopRequested = "com.ibrokhim.dmtranslator.voiceStopRequested"
    /// Darwin notification: the keyboard appended a diagnostics session to `diagnostics.json`.
    static let diagnosticsChanged = "com.ibrokhim.dmtranslator.diagnosticsChanged"
    /// Debug builds only: `tools/simulate-back-tap.sh` stands in for Back Tap in the Simulator.
    static let simulatedBackTap = "com.ibrokhim.dmtranslator.debug.simulatedBackTap"
}

/// Everything the app and the keyboard share. Lives in one JSON file in the App Group container.
struct SharedState: Codable, Equatable {
    var context: ChatAnalysis?
    var contextDate: Date?
    var analyzingSince: Date?
    var lastError: String?
    var lastErrorDate: Date?
    /// ✨ target when there is no fresh screenshot context. Follows the last analysed chat,
    /// and the keyboard's friend/language chips.
    var targetLanguage: String?
    /// Friend picked in the keyboard (or the last analysed one) — gives ✨ their tone without a screenshot.
    var activeFriend: String?
    /// People seen in screenshots, most recent first.
    var friends: [Friend]?
    // Setup checklist evidence — the app cannot query Settings or the Shortcuts library directly.
    var keyboardFullAccessDate: Date?
    var shortcutRunDate: Date?
    /// App setting: the bottom-row КИР/LAT key becomes an emoji key.
    var emojiKey: Bool?
    /// App setting (Diagnostika): the keyboard records a session summary per appearance.
    var diagnosticsEnabled: Bool?
    /// Voice dictation: written by the app as it records and transcribes, read by the keyboard.
    var voice: VoiceState?
    /// App setting: the languages in the keyboard's chip row, in order. Nil until edited — then `Languages.defaults`.
    var languages: [String]?
    /// App setting: the user's own instructions for how to translate, added to every translation prompt.
    var translationStyle: String?
    /// App setting: slower models with more thinking for translations (see `Gemini.Quality`). Off when nil.
    var qualityMode: Bool?
    /// App setting: keep what each friend wrote, from past screenshots, for ✨. On when nil.
    var rememberChats: Bool?
}

struct Friend: Codable, Hashable, Identifiable {
    /// How formal ✨ writes to this friend when the user decided it, instead of the model guessing from the chat.
    enum Formality: String, Codable, CaseIterable {
        case informal, formal
    }

    var name: String
    var language: String
    var tone: String
    var lastSeen: Date
    var formality: Formality?
    /// What was said in this chat, collected from screenshots (see `ChatHistory`); nil when the user turned chat
    /// memory off. Stays on the device; only ✨ sends it, and only for this friend.
    var history: [ChatAnalysis.Line]?
    /// What the user wrote about this person for the model: who they are, how to translate and reply for them.
    var notes: String?
    /// ✨ variants the user changed before sending, for the model to learn their taste (see `EditLearning`).
    var examples: [Example]?
    var id: String { name }

    /// The model reads the name off each screenshot, so the same person comes back as "Christi..."
    /// (Instagram truncates long names), "Christima" (misread), "christina 🌸" or "christina.lee".
    /// Compare letters and digits only; a name that is the start of the other is the same person,
    /// and from 6 letters on one misread, missing or extra letter is tolerated (not below: Maria ≠ Marta).
    static func isSamePerson(_ a: String, _ b: String) -> Bool {
        let x = key(a), y = key(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x == y { return true }
        let (short, long) = x.count < y.count ? (x, y) : (y, x)
        guard short.count >= 4 else { return false }
        if long.hasPrefix(short) { return true }
        return short.count >= 6 && prefixEditDistance(short, long) <= 1
    }

    /// Edit distance between `short` and the closest-length prefix of `long` (truncation is free).
    private static func prefixEditDistance(_ short: String, _ long: String) -> Int {
        let s = Array(short), l = Array(long)
        var row = Array(0...l.count)
        for i in 1...s.count {
            var next = [i] + Array(repeating: 0, count: l.count)
            for j in 1...l.count {
                next[j] = min(row[j] + 1, next[j - 1] + 1, row[j - 1] + (s[i - 1] == l[j - 1] ? 0 : 1))
            }
            row = next
        }
        let n = s.count
        return row[max(0, n - 1)...min(l.count, n + 1)].min() ?? Int.max
    }

    static func key(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    /// Of several spellings, keep the most complete one.
    static func bestName(_ names: [String]) -> String {
        names.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .…")) }
            .max { key($0).count < key($1).count } ?? ""
    }
}

enum SharedStore {
    /// Suggestions from an old screenshot are worse than none — the chat has moved on.
    static let contextLifetime: TimeInterval = 15 * 60
    static let analysisTimeout: TimeInterval = 60
    /// How long an analysis error stays in the keyboard's status line.
    static let errorLifetime: TimeInterval = 120

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
    }

    private static var fileURL: URL? { containerURL?.appendingPathComponent("state.json") }

    static func load() -> SharedState {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SharedState.self, from: data)
        else { return SharedState() }
        return state
    }

    static func update(_ change: (inout SharedState) -> Void) {
        var state = load()
        change(&state)
        guard let url = fileURL, let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
        DarwinNotification.post(AppGroup.stateChanged)
    }
}

extension SharedState {
    var freshContext: ChatAnalysis? { freshContext(at: Date()) }

    func freshContext(at now: Date) -> ChatAnalysis? {
        guard let context, let contextDate,
              now.timeIntervalSince(contextDate) < SharedStore.contextLifetime
        else { return nil }
        return context
    }

    var isAnalyzing: Bool { isAnalyzing(at: Date()) }

    func isAnalyzing(at now: Date) -> Bool {
        guard let analyzingSince else { return false }
        return now.timeIntervalSince(analyzingSince) < SharedStore.analysisTimeout
    }

    var recentError: String? { recentError(at: Date()) }

    func recentError(at now: Date) -> String? {
        guard let lastError, let lastErrorDate,
              now.timeIntervalSince(lastErrorDate) < SharedStore.errorLifetime
        else { return nil }
        return lastError
    }

    /// The next moment something time-based changes on screen: the analysis spinner times out, the error line
    /// expires or the context goes stale. Nothing else re-renders the keyboard then, so it wakes for this.
    func nextDeadline(after now: Date) -> Date? {
        [
            analyzingSince.map { $0 + SharedStore.analysisTimeout },
            lastErrorDate.map { $0 + SharedStore.errorLifetime },
            contextDate.map { $0 + SharedStore.contextLifetime },
            voice?.expiry,
        ]
        .compactMap { $0 }
        .filter { $0 > now }
        .min()
    }

    /// The voice session while it is still believed; a dead one (app killed mid-way) shows as none.
    func activeVoice(at now: Date) -> VoiceState? {
        guard let voice, voice.isLive(at: now) else { return nil }
        return voice
    }

    var language: String { freshContext?.language ?? targetLanguage ?? "English" }

    var languageList: [String] { languages ?? Languages.defaults }

    /// The friend whose tone ✨ uses when there is no fresh context.
    var activeFriendProfile: Friend? {
        guard freshContext == nil, let activeFriend else { return nil }
        return friends?.first { $0.name == activeFriend }
    }

    /// The friend ✨ is writing to — with or without a fresh screenshot (`activeFriendProfile` is only for the latter).
    var activeFriendRecord: Friend? {
        guard let activeFriend else { return nil }
        return friends?.first { $0.name == activeFriend }
    }

    /// The formality the user picked for that friend.
    var chosenFormality: Friend.Formality? { activeFriendRecord?.formality }

    /// What the active friend wrote and was written, for ✨; nothing while chat memory is off.
    var rememberedMessages: [ChatAnalysis.Line] {
        rememberChats == false ? [] : activeFriendRecord?.history ?? []
    }

    /// Turning memory off also forgets what was already saved.
    mutating func setRememberChats(_ on: Bool) {
        rememberChats = on
        guard !on, friends != nil else { return }
        for index in friends!.indices {
            friends![index].history = nil
            friends![index].examples = nil
        }
    }

    /// The correction goes to the friend ✨ was writing to; nothing is kept while chat memory is off.
    mutating func learn(_ example: Friend.Example) {
        guard rememberChats != false, let activeFriend,
              let index = friends?.firstIndex(where: { $0.name == activeFriend })
        else { return }
        friends?[index].learn(example)
    }

    /// The active friend's corrections, for ✨; nothing while chat memory is off.
    var rememberedExamples: [Friend.Example] {
        rememberChats == false ? [] : activeFriendRecord?.examples ?? []
    }

    mutating func remember(_ analysis: ChatAnalysis) {
        // Empty when the quick half failed — keep what we knew.
        guard !analysis.language.isEmpty else { return }
        targetLanguage = analysis.language
        guard !analysis.partner.isEmpty else {
            activeFriend = nil
            return
        }
        var list = friends ?? []
        let same = list.filter { Friend.isSamePerson($0.name, analysis.partner) }
        let name = Friend.bestName([analysis.partner] + same.map(\.name))
        list.removeAll { Friend.isSamePerson($0.name, analysis.partner) }
        let history = rememberChats == false
            ? nil : ChatHistory.merged(same.compactMap(\.history).first ?? [], with: analysis.transcript)
        list.insert(
            Friend(
                name: name, language: analysis.language, tone: analysis.tone, lastSeen: Date(),
                formality: same.compactMap(\.formality).first, history: history,
                notes: same.compactMap(\.notes).first,
                examples: rememberChats == false ? nil : same.compactMap(\.examples).first),
            at: 0)
        friends = Array(list.prefix(8))
        activeFriend = name
    }

    /// Merges entries that `Friend.isSamePerson` considers one person (e.g. saved by older builds). The list is
    /// most-recent-first, so the first entry keeps its language and tone; the name becomes the most complete one.
    mutating func mergeDuplicateFriends() {
        guard let list = friends else { return }
        var merged: [Friend] = []
        for friend in list {
            if let index = merged.firstIndex(where: { Friend.isSamePerson($0.name, friend.name) }) {
                merged[index].name = Friend.bestName([merged[index].name, friend.name])
                merged[index].formality = merged[index].formality ?? friend.formality
                merged[index].history = merged[index].history ?? friend.history
                merged[index].notes = merged[index].notes ?? friend.notes
                merged[index].examples = merged[index].examples ?? friend.examples
            } else {
                merged.append(friend)
            }
        }
        guard merged != list else { return }
        friends = merged
        if let active = activeFriend, let match = merged.first(where: { Friend.isSamePerson($0.name, active) }) {
            activeFriend = match.name
        }
    }
}

enum DarwinNotification {
    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }
}

/// Cross-process observer (app → keyboard). Keep a strong reference for as long as it should fire.
final class DarwinObserver {
    private let name: String
    private let handler: @MainActor () -> Void

    init(name: String, handler: @escaping @MainActor () -> Void) {
        self.name = name
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { me.handler() } }
            },
            name as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString), nil)
    }
}
