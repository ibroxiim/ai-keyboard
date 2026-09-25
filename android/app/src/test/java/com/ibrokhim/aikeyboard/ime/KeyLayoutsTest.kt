package com.ibrokhim.aikeyboard.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyLayoutsTest {
    private val width = 1080f
    private val gap = 18f
    private val side = 12f
    private val full = width - side * 2

    private fun rows(
        layer: Layer = Layer.LETTERS,
        alphabet: Alphabet = Alphabet.LATIN,
        globe: Boolean = false,
        emoji: Boolean = false,
    ) = KeyLayouts.rows(KeysConfig(layer, alphabet, globe, emoji), width, gap, side)

    private fun rowWidth(row: List<PlacedKey>) = row.sumOf { it.width.toDouble() }.toFloat() + gap * (row.size - 1)

    private fun texts(row: List<PlacedKey>) = row.mapNotNull { (it.key as? Key.Text)?.value }

    @Test fun latinLettersFollowQwerty() {
        val r = rows()
        assertEquals(4, r.size)
        assertEquals(listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"), texts(r[0]))
        assertEquals(Key.Shift, r[2].first().key)
        assertEquals(Key.Backspace, r[2].last().key)
    }

    @Test fun fullRowsFillTheWidthAndNoRowOverflows() {
        for (layer in Layer.entries) for (alphabet in Alphabet.entries) {
            val r = rows(layer, alphabet)
            assertEquals(full, rowWidth(r[0]), 0.5f)
            assertEquals(full, rowWidth(r[2]), 0.5f)
            assertEquals(full, rowWidth(r[3]), 0.5f)
            r.forEach { assertTrue(rowWidth(it) <= full + 0.5f) }
        }
    }

    @Test fun bottomRowHasAlphabetToggleAndUzbekLetters() {
        val bottom = rows().last()
        assertEquals(Key.LayerSwitch(Layer.NUMBERS, "123"), bottom[0].key)
        assertEquals(Key.AlphabetToggle, bottom[1].key)
        assertEquals(listOf("oʻ", "gʻ"), texts(bottom))
        assertEquals(Key.Space, bottom[bottom.size - 2].key)
        assertEquals(Key.Enter, bottom.last().key)
    }

    @Test fun cyrillicHasTwelveColumnsAndItsOwnExtras() {
        val r = rows(alphabet = Alphabet.CYRILLIC)
        assertEquals(12, r[0].size)
        assertEquals(listOf("ғ", "ҳ"), texts(r.last()))
    }

    @Test fun emojiKeyReplacesAlphabetToggle() {
        assertEquals(Key.Emoji, rows(emoji = true).last()[1].key)
    }

    @Test fun globeAppearsOnlyWhenAsked() {
        assertTrue(rows(globe = true).last().any { it.key == Key.Globe })
        assertTrue(rows().last().none { it.key == Key.Globe })
    }

    @Test fun numberLayersToggleEachOtherAndReturnToLetters() {
        val numbers = rows(Layer.NUMBERS)
        assertEquals(Key.LayerSwitch(Layer.SYMBOLS, "#+="), numbers[2].first().key)
        assertEquals(listOf(".", ",", "?", "!", "'"), texts(numbers[2]))
        assertEquals(Key.LayerSwitch(Layer.LETTERS, "ABC"), numbers.last().first().key)
        assertEquals(Key.LayerSwitch(Layer.NUMBERS, "123"), rows(Layer.SYMBOLS)[2].first().key)
    }
}
