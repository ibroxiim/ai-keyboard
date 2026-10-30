package com.ibrokhim.aikeyboard.ai

import kotlinx.serialization.json.JsonObject

sealed interface Part {
    data class Text(val text: String) : Part
    class Jpeg(val bytes: ByteArray) : Part
}

/**
 * How a request trades time for care. [FAST] is for the keyboard's everyday use; [CAREFUL] is the app's
 * "Sifatli tarjima" setting, for translations only.
 */
enum class GeminiQuality {
    FAST, CAREFUL;

    /**
     * Raced in this order. Which one is up changes day to day; all of them take `thinkingLevel` minimal and low
     * (3.7/3.8-flash do not).
     */
    val models: List<String>
        get() = when (this) {
            FAST -> listOf("gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.1-flash-lite", "gemini-3.5-flash")
            CAREFUL -> listOf("gemini-3.6-flash", "gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite")
        }

    /** On Flash-Lite `low` did not read better than `minimal` (it made up slang), so it is only for [CAREFUL]. */
    val thinkingLevel: String get() = if (this == CAREFUL) "low" else "minimal"

    /** Multiplies the client's hedge delay and attempt timeout. */
    val patience: Double get() = if (this == CAREFUL) 2.0 else 1.0
}

/** Turns a system prompt, the user's parts and a JSON schema into the model's JSON text. */
interface LlmClient {
    suspend fun generate(
        system: String,
        parts: List<Part>,
        schema: JsonObject,
        quality: GeminiQuality = GeminiQuality.FAST,
    ): String
}

/** Like runCatching, but cancellation still propagates. */
internal inline fun <T> runCatchingNonCancel(block: () -> T): Result<T> = try {
    Result.success(block())
} catch (e: kotlinx.coroutines.CancellationException) {
    throw e
} catch (e: Exception) {
    Result.failure(e)
}

/** The user's "Sifatli tarjima" setting. */
val com.ibrokhim.aikeyboard.data.SharedState.quality: GeminiQuality
    get() = if (qualityMode) GeminiQuality.CAREFUL else GeminiQuality.FAST
