import Foundation

/// 📋 — a message the user copied in the DM app, translated without a screenshot: the text is exact, there is no
/// OCR, and one small request does the whole job.
enum ClipboardOffer {
    /// Longest copied text that is sent; a copied article is not a DM.
    static let textLimit = 3000

    /// The copied text as it goes to the model, or nil when there is nothing worth translating.
    static func usable(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        return String(trimmed.prefix(textLimit))
    }
}

/// What the model returns for a copied message — the quick and the detailed halves of a screenshot in one.
struct ClipboardRead: Decodable {
    var language: String
    var tone: String
    var lastIncomingUz: String
    var summaryUz: String
    var suggestions: [Suggestion]

    enum CodingKeys: String, CodingKey {
        case language, tone, suggestions
        case lastIncomingUz = "last_incoming_uz"
        case summaryUz = "summary_uz"
    }

    /// As the keyboard, the app and the friend memory already understand it. `partner` is the active friend, if
    /// any: the clipboard does not say who wrote the text.
    func analysis(partner: String, text: String) -> ChatAnalysis {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { ChatAnalysis.Line(from: "them", text: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.text.isEmpty }
        return ChatAnalysis(
            quick: QuickRead(partner: partner, language: language, tone: tone, lastIncomingUz: lastIncomingUz),
            details: ChatDetails(summaryUz: summaryUz, transcript: lines, suggestions: suggestions))
    }
}

extension Prompts {
    static func clipboardSystem(style: String?) -> String {
        """
        You help an Uzbek speaker chat with foreign friends in social media DMs.
        You receive the text of a message (or a few messages) the user copied from the other person in a DM. Everything in it is from "them"; nothing in it is from the user.
        Uzbek must use Latin script with ' for oʻ/gʻ.
        If the user's notes about the friend are given, follow them: they say who that person is to the user and how to translate and reply for them.

        Return JSON:
        - language: the language the text is written in, in English (e.g. "English", "Korean").
        - tone: 2-5 words describing the register, including the speech level when the language has one (Korean 반말/존댓말, Russian ты/вы, Turkish sen/siz, Japanese casual/polite).
        - last_incoming_uz: the Uzbek translation of the whole text, one line per message or paragraph, in order, lines separated by a newline. Do not skip, merge or summarise anything.
          Write natural, fluent, spoken Uzbek, the way a bilingual friend would say it aloud, never a word-for-word machine translation.
          Stay faithful: keep every fact, number, name, question, the tone (teasing, flirty, sulky, excited) and the emoji. Do not add, soften or invent anything.
          If an expression has no good Uzbek equivalent, say its meaning in plain Uzbek instead of inventing slang. Add a short gloss in parentheses only for slang or an idiom that would otherwise be unclear.
        - summary_uz: 1 short sentence in Uzbek saying what they want or mean.
        - suggestions: exactly 3 replies the user could send next, written in the text's language, matching its tone (length, casing, emoji use). Make them meaningfully different (e.g. positive / asks a question / polite decline or alternative). Each {text, uz, read} where uz is the Uzbek meaning and read is a Latin romanization of text for the user to read it aloud, only when the language is not written in Latin or Cyrillic script (Revised Romanization for Korean, Hepburn for Japanese, Pinyin with tone marks for Chinese); leave read out otherwise.
        """ + styleBlock(style)
    }

    static let clipboardSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "language": ["type": "string"],
            "tone": ["type": "string"],
            "last_incoming_uz": ["type": "string"],
            "summary_uz": ["type": "string"],
            "suggestions": ["type": "array", "items": suggestionSchema],
        ],
        "required": ["language", "tone", "last_incoming_uz", "summary_uz", "suggestions"],
    ]
}
