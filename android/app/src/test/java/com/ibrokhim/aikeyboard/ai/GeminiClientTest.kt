package com.ibrokhim.aikeyboard.ai

import kotlin.test.assertFailsWith
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

class GeminiClientTest {
    private class FakeTransport(private val answer: suspend (model: String) -> HttpResponse) : GeminiTransport {
        val calls = mutableListOf<String>()
        var lastBody = ""
        override suspend fun post(model: String, apiKey: String, body: String): HttpResponse {
            calls.add(model)
            lastBody = body
            return answer(model)
        }
    }

    private fun ok(text: String) =
        HttpResponse(200, """{"candidates":[{"content":{"parts":[{"text":${JsonPrimitive(text)}}]}}]}""")

    private fun error(code: Int, message: String) = HttpResponse(code, """{"error":{"message":"$message"}}""")

    private val lite = GeminiClient.MODELS[0]
    private val flash = GeminiClient.MODELS[1]
    private val schema = JsonObject(emptyMap())

    private fun client(transport: GeminiTransport, key: String = "k") = GeminiClient(transport, { key })

    @Test fun primaryAnswers() = runTest {
        val transport = FakeTransport { ok("{\"a\":1}") }
        assertEquals("{\"a\":1}", client(transport).generate("sys", listOf(Part.Text("hi")), schema))
        assertEquals(listOf(lite), transport.calls)
    }

    @Test fun overloadedPrimaryFallsBackAtOnce() = runTest {
        val transport = FakeTransport { model -> if (model == lite) error(503, "overloaded") else ok("fallback") }
        assertEquals("fallback", client(transport).generate("sys", emptyList(), schema))
        assertEquals(listOf(lite, flash), transport.calls)
        assertEquals(0L, testScheduler.currentTime)
    }

    @Test fun slowPrimaryIsHedgedAfterFiveSeconds() = runTest {
        val transport = FakeTransport { model ->
            if (model == lite) {
                delay(30_000)
                ok("slow")
            } else {
                ok("fast")
            }
        }
        assertEquals("fast", client(transport).generate("sys", emptyList(), schema))
        assertEquals(5_000L, testScheduler.currentTime)
    }

    @Test fun clientErrorIsNotRetried() = runTest {
        val transport = FakeTransport { error(400, "API key not valid") }
        val e = assertFailsWith<GeminiException.Http> { client(transport).generate("sys", emptyList(), schema) }
        assertEquals(400, e.code)
        assertEquals(listOf(lite), transport.calls)
    }

    @Test fun bothFailing() = runTest {
        val transport = FakeTransport { error(503, "overloaded") }
        assertFailsWith<GeminiException.Http> { client(transport).generate("sys", emptyList(), schema) }
    }

    @Test fun hangingModelsTimeOut() = runTest {
        val transport = FakeTransport { awaitCancellation() }
        assertFailsWith<GeminiException.Timeout> { client(transport).generate("sys", emptyList(), schema) }
        assertEquals(25_000L, testScheduler.currentTime) // hedge at 5 s, fallback's own 20 s
    }

    @Test fun missingKeyFailsWithoutACall() = runTest {
        val transport = FakeTransport { ok("x") }
        assertFailsWith<GeminiException.MissingKey> { client(transport, key = "").generate("sys", emptyList(), schema) }
        assertEquals(emptyList<String>(), transport.calls)
    }

    @Test fun emptyCandidatesFallBack() = runTest {
        val transport = FakeTransport { model -> if (model == lite) HttpResponse(200, "{\"candidates\":[]}") else ok("x") }
        assertEquals("x", client(transport).generate("sys", emptyList(), schema))
    }

    @Test fun requestBodyCarriesPromptImageAndConfig() = runTest {
        val transport = FakeTransport { ok("{}") }
        client(transport).generate("system text", listOf(Part.Text("Known friends: Emma"), Part.Jpeg(byteArrayOf(1, 2, 3))), schema)
        val body = Json.parseToJsonElement(transport.lastBody).jsonObject
        val system = body["systemInstruction"]!!.jsonObject["parts"]!!.jsonArray[0].jsonObject["text"]!!.jsonPrimitive.content
        assertEquals("system text", system)
        val parts = body["contents"]!!.jsonArray[0].jsonObject["parts"]!!.jsonArray
        assertEquals("Known friends: Emma", parts[0].jsonObject["text"]!!.jsonPrimitive.content)
        assertEquals("AQID", parts[1].jsonObject["inlineData"]!!.jsonObject["data"]!!.jsonPrimitive.content)
        val config = body["generationConfig"]!!.jsonObject
        assertEquals("application/json", config["responseMimeType"]!!.jsonPrimitive.content)
        assertEquals("minimal", config["thinkingConfig"]!!.jsonObject["thinkingLevel"]!!.jsonPrimitive.content)
    }
}
