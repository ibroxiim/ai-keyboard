package com.ibrokhim.aikeyboard.ai

import java.io.File
import java.util.Properties
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Calls the real Gemini API with a made-up chat. Skipped unless android/local.properties has gemini.apiKey
 * and the LIVE_GEMINI environment variable is set — normal test runs never touch the network.
 */
class GeminiLiveTest {
    private val key: String = Properties().run {
        val file = File("../local.properties")
        if (file.exists()) file.inputStream().use { load(it) }
        getProperty("gemini.apiKey", "")
    }

    @Test fun transcriptReadingWorksEndToEnd() = runBlocking {
        assumeTrue(key.isNotBlank() && System.getenv("LIVE_GEMINI") != null)
        // Generous timeout: this checks the prompt and parsing, not today's API latency (often 5–25 s).
        val translator = Translator(GeminiClient(OkHttpGeminiTransport(), { key }, attemptTimeoutMs = 45_000))
        val lines = listOf(
            "[TOP] Emma",
            "[TOP] Active now",
            "[L] omg ur samarkand pics are unreal 😭😭",
            "[R] thank you! it was so beautiful",
            "[L] btw i'm landing in tashkent on friday w my sister ✈️",
            "[L] u free this weekend? we could grab food, ur call on the spot 🍜",
            "[L] 13:02",
        )
        val started = System.currentTimeMillis()
        val result = translator.analyze(ChatInput.Transcript(lines), emptyList()) {
            println("quick after ${System.currentTimeMillis() - started} ms: ${it.lastIncomingUz}")
        }
        println("full after ${System.currentTimeMillis() - started} ms: ${result.analysis.suggestions.map { it.text }}")
        result.partialError?.let { println("partial error: ${it::class.simpleName}: ${it.message} / ${it.cause}") }
        assertEquals("Emma", result.analysis.partner)
        assertEquals("English", result.analysis.language)
        assertEquals(3, result.analysis.suggestions.size)
        assertTrue(result.analysis.transcript.none { it.text == "13:02" || it.text == "Active now" })
    }
}
