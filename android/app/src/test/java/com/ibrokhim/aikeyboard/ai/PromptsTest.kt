package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.ChatLine
import com.ibrokhim.aikeyboard.data.ClipboardOffer
import com.ibrokhim.aikeyboard.data.ClipboardRead
import com.ibrokhim.aikeyboard.data.EditLearning
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.RewriteTweak
import com.ibrokhim.aikeyboard.data.SharedState
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.data.Suggestion
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PromptsTest {
    private fun friend(name: String, notes: String? = null) = Friend(name, "English", "casual", 0, notes = notes)

    @Test fun styleReachesTranslationPromptsAndIsCapped() {
        assertEquals("", Prompts.styleBlock(null))
        assertEquals("", Prompts.styleBlock("  \n "))
        assertTrue(Prompts.quick(Prompts.transcriptBasics, "ko'cha tilida").endsWith("ko'cha tilida"))
        assertTrue(Prompts.rewriteSystem("ko'cha tilida").contains("own instructions"))
        assertFalse(Prompts.quick(Prompts.transcriptBasics).contains("own instructions"))
        val block = Prompts.styleBlock("a".repeat(Prompts.STYLE_LIMIT + 500))
        assertTrue(block.endsWith("a".repeat(Prompts.STYLE_LIMIT)))
        assertFalse(block.contains("a".repeat(Prompts.STYLE_LIMIT + 1)))
    }

    @Test fun translationCoversTheWholeUnansweredRunAndTwelveMessages() {
        val quick = Prompts.quick(Prompts.screenshotBasics)
        assertTrue(quick.contains("EVERY message from \"them\" after the last message from \"me\""))
        assertTrue(quick.contains("speech level"))
        assertTrue(Prompts.details(Prompts.transcriptBasics).contains("last up to 12 messages"))
        assertTrue(Prompts.details(Prompts.transcriptBasics).contains("romanization"))
    }

    @Test fun knownFriendsCarryNotesWithinTheBudget() {
        assertNull(Prompts.knownFriendsPart(emptyList()))
        assertEquals("Known friends: Anna, Minho", Prompts.knownFriendsPart(listOf(friend("Anna"), friend("Minho", "  "))))
        val part = Prompts.knownFriendsPart(listOf(friend("Anna", "my classmate"), friend("Minho")))
        assertEquals("Known friends: Anna, Minho\n\nThe user's notes about Anna (follow them when the partner is Anna):\nmy classmate", part)
        val long = "x".repeat(Prompts.STYLE_LIMIT)
        val budgeted = Prompts.knownFriendsPart((1..4).map { friend("F$it", long) })!!
        assertEquals(Prompts.FRIEND_NOTES_BUDGET, budgeted.count { it == 'x' })
        assertTrue(budgeted.contains("notes about F2"))
        assertFalse(budgeted.contains("notes about F3"))
        assertTrue(Prompts.transcriptBasics.contains("notes about known friends"))
    }

    @Test fun rewriteInputCarriesFormalityTweaksNotesExamplesAndHistory() {
        val examples = (0 until EditLearning.PROMPT_LIMIT + 3).map { Friend.Example("draft $it", "sugg $it", "sent $it") }
        val history = listOf(ChatLine("them", "are you free friday?"), ChatLine("me", "maybe, what time?"))
        val input = Prompts.rewriteInput(
            "salom", null, friend("Anna"), "Korean", Friend.Formality.FORMAL, history, "my classmate",
            listOf(RewriteTweak.SHORTER, RewriteTweak.WARMER), examples,
        )
        assertTrue(input.startsWith("Target language: Korean\nFormality chosen by the user: formal\nAdjust: shorter; warmer and more affectionate"))
        assertTrue(input.contains("The user's notes about this friend (follow them):\nmy classmate"))
        assertTrue(input.contains("- draft: draft 12\n  suggested: sugg 12\n  sent: sent 12"))
        assertFalse(input.contains("draft 2\n"))
        assertTrue(input.contains("Earlier messages, from past chat reads"))
        assertTrue(input.contains("them: are you free friday?\nme: maybe, what time?"))
        assertTrue(input.endsWith("Draft:\nsalom"))
        val plain = Prompts.rewriteInput("salom", null, null, "English")
        assertFalse(plain.contains("Formality"))
        assertFalse(plain.contains("Adjust"))
        assertTrue(plain.contains("No conversation context"))
    }

    @Test fun rewriteInputWithAReadPrefersTheLongerRememberedChat() {
        val context = ChatAnalysis(partner = "Anna", tone = "casual", transcript = listOf(ChatLine("them", "newest message")))
        val history = listOf(ChatLine("me", "an older message"), ChatLine("them", "newest message"))
        assertTrue(Prompts.rewriteInput("x", context, null, "English", history = history).contains("me: an older message\nthem: newest message"))
        assertTrue(Prompts.rewriteSystem().contains("\"Adjust\" line"))
        assertTrue(RewriteTweak.entries.all { it.label.isNotEmpty() && it.instruction.isNotEmpty() })
    }

    @Test fun suggestionsCarryAnOptionalReading() {
        val plain = SharedStore.json.decodeFromString(Suggestion.serializer(), """{"text":"hi","uz":"salom"}""")
        assertNull(plain.read)
        val korean = SharedStore.json.decodeFromString(Suggestion.serializer(), """{"text":"안녕","uz":"salom","read":"annyeong"}""")
        assertEquals("annyeong", korean.read)
        val required = (Prompts.suggestionSchema["required"] as JsonArray).map { it.jsonPrimitive.content }
        assertEquals(listOf("text", "uz"), required)
        assertTrue((Prompts.suggestionSchema["properties"] as JsonObject).containsKey("read"))
    }

    @Test fun clipboardReadBecomesAnAnalysisTheKeyboardUnderstands() {
        val json = """{"language":"English","tone":"casual","last_incoming_uz":"Qalaysan?\nErtaga ko'rishamizmi?","summary_uz":"Ertaga.","suggestions":[{"text":"yes!","uz":"ha!"}]}"""
        val read = SharedStore.json.decodeFromString(ClipboardRead.serializer(), json)
        val analysis = read.analysis("Anna", "how are you?\n\n see you tomorrow? ")
        assertEquals("Anna", analysis.partner)
        assertEquals(listOf(ChatLine("them", "how are you?"), ChatLine("them", "see you tomorrow?")), analysis.transcript)
        assertEquals("how are you? see you tomorrow?", analysis.lastIncoming)
        val state = SharedState(friends = listOf(friend("Anna"))).remember(read.analysis("Anna", "are you free friday?"), 5)
        assertEquals(listOf("are you free friday?"), state.friends.first().history?.map { it.text })
        assertNull(ClipboardOffer.usable(null)); assertNull(ClipboardOffer.usable(" a "))
        assertEquals("hey there", ClipboardOffer.usable("  hey there \n"))
        assertEquals(ClipboardOffer.TEXT_LIMIT, ClipboardOffer.usable("a".repeat(ClipboardOffer.TEXT_LIMIT + 10))?.length)
        assertTrue(Prompts.clipboardSystem("oddiy yoz").endsWith("oddiy yoz"))
        assertEquals(5, (Prompts.clipboardSchema["required"] as JsonArray).size)
    }

    @Test fun qualityPicksModelsThinkingAndPatience() {
        assertEquals("gemini-3.5-flash-lite", GeminiQuality.FAST.models.first())
        assertEquals(listOf("gemini-3.6-flash", "gemini-3.5-flash"), GeminiQuality.CAREFUL.models.take(2))
        assertEquals(GeminiQuality.FAST.models.toSet(), GeminiQuality.CAREFUL.models.toSet())
        assertEquals("minimal", GeminiQuality.FAST.thinkingLevel)
        assertEquals("low", GeminiQuality.CAREFUL.thinkingLevel)
        assertTrue(GeminiQuality.CAREFUL.patience > GeminiQuality.FAST.patience)
    }
}
