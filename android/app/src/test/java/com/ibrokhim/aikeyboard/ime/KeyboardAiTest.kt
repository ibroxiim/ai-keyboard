package com.ibrokhim.aikeyboard.ime

import android.text.InputType
import com.ibrokhim.aikeyboard.ai.ChatAnalysisService
import com.ibrokhim.aikeyboard.ai.ChatInput
import com.ibrokhim.aikeyboard.ai.GeminiQuality
import com.ibrokhim.aikeyboard.ai.LlmClient
import com.ibrokhim.aikeyboard.ai.Part
import com.ibrokhim.aikeyboard.ai.Translator
import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.RewriteTweak
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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
        val asked = mutableListOf<Pair<String, Boolean>>()
        override var available = true
        override suspend fun read(packageName: String, allowScreenshot: Boolean): ChatInput? {
            asked.add(packageName to allowScreenshot)
            return input
        }
    }

    private class Llm : LlmClient {
        var calls = 0
        val inputs = mutableListOf<String>()
        override suspend fun generate(system: String, parts: List<Part>, schema: JsonObject, quality: GeminiQuality): String {
            calls++
            inputs.add(parts.filterIsInstance<Part.Text>().joinToString("\n") { it.text })
            return when {
                system.contains("copied from the other person") ->
                    """{"language":"English","tone":"casual","last_incoming_uz":"Bo'shmisan?","summary_uz":"x","suggestions":[{"text":"yes!","uz":"ha!"}]}"""
                system.contains("- partner:") ->
                    """{"partner":"Emma","language":"English","tone":"casual","last_incoming_uz":"Bo'shmisan?"}"""
                system.contains("- suggestions:") ->
                    """{"summary_uz":"x","transcript":[{"from":"them","text":"u free?"}],"suggestions":[{"text":"yes!","uz":"ha!"}]}"""
                else -> """{"variants":[{"text":"we're getting plov on saturday","uz":"Shanba kuni osh yeymiz"}]}"""
            }
        }
    }

    private val field = Field()
    private val source = Source(ChatInput.Transcript(listOf("[TOP] Emma", "[L] u free?", "[R] maybe")))
    private val llm = Llm()
    private var setupOpened = 0
    private val textField = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES

    private fun TestScope.ai(): Pair<KeyboardAi, SharedStore> {
        val store = SharedStore(File(folder.root, "state.json"))
        val translator = Translator(llm)
        val analysis = ChatAnalysisService(store, translator) { 1_000 }
        return KeyboardAi(store, translator, analysis, field, source, this, { 1_000 }) { setupOpened++ } to store
    }

    @Test fun readChatAnalysesTheChatOfTheFocusedApp() = runTest {
        val (ai, store) = ai()
        ai.readChat("com.example.chat")
        advanceUntilIdle()
        assertEquals(listOf("com.example.chat" to true), source.asked)
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
        // The variants stay, with the picked one lit, so another one or the draft can be put back.
        assertEquals(1, ai.ui.value.variants.size)
        assertEquals("we're getting plov on saturday", ai.ui.value.picked)
        assertEquals("shanba kuni plov yeymiz", ai.ui.value.originalDraft)
        ai.restoreOriginal()
        assertEquals("shanba kuni plov yeymiz", field.text.toString())
        assertNull(ai.ui.value.picked)
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

    @Test fun detailsOpenOnlyWithAFreshContextAndCloseWithIt() = runTest {
        val (ai, store) = ai()
        ai.openDetails()
        assertFalse(ai.ui.value.detailsOpen)
        store.update { it.copy(context = ChatAnalysis(partner = "Emma"), contextDate = 1_000) }
        ai.openDetails()
        assertTrue(ai.ui.value.detailsOpen)
        ai.dismissContext()
        assertNull(store.value.context)
        assertFalse(ai.ui.value.detailsOpen)
    }

    @Test fun autoReadAnalysesAnEligibleChatOnceUntilItChanges() = runTest {
        val (ai, store) = ai()
        store.update { it.copy(autoRead = true) }
        ai.autoRead("com.whatsapp", textField)
        advanceUntilIdle()
        assertEquals(listOf("com.whatsapp" to false), source.asked) // text only, never a screenshot
        assertEquals("Emma", store.value.context?.partner)
        assertNotNull(store.value.lastReadHash)
        assertEquals(2, llm.calls)

        ai.autoRead("com.whatsapp", textField)
        advanceUntilIdle()
        assertEquals(2, llm.calls) // same chat, context still fresh: no new request

        source.input = ChatInput.Transcript(listOf("[TOP] Emma", "[L] u free?", "[R] maybe", "[L] ??"))
        ai.autoRead("com.whatsapp", textField)
        advanceUntilIdle()
        assertEquals(4, llm.calls)
    }

    @Test fun autoReadStaysQuietWhenOffOrOutsideMessengers() = runTest {
        val (ai, store) = ai()
        ai.autoRead("com.whatsapp", textField)
        store.update { it.copy(autoRead = true) }
        ai.autoRead("com.android.chrome", textField)
        advanceUntilIdle()
        assertEquals(emptyList<Pair<String, Boolean>>(), source.asked)
        assertEquals(0, llm.calls)
    }

    private class Clip(private var stamp: Long?, private val text: String?) : ClipboardSource {
        override var seen = 0L
        override fun stamp() = stamp
        override fun text() = text
    }

    private fun TestScope.aiWith(clip: ClipboardSource): Pair<KeyboardAi, SharedStore> {
        val store = SharedStore(folder.newFile("state.json"))
        val translator = Translator(llm)
        val analysis = ChatAnalysisService(store, translator) { 1_000 }
        return KeyboardAi(store, translator, analysis, field, source, this, { 1_000 }, clip) to store
    }

    @Test fun refineAsksAgainWithAnAdjustLineAndSwapsThePickedVariant() = runTest {
        val (ai, _) = ai()
        field.replaceAll("shanba kuni plov yeymiz")
        ai.magic(); advanceUntilIdle()
        ai.pick(ai.ui.value.variants.first())
        ai.refine(RewriteTweak.SHORTER); advanceUntilIdle()
        assertEquals(listOf(RewriteTweak.SHORTER), ai.ui.value.tweaks)
        assertTrue(llm.inputs.last().contains("Adjust: shorter"))
        assertTrue(llm.inputs.last().endsWith("Draft:\nshanba kuni plov yeymiz"))
        assertEquals("we're getting plov on saturday", ai.ui.value.picked)
        ai.refine(RewriteTweak.SHORTER); advanceUntilIdle()
        assertEquals(emptyList<RewriteTweak>(), ai.ui.value.tweaks)
        ai.magic(); advanceUntilIdle()
        assertNull(ai.ui.value.picked)
    }

    @Test fun aSentMessageClearsTheVariantsAndTeachesTheEdit() = runTest {
        val (ai, store) = ai()
        store.update { it.copy(friends = listOf(Friend("Emma", "English", "casual", 0)), activeFriend = "Emma") }
        field.replaceAll("shanba kuni plov yeymiz")
        ai.magic(); advanceUntilIdle()
        ai.pick(ai.ui.value.variants.first())
        field.replaceAll("we're getting plov on saturday 😄 you in?")
        ai.textChanged()
        assertEquals(1, ai.ui.value.variants.size)
        field.replaceAll("")
        ai.textChanged()
        assertEquals(emptyList<Suggestion>(), ai.ui.value.variants)
        assertNull(ai.ui.value.originalDraft)
        val example = store.value.friends.first().examples?.single()
        assertEquals(Friend.Example("shanba kuni plov yeymiz", "we're getting plov on saturday", "we're getting plov on saturday 😄 you in?"), example)
    }

    @Test fun anUnchangedVariantTeachesNothing() = runTest {
        val (ai, store) = ai()
        store.update { it.copy(friends = listOf(Friend("Emma", "English", "casual", 0)), activeFriend = "Emma") }
        field.replaceAll("salom")
        ai.magic(); advanceUntilIdle()
        ai.pick(ai.ui.value.variants.first())
        field.replaceAll("")
        ai.textChanged()
        assertNull(store.value.friends.first().examples)
    }

    @Test fun clipboardIsOfferedOnceAndTranslatedLikeAChat() = runTest {
        val clip = Clip(stamp = 42, text = "u free tonight?")
        val (ai, store) = aiWith(clip)
        store.update { it.copy(friends = listOf(Friend("Emma", "English", "casual", 0)), activeFriend = "Emma") }
        ai.checkClipboard(force = true)
        assertTrue(ai.ui.value.clipboardOffered)
        ai.translateClipboard(); advanceUntilIdle()
        assertFalse(ai.ui.value.clipboardOffered)
        assertEquals(42L, clip.seen)
        assertEquals("Bo'shmisan?", store.value.context?.lastIncomingUz)
        assertEquals("Emma", store.value.context?.partner)
        assertEquals(listOf("u free tonight?"), store.value.friends.first().history?.map { it.text })
        assertTrue(llm.inputs.last().contains("Copied text:\nu free tonight?"))
        ai.checkClipboard(force = true)
        assertFalse(ai.ui.value.clipboardOffered)
    }

    @Test fun anEmptyClipboardSaysSo() = runTest {
        val (ai, store) = aiWith(Clip(stamp = 7, text = " "))
        ai.translateClipboard()
        assertEquals(Notices.CLIPBOARD_EMPTY, ai.ui.value.notice)
        advanceUntilIdle()
        assertNull(ai.ui.value.notice)
        assertNull(store.value.context)
    }
}
