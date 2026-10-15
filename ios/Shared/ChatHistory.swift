import Foundation

/// A friend's chat as far as the screenshots have shown it. Each screenshot shows a screenful; consecutive ones
/// overlap, so the new screenful is joined to the saved history at the place they agree.
enum ChatHistory {
    /// Messages kept per friend, oldest dropped first.
    static let limit = 40

    typealias Line = ChatAnalysis.Line

    /// `old` (oldest first) extended with the screenful `new`.
    ///
    /// The overlap is searched from the newest end of `old`: a screenshot taken a moment after the last one
    /// repeats its last lines. A screenful that sits wholly inside `old` (scrolled up) adds nothing. Without any
    /// overlap `new` is taken to be the newer one — the usual case for a screenshot days later.
    static func merged(_ old: [Line], with new: [Line]) -> [Line] {
        guard !new.isEmpty else { return capped(old) }
        guard !old.isEmpty else { return capped(new) }

        for start in stride(from: old.count - 1, through: 0, by: -1) {
            let overlap = min(old.count - start, new.count)
            guard anchors(overlap, new), (0..<overlap).allSatisfy({ same(old[start + $0], new[$0]) }) else { continue }
            var result = Array(old[..<start])
            result += (0..<overlap).map { fuller(old[start + $0], new[$0]) }
            result += old[(start + overlap)...]
            result += new[overlap...]
            return capped(result)
        }
        return capped(old + new)
    }

    private static func capped(_ lines: [Line]) -> [Line] { Array(lines.suffix(limit)) }

    /// One short line ("ok", "lol") is in every chat, so it cannot tell where two screenshots meet.
    private static func anchors(_ overlap: Int, _ new: [Line]) -> Bool {
        overlap >= 2 || key(new[0].text).count >= minimumAnchor
    }

    private static let minimumAnchor = 8

    /// Same sender, and the same words up to letter case and punctuation. A bubble cut off by the top of the
    /// screen shows only the end of its text, so one that is the start or end of the other counts too.
    private static func same(_ a: Line, _ b: Line) -> Bool {
        guard a.from == b.from else { return false }
        let x = key(a.text), y = key(b.text)
        if x == y { return true }
        let (short, long) = x.count < y.count ? (x, y) : (y, x)
        return short.count >= minimumAnchor && (long.hasPrefix(short) || long.hasSuffix(short))
    }

    private static func fuller(_ a: Line, _ b: Line) -> Line {
        key(b.text).count > key(a.text).count ? b : a
    }

    /// Letters and digits, lower-cased; a message of only emoji or punctuation falls back to its own text.
    private static func key(_ text: String) -> String {
        let letters = String(String.UnicodeScalarView(
            text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
        return letters.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : letters
    }
}
