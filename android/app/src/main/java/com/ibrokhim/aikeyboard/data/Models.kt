package com.ibrokhim.aikeyboard.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Suggestion(
    val text: String,
    /** What `text` means in Uzbek, so the user knows exactly what they send. */
    val uz: String,
    /**
     * How `text` is read, in Latin letters, when its script is not one the user reads (Korean, Japanese,
     * Chinese, Arabic…); null for Latin and Cyrillic.
     */
    val read: String? = null,
)

@Serializable
data class ChatLine(
    /** "me" or "them". */
    val from: String,
    val text: String,
)

/** What the model read from a DM. Built from two parallel calls; either half may be missing. */
@Serializable
data class ChatAnalysis(
    val partner: String = "",
    val language: String = "",
    val tone: String = "",
    @SerialName("last_incoming_uz") val lastIncomingUz: String = "",
    @SerialName("summary_uz") val summaryUz: String = "",
    val transcript: List<ChatLine> = emptyList(),
    val suggestions: List<Suggestion> = emptyList(),
) {
    /** The trailing run of messages from "them" — the thing the user is replying to. */
    val lastIncoming: String
        get() = transcript.takeLastWhile { it.from == "them" }.joinToString(" ") { it.text }

    companion object {
        fun of(quick: QuickRead?, details: ChatDetails?) = ChatAnalysis(
            // Instagram truncates long names in the chat header ("Christi...") and the model copies that.
            partner = quick?.partner.orEmpty().trim(' ', '.', '…'),
            language = quick?.language.orEmpty(),
            tone = quick?.tone.orEmpty(),
            lastIncomingUz = quick?.lastIncomingUz.orEmpty(),
            summaryUz = details?.summaryUz.orEmpty(),
            transcript = details?.transcript.orEmpty(),
            suggestions = details?.suggestions.orEmpty(),
        )
    }
}

/** Small, fast half: who, which language, what the last message means. Shown first. */
@Serializable
data class QuickRead(
    val partner: String,
    val language: String,
    val tone: String,
    @SerialName("last_incoming_uz") val lastIncomingUz: String,
)

/** Slower half: reply suggestions and the transcript ✨ uses as context. */
@Serializable
data class ChatDetails(
    @SerialName("summary_uz") val summaryUz: String,
    val transcript: List<ChatLine>,
    val suggestions: List<Suggestion>,
)

/**
 * 📋 — a message the user copied in the DM app, translated without reading the screen: the text is exact and
 * one small request does the whole job. The quick and the detailed halves in one.
 */
@Serializable
data class ClipboardRead(
    val language: String,
    val tone: String,
    @SerialName("last_incoming_uz") val lastIncomingUz: String,
    @SerialName("summary_uz") val summaryUz: String,
    val suggestions: List<Suggestion>,
) {
    /** As the keyboard, the app and the friend memory already understand it. [partner] is the active friend, if any. */
    fun analysis(partner: String, text: String): ChatAnalysis {
        val lines = text.lines().map { it.trim() }.filter { it.isNotEmpty() }.map { ChatLine("them", it) }
        return ChatAnalysis(
            partner = partner, language = language, tone = tone, lastIncomingUz = lastIncomingUz,
            summaryUz = summaryUz, transcript = lines, suggestions = suggestions,
        )
    }
}

object ClipboardOffer {
    /** Longest copied text that is sent; a copied article is not a DM. */
    const val TEXT_LIMIT = 3000

    /** The copied text as it goes to the model, or null when there is nothing worth translating. */
    fun usable(text: CharSequence?): String? {
        val trimmed = text?.toString()?.trim().orEmpty()
        if (trimmed.length < 2) return null
        return trimmed.take(TEXT_LIMIT)
    }
}
