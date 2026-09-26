package com.ibrokhim.aikeyboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FriendTest {
    @Test fun truncatedAndDecoratedNamesAreTheSamePerson() {
        assertTrue(Friend.isSamePerson("Christi...", "Christina"))
        assertTrue(Friend.isSamePerson("christina 🌸", "Christina"))
        assertTrue(Friend.isSamePerson("christina.lee", "Christina"))
        assertTrue(Friend.isSamePerson("Émma", "emma"))
    }

    @Test fun oneMisreadLetterIsToleratedFromSixLetters() {
        assertTrue(Friend.isSamePerson("Christima", "Christina"))
        assertTrue(Friend.isSamePerson("Gabriet", "Gabriel"))
        assertFalse(Friend.isSamePerson("Maria", "Marta"))
    }

    @Test fun shortOrEmptyNamesDoNotMatch() {
        assertFalse(Friend.isSamePerson("Ali", "Alisher"))
        assertFalse(Friend.isSamePerson("", "Emma"))
        assertFalse(Friend.isSamePerson("🌸", "🌸"))
    }

    @Test fun nonLatinNamesKeepTheirLetters() {
        assertEquals("민지", Friend.key("민지 🌷"))
        assertTrue(Friend.isSamePerson("Minji", "minji_"))
    }

    @Test fun bestNameKeepsTheMostCompleteSpelling() {
        assertEquals("Christina", Friend.bestName(listOf("Christi…", "Christina", "Christ")))
    }
}
