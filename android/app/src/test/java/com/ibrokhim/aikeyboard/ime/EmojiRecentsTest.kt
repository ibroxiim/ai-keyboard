package com.ibrokhim.aikeyboard.ime

import org.junit.Assert.assertEquals
import org.junit.Test

class EmojiRecentsTest {
    private var stored = emptyList<String>()
    private val recents = EmojiRecents({ stored }, { stored = it })

    @Test fun newestFirstWithoutDuplicates() {
        recents.add("😀")
        recents.add("🔥")
        recents.add("😀")
        assertEquals(listOf("😀", "🔥"), recents.all)
    }

    @Test fun keepsThirtyTwo() {
        (1..40).forEach { recents.add("e$it") }
        assertEquals(EmojiRecents.LIMIT, recents.all.size)
        assertEquals("e40", recents.all.first())
    }
}
