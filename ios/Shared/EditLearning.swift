import Foundation

/// What the keyboard learns when the user changes a ✨ variant before sending it. The Gemini chat the user
/// compares us to got better over years of such corrections; here they are kept per friend and shown to the model.
enum EditLearning {
    /// Examples kept per friend, oldest dropped first.
    static let limit = 20
    /// Examples that go to the model with a rewrite.
    static let promptLimit = 10

    /// The example a sent message makes, or nil when there is nothing to learn from it: the user sent the variant
    /// as it was, or the host app only showed part of it (`documentContext` is cut around the cursor, so a prefix
    /// or a suffix of the variant is not an edit).
    static func example(draft: String, picked: String, sent: String) -> Friend.Example? {
        let sentText = sent.trimmingCharacters(in: .whitespacesAndNewlines)
        let pickedText = picked.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sentText.count >= 2, pickedText != sentText, !pickedText.hasPrefix(sentText),
              !pickedText.hasSuffix(sentText)
        else { return nil }
        return Friend.Example(draft: draft.trimmingCharacters(in: .whitespacesAndNewlines), suggested: pickedText, sent: sentText)
    }
}

extension Friend {
    /// One correction: what the user wrote in Uzbek, what ✨ offered, what they actually sent.
    struct Example: Codable, Hashable {
        var draft: String
        var suggested: String
        var sent: String
    }

    /// Keeps the newest `EditLearning.limit` examples, newest last.
    mutating func learn(_ example: Example) {
        var list = examples ?? []
        list.removeAll { $0 == example }
        list.append(example)
        examples = Array(list.suffix(EditLearning.limit))
    }
}
