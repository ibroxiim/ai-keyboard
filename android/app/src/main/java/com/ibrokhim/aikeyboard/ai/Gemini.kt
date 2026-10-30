package com.ibrokhim.aikeyboard.ai

import java.io.IOException
import java.util.Base64
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

sealed class GeminiException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class MissingKey : GeminiException("Gemini API kaliti kiritilmagan — AI Keyboard ilovasini oching")
    class Http(val code: Int, detail: String) : GeminiException("Gemini $code: $detail")
    class Empty : GeminiException("Gemini bo'sh javob qaytardi")
    class Timeout : GeminiException("Gemini javob bermadi")
    class Network(cause: IOException) : GeminiException("Internet bilan muammo", cause)

    /** Worth asking the other model: overload, server trouble, silence, a dropped connection. */
    val retriable: Boolean
        get() = when (this) {
            is Http -> code == 429 || code >= 500
            is Empty, is Timeout, is Network -> true
            is MissingKey -> false
        }
}

data class HttpResponse(val code: Int, val body: String)

interface GeminiTransport {
    /** POSTs `body` to the model's generateContent endpoint; throws IOException on network failure. */
    suspend fun post(model: String, apiKey: String, body: String): HttpResponse
}

/**
 * Gemini with a hedge: the first model answers in ~2 s but now and then takes 20–50 s, so if it has not answered
 * after the hedge delay the next model is asked in parallel, and so on down the chain; the first answer wins and
 * the rest are cancelled. A failure worth retrying starts the next model at once. Which model is fast or down
 * changes day to day, so the chain is four long (see [GeminiQuality.models]).
 */
class GeminiClient(
    private val transport: GeminiTransport,
    private val apiKey: () -> String,
    private val models: List<String>? = null,
    private val hedgeAfterMs: Long = 5_000,
    private val attemptTimeoutMs: Long = 30_000,
) : LlmClient {

    override suspend fun generate(system: String, parts: List<Part>, schema: JsonObject, quality: GeminiQuality): String {
        val key = apiKey()
        if (key.isBlank()) throw GeminiException.MissingKey()
        val body = requestBody(system, parts, schema, quality.thinkingLevel)
        val chain = models ?: quality.models
        // A screenshot takes longer to read than a rewrite, so it gets more time before paying for a second request.
        val media = parts.any { it is Part.Jpeg }
        val hedgeMs = (hedgeAfterMs * (if (media) 1.5 else 1.0) * quality.patience).toLong()
        val timeoutMs = (attemptTimeoutMs * quality.patience).toLong()
        return coroutineScope {
            val running = mutableListOf<Deferred<Result<String>>>()
            var next = 0
            fun launchNext(): Boolean {
                if (next >= chain.size) return false
                running += async { attempt(chain[next++], key, body, timeoutMs) }
                return true
            }
            launchNext()
            var timer: Deferred<Unit>? = async { delay(hedgeMs) }
            while (true) {
                val finished = select<Pair<Deferred<Result<String>>, Result<String>>?> {
                    running.forEach { job -> job.onAwait { job to it } }
                    timer?.onAwait { null }
                }
                if (finished == null) {
                    // Quiet too long: ask the next model alongside, and start the clock for the one after.
                    timer = if (launchNext()) async { delay(hedgeMs) } else null
                    continue
                }
                running.remove(finished.first)
                val result = finished.second
                if (result.isSuccess) {
                    running.forEach { it.cancel() }
                    timer?.cancel()
                    return@coroutineScope result.getOrThrow()
                }
                val error = result.exceptionOrNull()!!
                if (error is GeminiException && error.retriable) {
                    if (!launchNext() && running.isEmpty()) {
                        timer?.cancel()
                        throw error
                    }
                    continue
                }
                running.forEach { it.cancel() }
                timer?.cancel()
                throw error
            }
            @Suppress("UNREACHABLE_CODE")
            error("unreachable")
        }
    }

    private suspend fun attempt(model: String, key: String, body: String, timeoutMs: Long): Result<String> {
        val response = try {
            withTimeoutOrNull(timeoutMs) { transport.post(model, key, body) }
                ?: return Result.failure(GeminiException.Timeout())
        } catch (e: IOException) {
            return Result.failure(GeminiException.Network(e))
        }
        return try {
            Result.success(parseResponse(response))
        } catch (e: GeminiException) {
            Result.failure(e)
        }
    }

    internal fun requestBody(
        system: String, parts: List<Part>, schema: JsonObject, thinkingLevel: String = "minimal",
    ): String = buildJsonObject {
        putJsonObject("systemInstruction") {
            putJsonArray("parts") { addJsonObject { put("text", system) } }
        }
        putJsonArray("contents") {
            addJsonObject {
                put("role", "user")
                putJsonArray("parts") {
                    for (part in parts) {
                        when (part) {
                            is Part.Text -> addJsonObject { put("text", part.text) }
                            is Part.Jpeg -> addJsonObject {
                                putJsonObject("inlineData") {
                                    put("mimeType", "image/jpeg")
                                    put("data", Base64.getEncoder().encodeToString(part.bytes))
                                }
                            }
                        }
                    }
                }
            }
        }
        putJsonObject("generationConfig") {
            put("responseMimeType", "application/json")
            put("responseSchema", schema)
            putJsonObject("thinkingConfig") { put("thinkingLevel", thinkingLevel) }
        }
    }.toString()

    internal fun parseResponse(response: HttpResponse): String {
        val root = try {
            Json.parseToJsonElement(response.body) as? JsonObject
        } catch (e: Exception) {
            null
        }
        if (response.code != 200) {
            val message = ((root?.get("error") as? JsonObject)?.get("message") as? JsonPrimitive)?.contentOrNull
            throw GeminiException.Http(response.code, message ?: "HTTP ${response.code}")
        }
        val candidate = (root?.get("candidates") as? JsonArray)?.firstOrNull() as? JsonObject
        val parts = ((candidate?.get("content") as? JsonObject)?.get("parts") as? JsonArray).orEmpty()
        val text = parts.firstNotNullOfOrNull { ((it as? JsonObject)?.get("text") as? JsonPrimitive)?.contentOrNull }
        return text ?: throw GeminiException.Empty()
    }

    companion object {
        /** The everyday chain; see [GeminiQuality.models]. */
        val MODELS: List<String> get() = GeminiQuality.FAST.models
    }
}
