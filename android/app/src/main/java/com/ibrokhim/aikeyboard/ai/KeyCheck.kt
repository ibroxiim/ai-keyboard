package com.ibrokhim.aikeyboard.ai

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/** One tiny request to see whether a Gemini key works (iOS `Gemini.check` + `APIKey.outcome`). */
object KeyCheck {
    private val schema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") { putJsonObject("ok") { put("type", "boolean") } }
    }

    sealed class Outcome {
        /** Google accepted the key. */
        data object Valid : Outcome()

        /** Google refused the key. It is not saved. */
        data class Rejected(val reason: String) : Outcome()

        /** Nothing certain (network, quota, server). The key is saved, and the user is told it was not verified. */
        data class Unverified(val reason: String) : Outcome()

        val shouldSave: Boolean get() = this !is Rejected
    }

    const val REJECTED = "Kalit noto'g'ri yoki faol emas"

    fun outcomeOf(error: Throwable?): Outcome = when (error) {
        null -> Outcome.Valid
        is GeminiException.Http -> if (error.code in listOf(400, 401, 403)) Outcome.Rejected(REJECTED) else Outcome.Unverified(error.message ?: "Tekshirib bo'lmadi")
        is GeminiException.MissingKey -> Outcome.Rejected("Kalit bo'sh")
        else -> Outcome.Unverified(error.message ?: "Tekshirib bo'lmadi")
    }

    suspend fun check(key: String): Outcome = try {
        GeminiClient(OkHttpGeminiTransport(), { key }).generate("Reply with {\"ok\": true}.", listOf(Part.Text("ping")), schema)
        Outcome.Valid
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        outcomeOf(e)
    }
}
