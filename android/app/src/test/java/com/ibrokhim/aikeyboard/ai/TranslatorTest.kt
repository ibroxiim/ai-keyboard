package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.ChatLine
import com.ibrokhim.aikeyboard.data.Friend
import kotlin.test.assertFailsWith
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TranslatorTest {
    private class FakeLlm(private val answer: (system: String) -> String) : LlmClient {
        val calls = mutableListOf<Pair<String, List<Part>>>()
        override suspend fun generate(system: String, parts: List<Part>, schema: JsonObject): String {
            calls.add(system to parts)
            return answer(system)
        }
    }

    private val quick = """{"partner":"Emma","language":"English","tone":"casual","last_incoming_uz":"Bo'shmisan?"}"""
    private val details = """{"summary_uz":"Uchrashuv.","transcript":[{"from":"them","text":"u free?"}],""" +
        """"suggestions":[{"text":"yes!","uz":"ha!"}]}"""

    private fun isQuick(system: String) = system.contains("- partner:")

    private val transcript = ChatInput.Transcript(listOf("[TOP] Emma", "[L] u free?", "[R] maybe"))

    @Test fun analyzeMergesBothHalvesAndShowsTheQuickOneFirst() = runTest {
        val llm = FakeLlm { if (isQuick(it)) quick else details }
        val seen = mutableListOf<String>()
        val result = Translator(llm).analyze(transcript, listOf("Emma")) { seen.add(it.partner) }
        assertEquals(listOf("Emma"), seen)
        assertEquals("Emma", result.analysis.partner)
        assertEquals("yes!", result.analysis.suggestions.single().text)
        assertNull(result.partialError)
    }

    @Test fun transcriptUsesTheTextPromptAndKnownFriendsGoFirst() = runTest {
        val llm = FakeLlm { if (isQuick(it)) quick else details }
        Translator(llm).analyze(transcript, listOf("Emma", "Minji")) {}
        val (system, parts) = llm.calls.first { isQuick(it.first) }
        assertTrue(system.contains("[R]"))
        assertEquals(Part.Text("Known friends: Emma, Minji"), parts[0])
        assertEquals(Part.Text("[TOP] Emma\n[L] u free?\n[R] maybe"), parts[1])
    }

    @Test fun screenshotUsesTheImagePrompt() = runTest {
        val llm = FakeLlm { if (isQuick(it)) quick else details }
        Translator(llm).analyze(ChatInput.Screenshot(byteArrayOf(1)), emptyList()) {}
        val (system, parts) = llm.calls.first()
        assertTrue(system.contains("screenshot"))
        assertTrue(parts.single() is Part.Jpeg)
    }

    @Test fun failedDetailsHalfIsPartial() = runTest {
        val llm = FakeLlm { if (isQuick(it)) quick else throw GeminiException.Timeout() }
        val result = Translator(llm).analyze(transcript, emptyList()) {}
        assertEquals("Emma", result.analysis.partner)
        assertEquals(0, result.analysis.suggestions.size)
        assertNotNull(result.partialError)
    }

    @Test fun bothHalvesFailing() = runTest {
        val llm = FakeLlm { throw GeminiException.Timeout() }
        assertFailsWith<GeminiException.Timeout> { Translator(llm).analyze(transcript, emptyList()) {} }
    }

    @Test fun rewriteReturnsTheVariants() = runTest {
        val llm = FakeLlm { """{"variants":[{"text":"we're getting plov on saturday","uz":"Shanba kuni osh yeymiz"}]}""" }
        val variants = Translator(llm).rewrite("shanba kuni plov yeymiz", null, null, "English")
        assertEquals("we're getting plov on saturday", variants.single().text)
    }

    @Test fun rewriteInputCarriesTheConversation() {
        val context = ChatAnalysis(
            partner = "Emma", tone = "casual",
            transcript = listOf(ChatLine("them", "u free?"), ChatLine("me", "yes")),
        )
        val input = Prompts.rewriteInput("salom", context, null, "English")
        assertEquals(
            "Target language: English\nConversation tone: casual\nPartner: Emma\nRecent messages:\n" +
                "them: u free?\nme: yes\n\nDraft:\nsalom",
            input,
        )
        val friendOnly = Prompts.rewriteInput("salom", null, Friend("Minji", "Korean", "friendly", 0), "Korean")
        assertTrue(friendOnly.contains("Partner: Minji\nConversation tone: friendly\nNo recent messages available."))
    }
}
