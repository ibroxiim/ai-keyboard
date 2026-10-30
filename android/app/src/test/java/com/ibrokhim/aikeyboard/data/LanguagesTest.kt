package com.ibrokhim.aikeyboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LanguagesTest {
    @Test fun normalizedTidiesAndUsesTheCatalogSpelling() {
        assertEquals("Swahili", Languages.normalized("  swahili "))
        assertEquals("Old English", Languages.normalized("old   english"))
        assertEquals("Swiss GERMAN", Languages.normalized("swiss GERMAN"))
        assertEquals("Korean", Languages.normalized("KOREAN"))
        assertNull(Languages.normalized(""))
        assertNull(Languages.normalized("  \n "))
        assertNull(Languages.normalized("a".repeat(31)))
    }

    @Test fun addingAppendsOnceAndIgnoresBlanks() {
        assertEquals(listOf("English", "Korean", "Thai"), Languages.adding("thai", listOf("English", "Korean")))
        assertEquals(listOf("English", "Korean"), Languages.adding("korean", listOf("English", "Korean")))
        assertEquals(listOf("English"), Languages.adding("   ", listOf("English")))
    }

    @Test fun addableLeavesOutWhatIsListed() {
        val addable = Languages.addable(listOf("English", "korean")).map { it.name }
        assertFalse(addable.contains("English"))
        assertFalse(addable.contains("Korean"))
        assertEquals("Russian", addable.first())
    }

    @Test fun flagsAndCatalogAreConsistent() {
        assertEquals("🇰🇷", Languages.flag("korean"))
        assertEquals("🌐", Languages.flag("Klingon"))
        val names = Languages.catalog.map { it.name.lowercase() }
        assertEquals(names.size, names.toSet().size)
        assertTrue(Languages.defaults.all { it.lowercase() in names })
        assertEquals(Languages.defaults, SharedState(languages = null).languageList)
        assertEquals(listOf("Thai"), SharedState(languages = listOf("Thai")).languageList)
    }
}
