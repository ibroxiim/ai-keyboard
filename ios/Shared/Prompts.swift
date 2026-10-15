import Foundation

enum Prompts {
    /// Longest "Tarjima uslubi" the user can add to a prompt.
    static let styleLimit = 500

    /// The user's own translation instructions (app setting), as a block to append to a prompt. Empty when unset.
    static func styleBlock(_ style: String?) -> String {
        let text = (style ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        return "\nThe user's own instructions for how to translate (follow them unless they contradict the rules above):\n"
            + String(text.prefix(styleLimit))
    }

    private static let screenshotBasics = """
    You help an Uzbek speaker chat with foreign friends in social media DMs.
    You receive a phone screenshot of a DM conversation (Instagram, Telegram, WhatsApp, etc.).
    Messages on the RIGHT side (usually colored bubbles) are from the user ("me"); messages on the LEFT are from the other person ("them").
    Ignore the status bar, keyboard, app UI, and any system banners (e.g. a "Shortcuts" notification).
    Uzbek must use Latin script with ' for oʻ/gʻ.

    Return JSON:
    """

    static func quickSystem(style: String?) -> String {
        screenshotBasics + """
        - partner: the other person's visible name or handle, or "" if not visible. If it is cut off with "..." return only the visible part, without the dots. If "Known friends" are listed and this is clearly one of them (the same name, even if cut off or slightly misread), return that known name exactly as written.
        - language: the language the other person writes in, in English (e.g. "English", "Korean").
        - tone: 2-5 words describing the conversation register, including the speech level when the language has one (Korean 반말/존댓말, Russian ты/вы, Turkish sen/siz, Japanese casual/polite), e.g. "casual, slang, emojis, 반말".
        - last_incoming_uz: the Uzbek translation of EVERY message from "them" after the last message from "me" (the whole unanswered run at the bottom of the chat), in order, one line per message, lines separated by a newline. Do not skip, merge or summarise any of them. If "me" has not written anything on the screen, take the last up to 6 messages from "them".
          Write natural, fluent, spoken Uzbek, the way a bilingual friend would say it aloud, never a word-for-word machine translation.
          Stay faithful: keep every fact, number, name, question, the tone (teasing, flirty, sulky, excited) and the emoji. Do not add, soften or invent anything.
          If an expression has no good Uzbek equivalent, say its meaning in plain Uzbek instead of inventing slang. Add a short gloss in parentheses only for slang or an idiom that would otherwise be unclear.
          Use the earlier messages on the screen to resolve what "it", "that" or a short reply refers to.
        """ + styleBlock(style)
    }

    static let detailsSystem = screenshotBasics + """
    - summary_uz: 1 short sentence in Uzbek explaining what is going on right now.
    - transcript: the last up to 12 messages in order, verbatim, each {from: "me"|"them", text}.
    - suggestions: exactly 3 replies the user could send next, written in the conversation language, matching the tone (length, casing, emoji use). Make them meaningfully different (e.g. positive / asks a question / polite decline or alternative). Each {text, uz} where uz is the Uzbek meaning.
    """

    static let transcribeSystem = """
    You transcribe a short voice message from an Uzbek speaker who is chatting with a friend.
    Write exactly what was said, in Uzbek Latin script (use ' for oʻ/gʻ), with natural punctuation.
    Keep words in other languages (English, Russian) as spoken. Do not translate, summarize, correct or add anything.
    If there is no speech, return an empty string.

    Return JSON:
    - text: the transcript.
    """

    static let transcribeSchema: [String: Any] = [
        "type": "object",
        "properties": ["text": ["type": "string"]],
        "required": ["text"],
    ]

    static func rewriteSystem(style: String?) -> String {
        """
        You turn an Uzbek speaker's draft into a DM reply they can send.
        The draft may be in Uzbek (Latin or Cyrillic), Russian, broken English, or a mix, and may contain typos.
        Write exactly 3 variants in the target language that sound like a native speaker texting a friend:
        1. closest to the draft's meaning,
        2. more natural / warmer,
        3. shorter.
        Keep the user's intent and facts. Never add plans, offers, promises, names or details that are not in the draft (for example do not add "on me" = offering to pay).
        Do not add greetings or sign-offs unless the draft has them.
        If conversation context is given, the reply must fit it (answer what was asked, keep references consistent) and match its tone: length, casing, slang, emoji use.
        Match the speech level of the conversation. If the target language has politeness levels (Korean 반말/존댓말, Japanese, Russian ты/вы, Turkish sen/siz), use the level the recent messages use, informal with a friend by default; never fall back to the most formal level just because it is the textbook one. If the user chose a formality, always follow it.
        For each variant also give uz: a faithful translation of that variant into natural Uzbek (Latin script), including anything it implies, so the user knows exactly what they are sending.
        """ + styleBlock(style)
    }

    /// Messages of the remembered chat that go to the model with a rewrite.
    static let historyLimit = 20

    static func rewriteInput(
        draft: String, context: ChatAnalysis?, friend: Friend?, language: String, formality: Friend.Formality?,
        history: [ChatAnalysis.Line] = []
    ) -> String {
        var lines = ["Target language: \(language)"]
        if let formality { lines.append("Formality chosen by the user: \(formality.rawValue)") }
        let remembered = history.suffix(historyLimit).map { "\($0.from): \($0.text)" }
        if let context {
            lines.append("Conversation tone: \(context.tone)")
            if !context.partner.isEmpty { lines.append("Partner: \(context.partner)") }
            lines.append("Recent messages:")
            // The remembered chat already contains this screenshot and what came before it.
            lines += history.count > context.transcript.count
                ? remembered : context.transcript.map { "\($0.from): \($0.text)" }
        } else if let friend {
            lines.append("Partner: \(friend.name)")
            lines.append("Conversation tone: \(friend.tone)")
            if remembered.isEmpty {
                lines.append("No recent messages available.")
            } else {
                lines.append("Earlier messages, from past screenshots (the chat may have moved on since):")
                lines += remembered
            }
        } else {
            lines.append("No conversation context. Write a friendly, casual DM.")
        }
        lines += ["", "Draft:", draft]
        return lines.joined(separator: "\n")
    }

    private static let suggestionSchema: [String: Any] = [
        "type": "object",
        "properties": ["text": ["type": "string"], "uz": ["type": "string"]],
        "required": ["text", "uz"],
    ]

    static let quickSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "partner": ["type": "string"],
            "language": ["type": "string"],
            "tone": ["type": "string"],
            "last_incoming_uz": ["type": "string"],
        ],
        "required": ["partner", "language", "tone", "last_incoming_uz"],
    ]

    static let detailsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary_uz": ["type": "string"],
            "transcript": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "from": ["type": "string", "enum": ["me", "them"]],
                        "text": ["type": "string"],
                    ],
                    "required": ["from", "text"],
                ],
            ],
            "suggestions": ["type": "array", "items": suggestionSchema],
        ],
        "required": ["summary_uz", "transcript", "suggestions"],
    ]

    static let rewriteSchema: [String: Any] = [
        "type": "object",
        "properties": ["variants": ["type": "array", "items": suggestionSchema]],
        "required": ["variants"],
    ]
}
