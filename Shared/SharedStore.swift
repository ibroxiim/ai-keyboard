import Foundation

enum AppGroup {
    static let id = "group.com.ibrokhim.dmtranslator"
    /// Darwin notification: the app (Back Tap intent) changed the state, the keyboard should reload.
    static let stateChanged = "com.ibrokhim.dmtranslator.stateChanged"
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
}

struct Friend: Codable, Hashable, Identifiable {
    var name: String
    var language: String
    var tone: String
    var lastSeen: Date
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

    var isAnalyzing: Bool {
        guard let analyzingSince else { return false }
        return Date().timeIntervalSince(analyzingSince) < SharedStore.analysisTimeout
    }

    var recentError: String? {
        guard let lastError, let lastErrorDate, Date().timeIntervalSince(lastErrorDate) < 120 else { return nil }
        return lastError
    }

    var language: String { freshContext?.language ?? targetLanguage ?? "English" }

    /// The friend whose tone ✨ uses when there is no fresh context.
    var activeFriendProfile: Friend? {
        guard freshContext == nil, let activeFriend else { return nil }
        return friends?.first { $0.name == activeFriend }
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
        list.insert(Friend(name: name, language: analysis.language, tone: analysis.tone, lastSeen: Date()), at: 0)
        friends = Array(list.prefix(8))
        activeFriend = name
    }

    /// Merges duplicates saved before `Friend.isSamePerson` existed. The list is most-recent-first,
    /// so the first entry of each person keeps its language and tone; the name becomes the most complete one.
    mutating func mergeDuplicateFriends() {
        guard let list = friends else { return }
        var merged: [Friend] = []
        for friend in list {
            if let index = merged.firstIndex(where: { Friend.isSamePerson($0.name, friend.name) }) {
                merged[index].name = Friend.bestName([merged[index].name, friend.name])
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

enum Languages {
    static let common = [
        "English", "Korean", "Russian", "Turkish", "Japanese", "Chinese",
        "Arabic", "German", "Spanish", "French",
    ]

    static func flag(_ language: String) -> String {
        switch language.lowercased() {
        case "english": "🇬🇧"
        case "korean": "🇰🇷"
        case "russian": "🇷🇺"
        case "turkish": "🇹🇷"
        case "japanese": "🇯🇵"
        case "chinese": "🇨🇳"
        case "arabic": "🇸🇦"
        case "german": "🇩🇪"
        case "spanish": "🇪🇸"
        case "french": "🇫🇷"
        case "italian": "🇮🇹"
        case "portuguese": "🇵🇹"
        case "hindi": "🇮🇳"
        case "indonesian": "🇮🇩"
        case "kazakh": "🇰🇿"
        case "uzbek": "🇺🇿"
        default: "🌐"
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
