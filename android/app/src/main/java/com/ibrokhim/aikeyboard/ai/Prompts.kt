package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.ChatLine
import com.ibrokhim.aikeyboard.data.EditLearning
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.RewriteTweak
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/** Prompt texts and schemas, kept in step with the iOS `Prompts.swift`, plus a variant for chat text read on screen. */
object Prompts {
    /**
     * Longest text the user can put into a prompt: "Tarjima uslubi" and each friend's notes separately (~3000
     * tokens — room for rules plus 15–20 examples). Every request carries them, so this is a brake on pasting a
     * whole chat export.
     */
    const val STYLE_LIMIT = 12000

    /**
     * How much of all friends' notes together a chat read may carry. The list is most-recent-first, so the friends
     * the user actually talks to keep their notes when the budget runs out.
     */
    const val FRIEND_NOTES_BUDGET = 24000

    /** Messages of the remembered chat that go to the model with a rewrite. */
    const val HISTORY_LIMIT = 20

    /** Trimmed and cut at [STYLE_LIMIT]; null when there is nothing in it. */
    fun capped(text: String?): String? = text?.trim()?.takeIf { it.isNotEmpty() }?.take(STYLE_LIMIT)

    /** The user's own translation instructions (app setting), as a block to append to a prompt. Empty when unset. */
    fun styleBlock(style: String?): String {
        val text = capped(style) ?: return ""
        return "\nThe user's own instructions for how to translate (follow them unless they contradict the rules above):\n$text"
    }

    /**
     * Goes with a chat read: who the model may recognise, and what the user said about each of them. The partner
     * is only identified inside this same request, so every friend's notes are sent and the model applies the ones
     * for the person it finds.
     */
    fun knownFriendsPart(friends: List<Friend>): String? {
        if (friends.isEmpty()) return null
        val text = StringBuilder("Known friends: " + friends.joinToString(", ") { it.name })
        var budget = FRIEND_NOTES_BUDGET
        for (friend in friends) {
            if (budget <= 0) break
            val notes = capped(friend.notes) ?: continue
            val part = notes.take(budget)
            budget -= part.length
            text.append("\n\nThe user's notes about ${friend.name} (follow them when the partner is ${friend.name}):\n").append(part)
        }
        return text.toString()
    }

    private const val NOTES_RULE =
        "If the message includes the user's notes about known friends, apply the notes about the person you identify as the partner: they say who that person is to the user and how to translate and reply for them."

    val screenshotBasics = """
        You help an Uzbek speaker chat with foreign friends in social media DMs.
        You receive a phone screenshot of a DM conversation (Instagram, Telegram, WhatsApp, etc.).
        Messages on the RIGHT side (usually colored bubbles) are from the user ("me"); messages on the LEFT are from the other person ("them").
        Ignore the status bar, keyboard, app UI, and any system banners (e.g. a "Shortcuts" notification).
        Uzbek must use Latin script with ' for oʻ/gʻ.
        $NOTES_RULE

        Return JSON:
    """.trimIndent()

    /** Android reads the chat's text instead of a screenshot; the lines carry their on-screen position. */
    val transcriptBasics = """
        You help an Uzbek speaker chat with foreign friends in social media DMs.
        You receive the visible text of a DM conversation screen (Instagram, Telegram, WhatsApp, etc.), one line per text element, top to bottom.
        Each line starts with a tag: [TOP] = the screen header (usually the other person's name or handle), [R] = right side, sent by the user ("me"), [L] = left side, sent by the other person ("them").
        The lines also contain timestamps, "Seen"/"Active now" statuses, reactions, buttons and other UI labels: ignore them.
        Uzbek must use Latin script with ' for oʻ/gʻ.
        $NOTES_RULE

        Return JSON:
    """.trimIndent()

    private const val TRANSLATION_RULES = """  Write natural, fluent, spoken Uzbek, the way a bilingual friend would say it aloud, never a word-for-word machine translation.
  Stay faithful: keep every fact, number, name, question, the tone (teasing, flirty, sulky, excited) and the emoji. Do not add, soften or invent anything.
  If an expression has no good Uzbek equivalent, say its meaning in plain Uzbek instead of inventing slang. Add a short gloss in parentheses only for slang or an idiom that would otherwise be unclear."""

    private const val READ_RULE =
        "Each {text, uz, read} where uz is the Uzbek meaning and read is a Latin romanization of text for the user to read it aloud, only when the language is not written in Latin or Cyrillic script (Revised Romanization for Korean, Hepburn for Japanese, Pinyin with tone marks for Chinese); leave read out otherwise."

    private val quickFields = """
        - partner: the other person's visible name or handle, or "" if not visible. If it is cut off with "..." return only the visible part, without the dots. If "Known friends" are listed and this is clearly one of them (the same name, even if cut off or slightly misread), return that known name exactly as written.
        - language: the language the other person writes in, in English (e.g. "English", "Korean").
        - tone: 2-5 words describing the conversation register, including the speech level when the language has one (Korean 반말/존댓말, Russian ты/вы, Turkish sen/siz, Japanese casual/polite), e.g. "casual, slang, emojis, 반말".
        - last_incoming_uz: the Uzbek translation of EVERY message from "them" after the last message from "me" (the whole unanswered run at the bottom of the chat), in order, one line per message, lines separated by a newline. Do not skip, merge or summarise any of them. If "me" has not written anything on the screen, take the last up to 6 messages from "them".
        $TRANSLATION_RULES
          Use the earlier messages on the screen to resolve what "it", "that" or a short reply refers to.
    """.trimIndent()

    private val detailsFields = """
        - summary_uz: 1 short sentence in Uzbek explaining what is going on right now.
        - transcript: the last up to 12 messages in order, verbatim, each {from: "me"|"them", text}.
        - suggestions: exactly 3 replies the user could send next, written in the conversation language, matching the tone (length, casing, emoji use). Make them meaningfully different (e.g. positive / asks a question / polite decline or alternative). $READ_RULE
    """.trimIndent()

    fun quick(basics: String, style: String? = null) = basics + "\n" + quickFields + styleBlock(style)

    fun details(basics: String) = basics + "\n" + detailsFields

    fun rewriteSystem(style: String? = null) = """
        You turn an Uzbek speaker's draft into a DM reply they can send.
        The draft may be in Uzbek (Latin or Cyrillic), Russian, broken English, or a mix, and may contain typos.
        Write exactly 3 variants in the target language that sound like a native speaker texting a friend:
        1. closest to the draft's meaning,
        2. more natural / warmer,
        3. shorter.
        Keep the user's intent and facts. Never add plans, offers, promises, names or details that are not in the draft (for example do not add "on me" = offering to pay).
        Do not add greetings or sign-offs unless the draft has them.
        If conversation context is given, the reply must fit it (answer what was asked, keep references consistent) and match its tone: length, casing, slang, emoji use.
        If an "Adjust" line is given, apply it to all three variants on top of everything above (e.g. "shorter" makes all three shorter, variant 3 shortest).
        If "How the user changed earlier suggestions" are given, learn from them: they show the wording, warmth and length the user actually sends to this friend. Prefer that style over the generic one.
        Match the speech level of the conversation. If the target language has politeness levels (Korean 반말/존댓말, Japanese, Russian ты/вы, Turkish sen/siz), use the level the recent messages use, informal with a friend by default; never fall back to the most formal level just because it is the textbook one. If the user chose a formality, always follow it.
        For each variant also give uz: a faithful translation of that variant into natural Uzbek (Latin script), including anything it implies, so the user knows exactly what they are sending.
        Also give read: a Latin romanization of the variant for the user to read it aloud, only when the target language is not written in Latin or Cyrillic script (Revised Romanization for Korean, Hepburn for Japanese, Pinyin with tone marks for Chinese); leave it out otherwise.
    """.trimIndent() + styleBlock(style)

    fun rewriteInput(
        draft: String,
        context: ChatAnalysis?,
        friend: Friend?,
        language: String,
        formality: Friend.Formality? = null,
        history: List<ChatLine> = emptyList(),
        notes: String? = null,
        tweaks: List<RewriteTweak> = emptyList(),
        examples: List<Friend.Example> = emptyList(),
    ): String {
        val lines = mutableListOf("Target language: $language")
        if (formality != null) lines.add("Formality chosen by the user: ${formality.word}")
        if (tweaks.isNotEmpty()) lines.add("Adjust: " + tweaks.joinToString("; ") { it.instruction })
        capped(notes)?.let {
            lines.add("The user's notes about this friend (follow them):")
            lines.add(it)
        }
        if (examples.isNotEmpty()) {
            lines.add("How the user changed earlier suggestions for this friend (draft → suggested → what they sent):")
            for (example in examples.takeLast(EditLearning.PROMPT_LIMIT)) {
                lines.add("- draft: ${example.draft}")
                lines.add("  suggested: ${example.suggested}")
                lines.add("  sent: ${example.sent}")
            }
        }
        val remembered = history.takeLast(HISTORY_LIMIT).map { "${it.from}: ${it.text}" }
        when {
            context != null -> {
                lines.add("Conversation tone: ${context.tone}")
                if (context.partner.isNotEmpty()) lines.add("Partner: ${context.partner}")
                lines.add("Recent messages:")
                // The remembered chat already contains this read and what came before it.
                if (history.size > context.transcript.size) lines.addAll(remembered)
                else context.transcript.forEach { lines.add("${it.from}: ${it.text}") }
            }
            friend != null -> {
                lines.add("Partner: ${friend.name}")
                lines.add("Conversation tone: ${friend.tone}")
                if (remembered.isEmpty()) {
                    lines.add("No recent messages available.")
                } else {
                    lines.add("Earlier messages, from past chat reads (the chat may have moved on since):")
                    lines.addAll(remembered)
                }
            }
            else -> lines.add("No conversation context. Write a friendly, casual DM.")
        }
        lines.addAll(listOf("", "Draft:", draft))
        return lines.joinToString("\n")
    }

    fun clipboardSystem(style: String? = null) = """
        You help an Uzbek speaker chat with foreign friends in social media DMs.
        You receive the text of a message (or a few messages) the user copied from the other person in a DM. Everything in it is from "them"; nothing in it is from the user.
        Uzbek must use Latin script with ' for oʻ/gʻ.
        If the user's notes about the friend are given, follow them: they say who that person is to the user and how to translate and reply for them.

        Return JSON:
        - language: the language the text is written in, in English (e.g. "English", "Korean").
        - tone: 2-5 words describing the register, including the speech level when the language has one (Korean 반말/존댓말, Russian ты/вы, Turkish sen/siz, Japanese casual/polite).
        - last_incoming_uz: the Uzbek translation of the whole text, one line per message or paragraph, in order, lines separated by a newline. Do not skip, merge or summarise anything.
        $TRANSLATION_RULES
        - summary_uz: 1 short sentence in Uzbek saying what they want or mean.
        - suggestions: exactly 3 replies the user could send next, written in the text's language, matching its tone (length, casing, emoji use). Make them meaningfully different (e.g. positive / asks a question / polite decline or alternative). $READ_RULE
    """.trimIndent() + styleBlock(style)

    val suggestionSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("text") { put("type", "string") }
            putJsonObject("uz") { put("type", "string") }
            putJsonObject("read") { put("type", "string") }
        }
        putJsonArray("required") { add("text"); add("uz") }
    }

    val quickSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            for (field in listOf("partner", "language", "tone", "last_incoming_uz")) {
                putJsonObject(field) { put("type", "string") }
            }
        }
        putJsonArray("required") { add("partner"); add("language"); add("tone"); add("last_incoming_uz") }
    }

    val detailsSchema: JsonObject = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("summary_uz") { put("type", "string") }
            putJsonObject("transcript") {
                put("type", "array")
                putJsonObject("items") {
                    put("type", "object")
                    putJsonObject("properties") {
                        putJsonObject("from") {
                            put("type", "string")
                            putJsonArray("enum") { add("me"); add("them") }
                        }
                        putJsonObject("text") { put("type", "string") }
                    }
                    putJsonArray("required") { add("from"); add("text") }
                }
            }
            putJsonObject("suggestions") {
                put("type", "array")
                put("items", suggestionSchema)
            }
        }
        putJsonArray("required") { add("summary_uz"); add("transcript"); add("suggestions") }
    }

    val rewriteSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("variants") {
                put("type", "array")
                put("items", suggestionSchema)
            }
        }
        putJsonArray("required") { add("variants") }
    }

    val clipboardSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            for (field in listOf("language", "tone", "last_incoming_uz", "summary_uz")) {
                putJsonObject(field) { put("type", "string") }
            }
            putJsonObject("suggestions") {
                put("type", "array")
                put("items", suggestionSchema)
            }
        }
        putJsonArray("required") { add("language"); add("tone"); add("last_incoming_uz"); add("summary_uz"); add("suggestions") }
    }
}
