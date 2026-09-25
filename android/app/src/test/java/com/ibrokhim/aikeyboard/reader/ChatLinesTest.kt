package com.ibrokhim.aikeyboard.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatLinesTest {
    private val window = WindowBounds(0, 0, 1000, 2000)

    private fun node(text: String, left: Int, top: Int, right: Int, editable: Boolean = false) =
        TextNode(text, left, top, right, top + 60, editable)

    @Test fun tagsHeaderLeftAndRightInReadingOrder() {
        val lines = ChatLines.build(
            listOf(
                node("u free?", 40, 900, 500),
                node("Emma", 100, 100, 300),
                node("yes!", 600, 1000, 960),
                node("hi", 40, 800, 300),
            ),
            window,
        )
        assertEquals(listOf("[TOP] Emma", "[L] hi", "[L] u free?", "[R] yes!"), lines)
    }

    @Test fun draftFieldAndBlankTextAreSkipped() {
        val lines = ChatLines.build(
            listOf(node("hi", 40, 800, 300), node("my draft", 40, 1900, 900, editable = true), node("  ", 40, 850, 300)),
            window,
        )
        assertEquals(listOf("[L] hi"), lines)
    }

    @Test fun consecutiveDuplicatesCollapseAndNewlinesBecomeSpaces() {
        val lines = ChatLines.build(
            listOf(node("see u\nsoon", 600, 800, 960), node("see u soon", 610, 805, 950)),
            window,
        )
        assertEquals(listOf("[R] see u soon"), lines)
    }

    @Test fun keepsTheHeaderAndTheLastFortyMessages() {
        val messages = (1..50).map { node("message $it", 40, 400 + it * 30, 500) }
        val lines = ChatLines.build(listOf(node("Emma", 100, 100, 300)) + messages, window)
        assertEquals(41, lines.size)
        assertEquals("[TOP] Emma", lines.first())
        assertEquals("[L] message 11", lines[1])
        assertEquals("[L] message 50", lines.last())
    }

    @Test fun twoBubblesAreNeededToCountAsAChat() {
        assertTrue(ChatLines.hasMessages(listOf("[TOP] Emma", "[L] hi", "[R] hey")))
        assertFalse(ChatLines.hasMessages(listOf("[TOP] Emma", "[L] hi")))
    }

    @Test fun hashIsStableAndFollowsTheContent() {
        val a = listOf("[TOP] Emma", "[L] hi")
        assertEquals(ChatLines.hash(a), ChatLines.hash(a.toList()))
        assertNotEquals(ChatLines.hash(a), ChatLines.hash(a + "[R] hey"))
    }
}
