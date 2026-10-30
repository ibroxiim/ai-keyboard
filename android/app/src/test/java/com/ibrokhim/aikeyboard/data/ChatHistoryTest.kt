package com.ibrokhim.aikeyboard.data

import org.junit.Assert.assertEquals
import org.junit.Test

class ChatHistoryTest {
    private fun lines(vararg items: Pair<String, String>) = items.map { ChatLine(it.first, it.second) }

    @Test fun firstReadBecomesTheHistory() {
        val new = lines("them" to "hey there", "me" to "hello!")
        assertEquals(new, ChatHistory.merged(emptyList(), new))
    }

    @Test fun newMessagesAreAppendedAfterTheOverlap() {
        val old = lines("them" to "are you free friday?", "me" to "maybe, what time?", "them" to "around seven")
        val new = lines("me" to "maybe, what time?", "them" to "around seven", "me" to "works for me", "them" to "great")
        assertEquals(
            lines("them" to "are you free friday?", "me" to "maybe, what time?", "them" to "around seven", "me" to "works for me", "them" to "great"),
            ChatHistory.merged(old, new),
        )
    }

    @Test fun theSameReadTwiceChangesNothing() {
        val shot = lines("them" to "are you free friday?", "me" to "maybe, what time?", "them" to "around seven")
        val once = ChatHistory.merged(emptyList(), shot)
        assertEquals(once, ChatHistory.merged(once, shot))
    }

    @Test fun anOlderScreenfulInsideTheHistoryChangesNothing() {
        val old = lines("them" to "first message here", "me" to "second message here", "them" to "third message here", "me" to "fourth message here")
        assertEquals(old, ChatHistory.merged(old, lines("me" to "second message here", "them" to "third message here")))
    }

    @Test fun withoutOverlapTheNewReadIsTheNewerOne() {
        val old = lines("them" to "see you tomorrow")
        val new = lines("them" to "a week later, hello again", "me" to "hi!")
        assertEquals(old + new, ChatHistory.merged(old, new))
    }

    @Test fun aCutOffTopMessageStillOverlapsAndTheFullerWordingWins() {
        val old = lines("them" to "so much fun at the party last night", "me" to "yes we did!")
        val new = lines("them" to "we had so much fun at the party last night", "me" to "yes we did!", "them" to "again?")
        assertEquals(listOf("we had so much fun at the party last night", "yes we did!", "again?"), ChatHistory.merged(old, new).map { it.text })
    }

    @Test fun caseAndPunctuationDoNotBreakTheOverlapButTheSenderDoes() {
        assertEquals(3, ChatHistory.merged(lines("them" to "OK cool!!", "me" to "see you at 7"), lines("them" to "ok cool", "me" to "See you at 7.", "them" to "👍")).size)
        val old = lines("them" to "see you tomorrow, my friend", "me" to "sounds good to me")
        val new = lines("me" to "see you tomorrow, my friend", "them" to "sounds good to me")
        assertEquals(old + new, ChatHistory.merged(old, new))
    }

    @Test fun oneShortLineIsNotEnoughToAnchor() {
        assertEquals(4, ChatHistory.merged(lines("them" to "hi", "me" to "ok"), lines("me" to "ok", "them" to "bye")).size)
    }

    @Test fun onlyTheLatestMessagesAreKept() {
        val old = (0 until ChatHistory.LIMIT).map { ChatLine("them", "message number $it") }
        val merged = ChatHistory.merged(old, lines("me" to "a brand new reply", "them" to "another new message"))
        assertEquals(ChatHistory.LIMIT, merged.size)
        assertEquals("another new message", merged.last().text)
        assertEquals("message number 2", merged.first().text)
    }
}
