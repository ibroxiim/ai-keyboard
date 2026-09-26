package com.ibrokhim.aikeyboard.ime

import org.junit.Assert.assertEquals
import org.junit.Test

class KeyboardControllerTest {
    private class FakeTarget : InputTarget {
        val text = StringBuilder()
        var enters = 0
        var switches = 0
        override var autoCapitalize = true
        override fun textBeforeCursor(length: Int) = text.takeLast(length).toString()
        override fun commit(text: String) {
            this.text.append(text)
        }
        override fun deleteBackward() {
            if (text.isNotEmpty()) text.deleteCharAt(text.length - 1)
        }
        override fun moveCursor(offset: Int) = Unit
        override fun enter() {
            enters++
        }
        override fun switchKeyboard() {
            switches++
        }
        override fun currentText() = text.toString()
        override fun replaceAll(text: String) {
            this.text.clear()
            this.text.append(text)
        }
    }

    private var now = 10_000L
    private val target = FakeTarget()
    private val controller = KeyboardController(target, { now })

    private fun type(word: String) = word.forEach { controller.press(Key.Text(it.toString())) }

    @Test fun capitalisesTheFirstLetterOnly() {
        controller.autoCapitalize()
        type("salom")
        assertEquals("Salom", target.text.toString())
    }

    @Test fun capitalisesAfterAFullStop() {
        controller.autoCapitalize()
        type("salom.")
        controller.press(Key.Space)
        type("qalay")
        assertEquals("Salom. Qalay", target.text.toString())
    }

    @Test fun quickDoubleSpaceBecomesFullStop() {
        controller.autoCapitalize()
        type("salom")
        controller.press(Key.Space)
        now += 200
        controller.press(Key.Space)
        assertEquals("Salom. ", target.text.toString())
        assertEquals(ShiftState.ONCE, controller.shift)
    }

    @Test fun slowDoubleSpaceStaysTwoSpaces() {
        type("salom")
        controller.press(Key.Space)
        now += 1_000
        controller.press(Key.Space)
        assertEquals("salom  ", target.text.toString())
    }

    @Test fun doubleTapShiftLocksCapitals() {
        target.autoCapitalize = false
        controller.press(Key.Shift)
        now += 150
        controller.press(Key.Shift)
        assertEquals(ShiftState.LOCKED, controller.shift)
        type("ok")
        assertEquals("OK", target.text.toString())
    }

    @Test fun uzbekLetterUppercasesWithItsModifier() {
        controller.autoCapitalize()
        controller.press(Key.Text("oʻ"))
        assertEquals("Oʻ", target.text.toString())
    }

    @Test fun fieldsWithoutCapsStayLowercase() {
        target.autoCapitalize = false
        controller.autoCapitalize()
        type("salom")
        assertEquals("salom", target.text.toString())
    }

    @Test fun spaceReturnsFromNumbersToLetters() {
        controller.press(Key.LayerSwitch(Layer.NUMBERS, "123"))
        assertEquals(Layer.NUMBERS, controller.layer)
        controller.press(Key.Space)
        assertEquals(Layer.LETTERS, controller.layer)
    }

    @Test fun alphabetToggleAndEmojiKeyConfig() {
        controller.press(Key.AlphabetToggle)
        assertEquals(Alphabet.CYRILLIC, controller.config.alphabet)
        controller.emojiKey = true
        assertEquals(Alphabet.LATIN, controller.config.alphabet)
    }

    @Test fun enterAndGlobeGoToTheTarget() {
        controller.press(Key.Enter)
        controller.press(Key.Globe)
        assertEquals(1, target.enters)
        assertEquals(1, target.switches)
    }

    @Test fun backspaceDeletes() {
        type("ab")
        controller.press(Key.Backspace)
        assertEquals("a", target.text.toString())
    }

    @Test fun emojiKeyOpensThePanelAndAbcClosesIt() {
        controller.press(Key.Emoji)
        assertEquals(true, controller.showsEmoji)
        controller.closeEmoji()
        assertEquals(false, controller.showsEmoji)
    }

    @Test fun emojiGoesInAsIs() {
        controller.autoCapitalize()
        controller.insertEmoji("😀")
        controller.press(Key.Text("x"))
        assertEquals("😀x", target.text.toString())
    }
}
