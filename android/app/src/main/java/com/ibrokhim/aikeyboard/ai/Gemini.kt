package com.ibrokhim.aikeyboard.ai

import java.io.IOException
import java.util.Base64
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
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
    class MissingKey : GeminiException("Gemini API kaliti yo'q")
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
 * Gemini with a hedge: the lite model answers in ~2 s but now and then takes 20–50 s, so if it has not
 * answered after [hedgeAfterMs] the bigger model is asked in parallel and the first answer wins.
 * A failure worth retrying falls back at once. (The iOS client waits out a 30 s timeout instead.)
 */
class GeminiClient(
    private val transport: GeminiTransport,
    private val apiKey: () -> String,
    private val models: List<String> = MODELS,
    private val hedgeAfterMs: Long = 5_000,
    private val attemptTimeoutMs: Long = 20_000,
) : LlmClient {

    override suspend fun generate(system: String, parts: List<Part>, schema: JsonObject): String {
        val key = apiKey()
        if (key.isBlank()) throw GeminiException.MissingKey()
        val body = requestBody(system, parts, schema)
        return coroutineScope {
            val primary = async { attempt(models[0], key, body) }
            val early = withTimeoutOrNull(hedgeAfterMs) { primary.await() }
            val error = early?.exceptionOrNull()
            when {
                early == null -> race(primary, async { attempt(models[1], key, body) })
                error == null -> early.getOrThrow()
                error is GeminiException && error.retriable -> attempt(models[1], key, body).getOrThrow()
                else -> throw error
            }
        }
    }

    private suspend fun attempt(model: String, key: String, body: String): Result<String> {
        val response = try {
            withTimeoutOrNull(attemptTimeoutMs) { transport.post(model, key, body) }
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

    private suspend fun race(a: Deferred<Result<String>>, b: Deferred<Result<String>>): String {
        val (first, other) = select<Pair<Result<String>, Deferred<Result<String>>>> {
            a.onAwait { it to b }
            b.onAwait { it to a }
        }
        if (first.isSuccess) {
            other.cancel()
            return first.getOrThrow()
        }
        return other.await().getOrThrow()
    }

    internal fun requestBody(system: String, parts: List<Part>, schema: JsonObject): String = buildJsonObject {
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
            putJsonObject("thinkingConfig") { put("thinkingLevel", "minimal") }
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
        val MODELS = listOf("gemini-3.5-flash-lite", "gemini-3.5-flash")
    }
}
