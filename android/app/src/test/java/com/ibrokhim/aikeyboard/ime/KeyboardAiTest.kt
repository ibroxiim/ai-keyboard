package com.ibrokhim.aikeyboard.ime

import com.ibrokhim.aikeyboard.ai.ChatAnalysisService
import com.ibrokhim.aikeyboard.ai.ChatInput
import com.ibrokhim.aikeyboard.ai.LlmClient
import com.ibrokhim.aikeyboard.ai.Part
import com.ibrokhim.aikeyboard.ai.Translator
import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.data.Suggestion
import java.io.File
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class KeyboardAiTest {
    @get:Rule val folder = TemporaryFolder()

    private class Field : InputTarget {
        val text = StringBuilder()
        override val autoCapitalize = false
        override fun textBeforeCursor(length: Int) = text.takeLast(length).toString()
        override fun commit(text: String) {
            this.text.append(text)
        }
        override fun deleteBackward() = Unit
        override fun moveCursor(offset: Int) = Unit
        override fun enter() = Unit
        override fun switchKeyboard() = Unit
        override fun currentText() = text.toString()
        override fun replaceAll(text: String) {
            this.text.clear()
            this.text.append(text)
        }
    }

    private class Source(var input: ChatInput? = null) : ChatSource {
        val asked = mutableListOf<String>()
        override var available = true
        override suspend fun read(packageName: String): ChatInput? {
            asked.add(packageName)
            return input
        }
    }

    private class Llm : LlmClient {
        override suspend fun generate(system: String, parts: List<Part>, schema: JsonObject): String = when {
            system.contains("- partner:") ->
                """{"partner":"Emma","language":"English","tone":"casual","last_incoming_uz":"Bo'shmisan?"}"""
            system.contains("- suggestions:") ->
                """{"summary_uz":"x","transcript":[{"from":"them","text":"u free?"}],"suggestions":[{"text":"yes!","uz":"ha!"}]}"""
            else -> """{"variants":[{"text":"we're getting plov on saturday","uz":"Shanba kuni osh yeymiz"}]}"""
        }
    }

    private val field = Field()
    private val source = Source(input = ChatInput.Transcript(listOf("[TOP] Emma", "[L] u free?", "[R] maybe")))
    private var setupOpened = 0

    private fun TestScope.ai(): Pair<KeyboardAi, SharedStore> {
        val store = SharedStore(File(folder.root, "state.json"))
        val translator = Translator(Llm())
        val analysis = ChatAnalysisService(store, translator) { 1_000 }
        return KeyboardAi(store, translator, analysis, field, source, this, { 1_000 }) { setupOpened++ } to store
    }

    @Test fun readChatAnalysesTheChatOfTheFocusedApp() = runTest {
        val (ai, store) = ai()
        ai.readChat("com.example.chat")
        advanceUntilIdle()
        assertEquals(listOf("com.example.chat"), source.asked)
        assertEquals("Emma", store.value.context?.partner)
        assertEquals("yes!", store.value.context?.suggestions?.single()?.text)
    }

    @Test fun readerOffExplainsAndOpensSetup() = runTest {
        val (ai, _) = ai()
        source.available = false
        ai.readChat("com.example.chat")
        assertEquals(Notices.READER_OFF, ai.ui.value.notice)
        assertEquals(1, setupOpened)
        advanceTimeBy(KeyboardAi.NOTICE_MS + 1)
        assertNull(ai.ui.value.notice)
    }

    @Test fun unreadableChatSaysSo() = runTest {
        val (ai, store) = ai()
        source.input = null
        ai.readChat("com.example.chat")
        advanceTimeBy(1)
        assertEquals(Notices.UNREADABLE, ai.ui.value.notice)
        assertNull(store.value.context)
    }

    @Test fun magicWithoutADraftAsksForOne() = runTest {
        val (ai, _) = ai()
        ai.magic()
        assertEquals(Notices.WRITE_FIRST, ai.ui.value.notice)
    }

    @Test fun magicRewritesTheDraftAndPickReplacesIt() = runTest {
        val (ai, _) = ai()
        field.text.append("shanba kuni plov yeymiz")
        ai.magic()
        advanceUntilIdle()
        assertEquals("we're getting plov on saturday", ai.ui.value.variants.single().text)
        assertFalse(ai.ui.value.rewriting)
        ai.pick(ai.ui.value.variants.single())
        assertEquals("we're getting plov on saturday", field.text.toString())
        assertEquals(emptyList<Suggestion>(), ai.ui.value.variants)
    }

    @Test fun pickerSelectionsSetTheTarget() = runTest {
        val (ai, store) = ai()
        ai.togglePicker()
        assertEquals(true, ai.ui.value.pickerOpen)
        ai.selectFriend(Friend("Minji", "Korean", "friendly", 0))
        assertEquals("Minji", store.value.activeFriend)
        assertEquals("Korean", store.value.targetLanguage)
        assertFalse(ai.ui.value.pickerOpen)
        ai.selectLanguage("Turkish")
        assertNull(store.value.activeFriend)
        assertEquals("Turkish", store.value.targetLanguage)
    }

    @Test fun dismissContextClearsIt() = runTest {
        val (ai, store) = ai()
        store.update { it.copy(context = ChatAnalysis(partner = "Emma"), contextDate = 1_000) }
        ai.dismissContext()
        assertNull(store.value.context)
    }
}
