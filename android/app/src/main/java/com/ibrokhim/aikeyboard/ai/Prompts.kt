package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.Friend
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/** Prompt texts and schemas from the iOS `Translator.swift`, plus a variant for chat text read on screen. */
object Prompts {
    val screenshotBasics = """
        You help an Uzbek speaker chat with foreign friends in social media DMs.
        You receive a phone screenshot of a DM conversation (Instagram, Telegram, WhatsApp, etc.).
        Messages on the RIGHT side (usually colored bubbles) are from the user ("me"); messages on the LEFT are from the other person ("them").
        Ignore the status bar, keyboard, app UI, and any system banners (e.g. a "Shortcuts" notification).
        Uzbek must use Latin script with ' for oʻ/gʻ.

        Return JSON:
    """.trimIndent()

    /** Android reads the chat's text instead of a screenshot; the lines carry their on-screen position. */
    val transcriptBasics = """
        You help an Uzbek speaker chat with foreign friends in social media DMs.
        You receive the visible text of a DM conversation screen (Instagram, Telegram, WhatsApp, etc.), one line per text element, top to bottom.
        Each line starts with a tag: [TOP] = the screen header (usually the other person's name or handle), [R] = right side, sent by the user ("me"), [L] = left side, sent by the other person ("them").
        The lines also contain timestamps, "Seen"/"Active now" statuses, reactions, buttons and other UI labels: ignore them.
        Uzbek must use Latin script with ' for oʻ/gʻ.

        Return JSON:
    """.trimIndent()

    private val quickFields = """
        - partner: the other person's visible name or handle, or "" if not visible. If it is cut off with "..." return only the visible part, without the dots. If "Known friends" are listed and this is clearly one of them (the same name, even if cut off or slightly misread), return that known name exactly as written.
        - language: the language the other person writes in, in English (e.g. "English", "Korean").
        - tone: 2-5 words describing the conversation register (e.g. "casual, slang, emojis").
        - last_incoming_uz: natural, conversational Uzbek meaning of the latest message(s) from "them". Translate intent, not words. If there is slang or an idiom, add a short explanation in parentheses.
    """.trimIndent()

    private val detailsFields = """
        - summary_uz: 1 short sentence in Uzbek explaining what is going on right now.
        - transcript: the last up to 6 messages in order, verbatim, each {from: "me"|"them", text}.
        - suggestions: exactly 3 replies the user could send next, written in the conversation language, matching the tone (length, casing, emoji use). Make them meaningfully different (e.g. positive / asks a question / polite decline or alternative). Each {text, uz} where uz is the Uzbek meaning.
    """.trimIndent()

    fun quick(basics: String) = basics + "\n" + quickFields

    fun details(basics: String) = basics + "\n" + detailsFields

    val rewriteSystem = """
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
    """.trimIndent()

    fun rewriteInput(draft: String, context: ChatAnalysis?, friend: Friend?, language: String): String {
        val lines = mutableListOf("Target language: $language")
        when {
            context != null -> {
                lines.add("Conversation tone: ${context.tone}")
                if (context.partner.isNotEmpty()) lines.add("Partner: ${context.partner}")
                lines.add("Recent messages:")
                context.transcript.forEach { lines.add("${it.from}: ${it.text}") }
            }
            friend != null -> {
                lines.add("Partner: ${friend.name}")
                lines.add("Conversation tone: ${friend.tone}")
                lines.add("No recent messages available.")
            }
            else -> lines.add("No conversation context. Write a friendly, casual DM.")
        }
        lines.addAll(listOf("", "Draft:", draft))
        return lines.joinToString("\n")
    }

    private val suggestionSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("text") { put("type", "string") }
            putJsonObject("uz") { put("type", "string") }
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
}
