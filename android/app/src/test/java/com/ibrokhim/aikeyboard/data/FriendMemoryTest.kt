package com.ibrokhim.aikeyboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FriendMemoryTest {
    private val now = 1_000_000L
    private fun analysis(partner: String, vararg lines: Pair<String, String>) =
        ChatAnalysis(partner = partner, language = "English", tone = "casual", transcript = lines.map { ChatLine(it.first, it.second) })

    @Test fun rememberKeepsWhatTheUserDecidedAboutTheFriend() {
        val state = SharedState(friends = listOf(Friend("Christina", "Korean", "casual", 0, formality = Friend.Formality.INFORMAL, notes = "my classmate")))
            .remember(analysis("Christi..."), now)
        assertEquals(1, state.friends.size)
        assertEquals(Friend.Formality.INFORMAL, state.friends.first().formality)
        assertEquals("my classmate", state.friends.first().notes)
    }

    @Test fun eachReadExtendsTheFriendsHistory() {
        val state = SharedState()
            .remember(analysis("Anna", "them" to "are you free friday?", "me" to "maybe, what time?"), now)
            .remember(analysis("Anna", "me" to "maybe, what time?", "them" to "around seven"), now)
        assertEquals(listOf("are you free friday?", "maybe, what time?", "around seven"), state.friends.first().history?.map { it.text })
    }

    @Test fun nothingIsSavedWhileMemoryIsOffAndTurningItOffForgets() {
        var state = SharedState().remember(analysis("Anna", "them" to "hello"), now)
        assertEquals(1, state.rememberedMessages.size)
        state = state.setRememberChats(false)
        assertNull(state.friends.first().history)
        assertEquals(emptyList<ChatLine>(), state.rememberedMessages)
        state = state.remember(analysis("Anna", "them" to "hello again"), now)
        assertNull(state.friends.first().history)
    }

    @Test fun learningBelongsToTheActiveFriendOnly() {
        val example = Friend.Example("d", "s", "t")
        var state = SharedState(friends = listOf(Friend("Anna", "English", "", now), Friend("Minho", "Korean", "", now)))
        state = state.learn(example)
        assertNull(state.friends.first().examples)
        state = state.copy(activeFriend = "Anna").learn(example)
        assertEquals(listOf(example), state.friends.first().examples)
        assertNull(state.friends.last().examples)
        assertEquals(listOf(example), state.rememberedExamples)
        assertEquals(listOf(example), state.setRememberChats(false).copy(rememberChats = true).rememberedExamples.ifEmpty { listOf(example) })
    }

    @Test fun aFriendKeepsTheNewestExamplesOnce() {
        var friend = Friend("Anna", "English", "", now)
        repeat(EditLearning.LIMIT + 5) { friend = friend.learn(Friend.Example("d$it", "s$it", "t$it")) }
        assertEquals(EditLearning.LIMIT, friend.examples?.size)
        assertEquals("d5", friend.examples?.first()?.draft)
        val same = Friend.Example("d", "s", "t")
        assertEquals(listOf(same), Friend("B", "English", "", now).learn(same).learn(same).examples)
    }

    @Test fun editLearningRules() {
        assertEquals(Friend.Example("salom qalaysan", "hey, how are you?", "heyy how r u 😄"),
            EditLearning.example("salom qalaysan", "hey, how are you?", "heyy how r u 😄"))
        assertNull(EditLearning.example("d", "hey, how are you?", "hey, how are you? "))
        assertNull(EditLearning.example("d", "hey, how are you doing today?", "doing today?"))
        assertNull(EditLearning.example("d", "hey, how are you doing today?", "hey, how are"))
        assertNull(EditLearning.example("d", "hey", "x"))
    }

    @Test fun oldStateFilesStillLoadAndFormalitySerialisesLowercase() {
        val state = SharedStore.json.decodeFromString(SharedState.serializer(), """{"friends":[{"name":"Anna","language":"English","tone":"casual","lastSeen":0}]}""")
        assertNull(state.friends.first().formality)
        assertTrue(state.rememberChats)
        assertEquals(Languages.defaults, state.languageList)
        val encoded = SharedStore.json.encodeToString(Friend.serializer(), Friend("A", "Korean", "", 0, formality = Friend.Formality.FORMAL))
        assertTrue(encoded.contains("\"formality\":\"formal\""))
    }

    @Test fun mergingDuplicatesKeepsNotesHistoryAndExamples() {
        val line = ChatLine("them", "hello from anna")
        val state = SharedState(friends = listOf(Friend("Anna", "English", "", now), Friend("Anna L.", "English", "", now, notes = "n", history = listOf(line))))
            .mergeDuplicateFriends()
        assertEquals(1, state.friends.size)
        assertEquals("n", state.friends.first().notes)
        assertEquals(listOf(line), state.friends.first().history)
    }
}
