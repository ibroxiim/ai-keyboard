import Foundation

enum Translator {
    /// Two parallel calls on the same screenshot: the short one (translation, ~2s) is handed to
    /// `onQuickRead` as soon as it lands, the longer one (suggestions + transcript, ~3s) completes the result.
    /// One slow call producing everything took ~3.3s before anything could be shown.
    /// Throws only if both fail; a failed half is returned as `partialError`.
    /// `knownFriends` lets the model map a cut-off or misread name ("Christi...", "Christima") onto the
    /// friend it already knows, so each screenshot does not create a new friend card.
    static func analyze(
        jpeg: Data, knownFriends: [String], onQuickRead: @escaping (QuickRead) -> Void
    ) async throws -> (analysis: ChatAnalysis, partialError: Error?) {
        let detailsTask = Task {
            try await Gemini.generate(
                ChatDetails.self, system: Prompts.detailsSystem, parts: [.jpeg(jpeg)], schema: Prompts.detailsSchema)
        }
        var quickParts: [Gemini.Part] = [.jpeg(jpeg)]
        if !knownFriends.isEmpty {
            quickParts.insert(.text("Known friends: " + knownFriends.joined(separator: ", ")), at: 0)
        }
        var quick: QuickRead?
        var quickError: Error?
        do {
            quick = try await Gemini.generate(
                QuickRead.self, system: Prompts.quickSystem, parts: quickParts, schema: Prompts.quickSchema)
            onQuickRead(quick!)
        } catch {
            quickError = error
        }
        var details: ChatDetails?
        var detailsError: Error?
        do {
            details = try await detailsTask.value
        } catch {
            detailsError = error
        }
        if quick == nil && details == nil { throw quickError ?? detailsError ?? GeminiError.empty }
        return (ChatAnalysis(quick: quick, details: details), quickError ?? detailsError)
    }

    static func rewrite(
        draft: String, context: ChatAnalysis?, friend: Friend?, language: String
    ) async throws -> [Suggestion] {
        let input = Prompts.rewriteInput(draft: draft, context: context, friend: friend, language: language)
        let result = try await Gemini.generate(
            RewriteResult.self, system: Prompts.rewriteSystem, parts: [.text(input)], schema: Prompts.rewriteSchema)
        return result.variants
    }

    private struct RewriteResult: Decodable {
        var variants: [Suggestion]
    }
}

enum Prompts {
    private static let screenshotBasics = """
    You help an Uzbek speaker chat with foreign friends in social media DMs.
    You receive a phone screenshot of a DM conversation (Instagram, Telegram, WhatsApp, etc.).
    Messages on the RIGHT side (usually colored bubbles) are from the user ("me"); messages on the LEFT are from the other person ("them").
    Ignore the status bar, keyboard, app UI, and any system banners (e.g. a "Shortcuts" notification).
    Uzbek must use Latin script with ' for oʻ/gʻ.

    Return JSON:
    """

    static let quickSystem = screenshotBasics + """
    - partner: the other person's visible name or handle, or "" if not visible. If it is cut off with "..." return only the visible part, without the dots. If "Known friends" are listed and this is clearly one of them (the same name, even if cut off or slightly misread), return that known name exactly as written.
    - language: the language the other person writes in, in English (e.g. "English", "Korean").
    - tone: 2-5 words describing the conversation register (e.g. "casual, slang, emojis").
    - last_incoming_uz: natural, conversational Uzbek meaning of the latest message(s) from "them". Translate intent, not words. If there is slang or an idiom, add a short explanation in parentheses.
    """

    static let detailsSystem = screenshotBasics + """
    - summary_uz: 1 short sentence in Uzbek explaining what is going on right now.
    - transcript: the last up to 6 messages in order, verbatim, each {from: "me"|"them", text}.
    - suggestions: exactly 3 replies the user could send next, written in the conversation language, matching the tone (length, casing, emoji use). Make them meaningfully different (e.g. positive / asks a question / polite decline or alternative). Each {text, uz} where uz is the Uzbek meaning.
    """

    static let rewriteSystem = """
    You turn an Uzbek speaker's draft into a DM reply they can send.
    The draft may be in Uzbek (Latin or Cyrillic), Russian, broken English, or a mix, and may contain typos.
    Write exactly 3 variants in the target language that sound like a native speaker texting a friend:
    1. closest to the draft's meaning,
    2. more natural / warmer,
    3. shorter.
    Keep the user's intent and facts. Never add plans, offers, promises, names or details that are not in the draft (for example do not add "on me" = offering to pay).
    Do not add greetings or sign-offs unless the draft has them.
    If conversation context is given, the reply must fit it (answer what was asked, keep references consistent) and match its tone: length, casing, slang, emoji use.
    For each variant also give uz: a faithful translation of that variant into natural Uzbek (Latin script), including anything it implies, so the user knows exactly what they are sending.
    """

    static func rewriteInput(draft: String, context: ChatAnalysis?, friend: Friend?, language: String) -> String {
        var lines = ["Target language: \(language)"]
        if let context {
            lines.append("Conversation tone: \(context.tone)")
            if !context.partner.isEmpty { lines.append("Partner: \(context.partner)") }
            lines.append("Recent messages:")
            lines += context.transcript.map { "\($0.from): \($0.text)" }
        } else if let friend {
            lines.append("Partner: \(friend.name)")
            lines.append("Conversation tone: \(friend.tone)")
            lines.append("No recent messages available.")
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
