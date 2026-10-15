import Foundation

enum Languages {
    struct Entry: Equatable {
        let name: String
        let flag: String
    }

    /// What the keyboard's chip row offers until the user edits the list in the app. The first ten of `catalog`.
    static let defaults = [
        "English", "Korean", "Russian", "Turkish", "Japanese", "Chinese",
        "Arabic", "German", "Spanish", "French",
    ]

    /// What the app offers to add. Names are in English because they go to the model as the target language;
    /// anything else can still be typed in by hand.
    static let catalog: [Entry] = [
        Entry(name: "English", flag: "🇬🇧"), Entry(name: "Korean", flag: "🇰🇷"), Entry(name: "Russian", flag: "🇷🇺"),
        Entry(name: "Turkish", flag: "🇹🇷"), Entry(name: "Japanese", flag: "🇯🇵"), Entry(name: "Chinese", flag: "🇨🇳"),
        Entry(name: "Arabic", flag: "🇸🇦"), Entry(name: "German", flag: "🇩🇪"), Entry(name: "Spanish", flag: "🇪🇸"),
        Entry(name: "French", flag: "🇫🇷"), Entry(name: "Italian", flag: "🇮🇹"), Entry(name: "Portuguese", flag: "🇵🇹"),
        Entry(name: "Hindi", flag: "🇮🇳"), Entry(name: "Indonesian", flag: "🇮🇩"), Entry(name: "Kazakh", flag: "🇰🇿"),
        Entry(name: "Uzbek", flag: "🇺🇿"), Entry(name: "Kyrgyz", flag: "🇰🇬"), Entry(name: "Tajik", flag: "🇹🇯"),
        Entry(name: "Turkmen", flag: "🇹🇲"), Entry(name: "Azerbaijani", flag: "🇦🇿"), Entry(name: "Ukrainian", flag: "🇺🇦"),
        Entry(name: "Polish", flag: "🇵🇱"), Entry(name: "Dutch", flag: "🇳🇱"), Entry(name: "Swedish", flag: "🇸🇪"),
        Entry(name: "Czech", flag: "🇨🇿"), Entry(name: "Romanian", flag: "🇷🇴"), Entry(name: "Greek", flag: "🇬🇷"),
        Entry(name: "Hebrew", flag: "🇮🇱"), Entry(name: "Persian", flag: "🇮🇷"), Entry(name: "Urdu", flag: "🇵🇰"),
        Entry(name: "Bengali", flag: "🇧🇩"), Entry(name: "Thai", flag: "🇹🇭"), Entry(name: "Vietnamese", flag: "🇻🇳"),
        Entry(name: "Malay", flag: "🇲🇾"), Entry(name: "Filipino", flag: "🇵🇭"), Entry(name: "Georgian", flag: "🇬🇪"),
        Entry(name: "Armenian", flag: "🇦🇲"),
    ]

    private static let flags = Dictionary(uniqueKeysWithValues: catalog.map { ($0.name.lowercased(), $0.flag) })

    static func flag(_ language: String) -> String {
        flags[language.lowercased()] ?? "🌐"
    }

    /// A language as typed → how it is stored: "  korean " → "Korean", "old english" → "Old English". Nil when there
    /// is nothing usable to store. The rest of each word is left as typed ("Swiss GERMAN"): a name outside the
    /// catalog is not ours to fix.
    static func normalized(_ input: String) -> String? {
        let words = input.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        let text = words.joined(separator: " ")
        guard text.count <= 30 else { return nil }
        if let known = catalog.first(where: { $0.name.caseInsensitiveCompare(text) == .orderedSame }) {
            return known.name
        }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// `list` plus `input` at the end; unchanged when `input` is blank or already there (in any letter case).
    static func adding(_ input: String, to list: [String]) -> [String] {
        guard let language = normalized(input),
              !list.contains(where: { $0.caseInsensitiveCompare(language) == .orderedSame })
        else { return list }
        return list + [language]
    }

    /// Catalog entries not in `list` yet, in catalog order.
    static func addable(to list: [String]) -> [Entry] {
        catalog.filter { entry in !list.contains { $0.caseInsensitiveCompare(entry.name) == .orderedSame } }
    }
}
