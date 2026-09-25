package com.ibrokhim.aikeyboard.ime

import java.text.BreakIterator

/** Typing conventions shared with the iOS keyboard (`KeyboardModel.autoCapitalize` / `space`). */
object TextRules {
    const val DOUBLE_SPACE_WINDOW_MS = 350L
    const val DOUBLE_SHIFT_WINDOW_MS = 300L

    /** The next letter starts a sentence: empty field, a new line, or right after ". ", "! ", "? ". */
    fun startsSentence(before: String): Boolean {
        val trimmed = before.trimEnd(' ')
        if (trimmed.isEmpty() || before.endsWith("\n")) return true
        return trimmed.last() in ".!?" && before.endsWith(" ")
    }

    /** A second space soon after the first, right after a word, becomes ". " like the system keyboard. */
    fun isDoubleSpace(before: String, msSinceLastSpace: Long?): Boolean {
        if (msSinceLastSpace == null || msSinceLastSpace >= DOUBLE_SPACE_WINDOW_MS) return false
        if (!before.endsWith(" ")) return false
        val previous = before.dropLast(1).lastOrNull() ?: return false
        return previous.isLetterOrDigit()
    }

    /** UTF-16 length of the last user-perceived character, so backspace removes a whole emoji or flag. */
    fun lastGraphemeLength(before: String): Int {
        if (before.isEmpty()) return 0
        val iterator = BreakIterator.getCharacterInstance()
        iterator.setText(before)
        val end = iterator.last()
        return end - iterator.previous()
    }
}
