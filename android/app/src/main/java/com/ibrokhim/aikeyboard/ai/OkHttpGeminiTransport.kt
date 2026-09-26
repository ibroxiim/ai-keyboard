package com.ibrokhim.aikeyboard.ai

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

class OkHttpGeminiTransport(private val client: OkHttpClient = defaultClient) : GeminiTransport {
    override suspend fun post(model: String, apiKey: String, body: String): HttpResponse {
        val request = Request.Builder()
            .url("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent")
            .header("x-goog-api-key", apiKey)
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()
        val call = client.newCall(request)
        return suspendCancellableCoroutine { continuation ->
            // The hedge cancels the losing request; drop its socket too.
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    val result = response.use { HttpResponse(it.code, it.body?.string().orEmpty()) }
                    if (continuation.isActive) continuation.resume(result)
                }
            })
        }
    }

    companion object {
        /**
         * OkHttp's default 10 s read timeout would cut off a slow-but-fine answer before GeminiClient's own
         * hedge and 20 s attempt timeout decide; those own the timing, OkHttp only guards against hangs.
         */
        val defaultClient: OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()
    }
}
