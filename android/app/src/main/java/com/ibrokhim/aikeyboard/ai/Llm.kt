package com.ibrokhim.aikeyboard.ai

import kotlinx.serialization.json.JsonObject

sealed interface Part {
    data class Text(val text: String) : Part
    class Jpeg(val bytes: ByteArray) : Part
}

/** Turns a system prompt, the user's parts and a JSON schema into the model's JSON text. */
interface LlmClient {
    suspend fun generate(system: String, parts: List<Part>, schema: JsonObject): String
}

/** Like runCatching, but cancellation still propagates. */
internal inline fun <T> runCatchingNonCancel(block: () -> T): Result<T> = try {
    Result.success(block())
} catch (e: kotlinx.coroutines.CancellationException) {
    throw e
} catch (e: Exception) {
    Result.failure(e)
}
