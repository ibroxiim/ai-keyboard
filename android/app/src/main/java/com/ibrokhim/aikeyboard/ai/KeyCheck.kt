package com.ibrokhim.aikeyboard.ai

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/** One tiny request to see whether a Gemini key works. */
object KeyCheck {
    private val schema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") { putJsonObject("ok") { put("type", "boolean") } }
    }

    /** null when the key works, otherwise a short reason in Uzbek. */
    suspend fun check(key: String): String? = try {
        GeminiClient(OkHttpGeminiTransport(), { key }).generate("Reply with {\"ok\": true}.", listOf(Part.Text("ping")), schema)
        null
    } catch (e: CancellationException) {
        throw e
    } catch (e: GeminiException.Http) {
        if (e.code in listOf(400, 401, 403)) "Kalit noto'g'ri yoki faol emas" else e.message
    } catch (e: Exception) {
        e.message ?: "Tekshirib bo'lmadi"
    }
}
