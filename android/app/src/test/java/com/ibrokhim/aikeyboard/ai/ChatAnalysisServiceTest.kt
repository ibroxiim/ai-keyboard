package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.SharedStore
import java.io.File
import kotlin.test.assertFailsWith
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ChatAnalysisServiceTest {
    @get:Rule val folder = TemporaryFolder()

    private val quick = """{"partner":"Emma","language":"English","tone":"casual","last_incoming_uz":"Bo'shmisan?"}"""
    private val details = """{"summary_uz":"Uchrashuv.","transcript":[{"from":"them","text":"u free?"}],""" +
        """"suggestions":[{"text":"yes!","uz":"ha!"}]}"""

    private class Llm(private val answer: (String) -> String) : LlmClient {
        override suspend fun generate(system: String, parts: List<Part>, schema: JsonObject) = answer(system)
    }

    private fun store() = SharedStore(File(folder.root, "state.json"))
    private val input = ChatInput.Transcript(listOf("[TOP] Emma", "[L] u free?"))

    @Test fun successFillsContextAndRemembersTheFriend() = runTest {
        val store = store()
        val quickSnapshots = mutableListOf<ChatAnalysis?>()
        val llm = Llm { system ->
            if (system.contains("- partner:")) quick else details.also { quickSnapshots.add(store.value.context) }
        }
        store.update { it.copy(context = ChatAnalysis(partner = "Old chat"), contextDate = 1) }
        val analysis = ChatAnalysisService(store, Translator(llm)) { 1_000 }.run(input)

        assertEquals("Emma", analysis.partner)
        val state = store.value
        assertEquals(analysis, state.context)
        assertEquals(1_000L, state.contextDate)
        assertNull(state.analyzingSince)
        assertNull(state.lastError)
        assertEquals(listOf("Emma"), state.friends.map { it.name })
        assertEquals("Emma", state.activeFriend)
        assertEquals("English", state.targetLanguage)
        // The translation was on screen (without suggestions yet) before the details call finished.
        assertEquals(listOf("Emma"), quickSnapshots.map { it?.partner })
        assertEquals(0, quickSnapshots.single()?.suggestions?.size)
    }

    @Test fun partialFailureKeepsTheTranslationAndRecordsTheError() = runTest {
        val store = store()
        val llm = Llm { if (it.contains("- partner:")) quick else throw GeminiException.Timeout() }
        ChatAnalysisService(store, Translator(llm)) { 2_000 }.run(input)
        assertEquals("Emma", store.value.context?.partner)
        assertEquals("Gemini javob bermadi", store.value.lastError)
    }

    @Test fun totalFailureClearsTheSpinnerAndRecordsTheError() = runTest {
        val store = store()
        val llm = Llm { throw GeminiException.Http(503, "overloaded") }
        assertFailsWith<GeminiException.Http> { ChatAnalysisService(store, Translator(llm)) { 3_000 }.run(input) }
        assertNull(store.value.analyzingSince)
        assertEquals("Gemini 503: overloaded", store.value.lastError)
        assertEquals(3_000L, store.value.lastErrorDate)
    }
}
