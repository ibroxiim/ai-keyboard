package com.ibrokhim.aikeyboard.data

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SharedStoreTest {
    @get:Rule val folder = TemporaryFolder()

    private fun file() = File(folder.root, "state.json")

    @Test fun updatesArePersistedAndPublished() {
        val store = SharedStore(file())
        store.update { it.copy(targetLanguage = "Korean", friends = listOf(Friend("Minji", "Korean", "friendly", 1))) }
        assertEquals("Korean", store.state.value.targetLanguage)
        val reopened = SharedStore(file())
        assertEquals("Korean", reopened.value.targetLanguage)
        assertEquals("Minji", reopened.value.friends.single().name)
    }

    @Test fun contextRoundTripsWithSnakeCaseKeys() {
        val store = SharedStore(file())
        val analysis = ChatAnalysis(partner = "Emma", lastIncomingUz = "Salom", summaryUz = "Xulosa")
        store.update { it.copy(context = analysis, contextDate = 5) }
        val text = file().readText()
        assertEquals(true, text.contains("\"last_incoming_uz\":\"Salom\""))
        assertEquals(analysis, SharedStore(file()).value.context)
    }

    @Test fun corruptFileStartsFresh() {
        file().writeText("{not json")
        assertEquals(SharedState(), SharedStore(file()).value)
    }

    @Test fun unchangedStateIsNotWritten() {
        val store = SharedStore(file())
        store.update { it }
        assertFalse(file().exists())
    }
}
