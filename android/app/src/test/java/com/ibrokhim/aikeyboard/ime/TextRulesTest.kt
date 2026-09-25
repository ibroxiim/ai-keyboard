package com.ibrokhim.aikeyboard.ime

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TextRulesTest {
    @Test fun sentenceStarts() {
        assertTrue(TextRules.startsSentence(""))
        assertTrue(TextRules.startsSentence("   "))
        assertTrue(TextRules.startsSentence("Salom.\n"))
        assertTrue(TextRules.startsSentence("Salom. "))
        assertTrue(TextRules.startsSentence("Qalay? "))
        assertTrue(TextRules.startsSentence("Zo'r! "))
    }

    @Test fun midSentence() {
        assertFalse(TextRules.startsSentence("Salom"))
        assertFalse(TextRules.startsSentence("Salom "))
        assertFalse(TextRules.startsSentence("Salom."))
    }

    @Test fun doubleSpaceAfterAWordWithinTheWindow() {
        assertTrue(TextRules.isDoubleSpace("salom ", 200))
        assertTrue(TextRules.isDoubleSpace("5 ", 100))
    }

    @Test fun notADoubleSpace() {
        assertFalse(TextRules.isDoubleSpace("salom ", null))
        assertFalse(TextRules.isDoubleSpace("salom ", 350))
        assertFalse(TextRules.isDoubleSpace("salom", 100))
        assertFalse(TextRules.isDoubleSpace("salom. ", 100))
        assertFalse(TextRules.isDoubleSpace(" ", 100))
    }
}
