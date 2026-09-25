package com.ibrokhim.aikeyboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class SharedStateTest {
    private val now = 1_000_000_000L
    private val emma = ChatAnalysis(partner = "Emma", language = "English", tone = "casual")

    @Test fun contextExpiresAfterFifteenMinutes() {
        val state = SharedState(context = emma, contextDate = now)
        assertEquals(emma, state.freshContext(now + 14 * 60_000))
        assertNull(state.freshContext(now + 15 * 60_000))
    }

    @Test fun languageFollowsFreshContextThenTargetThenEnglish() {
        assertEquals("English", SharedState().language(now))
        assertEquals("Korean", SharedState(targetLanguage = "Korean").language(now))
        val korean = ChatAnalysis(partner = "Minji", language = "Korean")
        assertEquals("Korean", SharedState(context = korean, contextDate = now, targetLanguage = "Turkish").language(now))
    }

    @Test fun rememberPutsTheFriendFirstAndMakesThemTheTarget() {
        val older = Friend("Minji", "Korean", "friendly", now - 1)
        val state = SharedState(friends = listOf(older)).remember(emma, now)
        assertEquals(listOf("Emma", "Minji"), state.friends.map { it.name })
        assertEquals("Emma", state.activeFriend)
        assertEquals("English", state.targetLanguage)
    }

    @Test fun rememberMergesAMisreadNameIntoTheKnownFriend() {
        val known = Friend("Christina", "English", "casual", now - 1)
        val misread = ChatAnalysis(partner = "Christima", language = "English", tone = "slang")
        val state = SharedState(friends = listOf(known)).remember(misread, now)
        assertEquals(1, state.friends.size)
        assertEquals("Christima", state.friends[0].name) // same length: first (newest) spelling wins
        assertEquals("slang", state.friends[0].tone)
    }

    @Test fun rememberKeepsAtMostEightFriends() {
        val many = (1..8).map { Friend("Friend number $it", "English", "", now - it) }
        val state = SharedState(friends = many).remember(emma, now)
        assertEquals(8, state.friends.size)
        assertEquals("Emma", state.friends.first().name)
    }

    @Test fun failedQuickHalfChangesNothing() {
        val state = SharedState(targetLanguage = "Korean")
        assertSame(state, state.remember(ChatAnalysis(), now))
    }

    @Test fun unknownPartnerClearsTheActiveFriend() {
        val state = SharedState(activeFriend = "Emma").remember(ChatAnalysis(language = "Turkish"), now)
        assertNull(state.activeFriend)
        assertEquals("Turkish", state.targetLanguage)
    }

    @Test fun activeFriendProfileOnlyWithoutFreshContext() {
        val friend = Friend("Emma", "English", "casual", now)
        val state = SharedState(activeFriend = "Emma", friends = listOf(friend))
        assertEquals(friend, state.activeFriendProfile(now))
        assertNull(state.copy(context = emma, contextDate = now).activeFriendProfile(now))
    }

    @Test fun mergeDuplicateFriendsKeepsNewestToneAndFullestName() {
        val state = SharedState(
            activeFriend = "Gabriet",
            friends = listOf(Friend("Gabriet", "English", "new", now), Friend("Gabriel M", "English", "old", now - 1)),
        ).mergeDuplicateFriends()
        assertEquals(listOf("Gabriel M"), state.friends.map { it.name })
        assertEquals("new", state.friends[0].tone)
        assertEquals("Gabriel M", state.activeFriend)
    }

    @Test fun errorsAndAnalysisExpire() {
        val state = SharedState(analyzingSince = now, lastError = "x", lastErrorDate = now)
        assertEquals(true, state.isAnalyzing(now + 59_000))
        assertEquals(false, state.isAnalyzing(now + 60_000))
        assertEquals("x", state.recentError(now + 119_000))
        assertNull(state.recentError(now + 120_000))
    }
}
