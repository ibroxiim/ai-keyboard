import Foundation

/// The Diagnostika typing test: how the typed text differs from the phrase the user was asked to type.
/// Case and apostrophe style do not count — auto-capitalisation and the oʻ key are not missed taps.
struct PhraseDiff: Equatable {
    var missing = 0
    var extra = 0
    var substituted = 0
    /// The end of the phrase that was never typed: stopping early is not a missed tap.
    var unfinished = 0

    var isPerfect: Bool { missing == 0 && extra == 0 && substituted == 0 }

    /// Everyday Uzbek with punctuation, so the test also switches to the 123 layer and back.
    static let testPhrase = "Salom! Bugun ertalab bozorga bordim va olma, nok, uzum oldim. Kechqurun do'stlarim bilan choyxonada o'tirdik. Ertaga soat to'qqizda universitetga boraman, keyin ishga ketaman."

    /// Levenshtein alignment; the backtrace prefers matches, then missing, then extra characters.
    static func compare(expected: String, typed: String) -> PhraseDiff {
        let a = Array(normalize(expected)), b = Array(normalize(typed))
        var cost = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { cost[i][0] = i }
        for j in 0...b.count { cost[0][j] = j }
        if !a.isEmpty, !b.isEmpty {
            for i in 1...a.count {
                for j in 1...b.count {
                    cost[i][j] = min(
                        cost[i - 1][j] + 1,
                        cost[i][j - 1] + 1,
                        cost[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                }
            }
        }
        // Align with the best-matching start of the phrase; on a tie, the longer one.
        var end = 0
        for i in 0...a.count where cost[i][b.count] <= cost[end][b.count] { end = i }
        var diff = PhraseDiff(unfinished: a.count - end)
        var i = end, j = b.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, cost[i][j] == cost[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1) {
                if a[i - 1] != b[j - 1] { diff.substituted += 1 }
                i -= 1
                j -= 1
            } else if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                diff.missing += 1
                i -= 1
            } else {
                diff.extra += 1
                j -= 1
            }
        }
        return diff
    }

    static func normalize(_ text: String) -> String {
        let apostrophes: Set<Character> = ["ʻ", "ʼ", "’", "‘", "`"]
        return String(text.lowercased().map { apostrophes.contains($0) ? "'" : $0 })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
