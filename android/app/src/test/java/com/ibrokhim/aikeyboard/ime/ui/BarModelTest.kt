package com.ibrokhim.aikeyboard.ime.ui

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.SharedState
import com.ibrokhim.aikeyboard.data.Suggestion
import com.ibrokhim.aikeyboard.ime.AiUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BarModelTest {
    private val now = 10_000_000L
    private val emma = Friend("Emma", "English", "casual", now)
    private val idle = AiUiState()

    @Test fun idleShowsTheTargetWithTheActiveFriendAndStaysCompact() {
        val model = barModel(SharedState(targetLanguage = "English", activeFriend = "Emma", friends = listOf(emma)), idle, now)
        assertEquals(Status.Idle("✨ → 🇬🇧 English · Emma"), model.status)
        assertEquals(Chips.None, model.chips)
        assertFalse(model.expanded)
    }

    @Test fun readingShowsBothPlaceholders() {
        val model = barModel(SharedState(analyzingSince = now), idle, now)
        assertEquals(Status.Reading, model.status)
        assertEquals(Chips.Preparing, model.chips)
        assertTrue(model.expanded)
    }

    @Test fun translationArrivesBeforeTheReplies() {
        val quickOnly = ChatAnalysis(partner = "Emma", lastIncomingUz = "Bo'shmisan?")
        val reading = SharedState(context = quickOnly, contextDate = now, analyzingSince = now)
        assertEquals(Status.Translation("Emma", "Bo'shmisan?"), barModel(reading, idle, now).status)
        assertEquals(Chips.Preparing, barModel(reading, idle, now).chips)

        val replies = listOf(Suggestion("yes!", "ha!"))
        val done = SharedState(context = quickOnly.copy(suggestions = replies), contextDate = now)
        assertEquals(Chips.Replies(replies), barModel(done, idle, now).chips)
    }

    @Test fun variantsAndNoticesTakeOver() {
        val variants = listOf(Suggestion("we're getting plov on saturday", "Shanba kuni osh yeymiz"))
        val withVariants = barModel(SharedState(), AiUiState(variants = variants), now)
        assertEquals(Status.Variants, withVariants.status)
        assertEquals(Chips.Replies(variants), withVariants.chips)
        assertEquals(Status.Notice("x"), barModel(SharedState(), AiUiState(notice = "x", variants = variants), now).status)
    }

    @Test fun recentErrorIsShownUntilItExpires() {
        val state = SharedState(lastError = "Gemini javob bermadi", lastErrorDate = now)
        assertEquals(Status.Failed("Gemini javob bermadi"), barModel(state, idle, now).status)
        assertTrue(barModel(state, idle, now + 120_000).status is Status.Idle)
    }

    @Test fun staleContextFallsBackToIdle() {
        val state = SharedState(context = ChatAnalysis(partner = "Emma", language = "English"), contextDate = now - 16 * 60_000)
        assertTrue(barModel(state, idle, now).status is Status.Idle)
    }

    @Test fun pickerListsFriendsAndOtherLanguages() {
        val model = barModel(SharedState(targetLanguage = "Korean", friends = listOf(emma)), AiUiState(pickerOpen = true), now)
        val picker = model.chips as Chips.Picker
        assertEquals(listOf(emma), picker.friends)
        assertFalse(picker.languages.contains("Korean"))
        assertTrue(picker.languages.contains("English"))
    }

    @Test fun rewritingSpinsTheMagicButton() {
        assertTrue(barModel(SharedState(), AiUiState(rewriting = true), now).rewriting)
    }
}
