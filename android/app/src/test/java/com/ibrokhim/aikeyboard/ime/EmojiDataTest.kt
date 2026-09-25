package com.ibrokhim.aikeyboard.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EmojiDataTest {
    @Test fun sameListAsIos() {
        assertEquals(8, EmojiData.categories.size)
        assertEquals(1297, EmojiData.categories.sumOf { it.emojis.size })
        assertEquals("Smayllar va odamlar", EmojiData.categories.first().title)
        assertEquals("😀", EmojiData.categories.first().emojis.first())
    }

    @Test fun everyCategoryHasAnIconAndNoBlanks() {
        EmojiData.categories.forEach { category ->
            assertTrue(category.icon.isNotBlank())
            assertTrue(category.emojis.none { it.isBlank() })
        }
    }
}
