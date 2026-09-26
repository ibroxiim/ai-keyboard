package com.ibrokhim.aikeyboard.reader

import java.security.MessageDigest

/** One visible piece of text in the chat app's window, in screen pixels. */
data class TextNode(
    val text: String,
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
    val editable: Boolean,
)

data class WindowBounds(val left: Int, val top: Int, val right: Int, val bottom: Int)

/**
 * Turns a chat window's text into the tagged lines the transcript prompt expects: `[TOP]` for the header
 * (the top 15%), `[L]` for text left of the middle (them), `[R]` for the right (me). Timestamps and UI
 * labels are kept on purpose — the model drops them more reliably than a filter per messenger would.
 */
object ChatLines {
    const val MAX_MESSAGE_LINES = 40
    private const val HEADER_SHARE = 0.15

    fun build(nodes: List<TextNode>, window: WindowBounds): List<String> {
        val headerBottom = window.top + (window.bottom - window.top) * HEADER_SHARE
        val middle = (window.left + window.right) / 2.0
        val header = mutableListOf<String>()
        val messages = mutableListOf<String>()
        var previous: String? = null
        val ordered = nodes.filterNot { it.editable }.sortedWith(compareBy({ it.top }, { it.left }))
        for (node in ordered) {
            val text = node.text.replace('\n', ' ').trim()
            // A bubble's container often repeats its child's text as a content description.
            if (text.isEmpty() || text == previous) continue
            previous = text
            when {
                node.bottom <= headerBottom -> header.add("[TOP] $text")
                (node.left + node.right) / 2.0 < middle -> messages.add("[L] $text")
                else -> messages.add("[R] $text")
            }
        }
        return header + messages.takeLast(MAX_MESSAGE_LINES)
    }

    /** At least two bubbles; fewer means the app draws its text where the tree cannot see it. */
    fun hasMessages(lines: List<String>): Boolean = lines.count { !it.startsWith("[TOP]") } >= 2

    fun hash(lines: List<String>): String =
        MessageDigest.getInstance("SHA-256")
            .digest(lines.joinToString("\n").toByteArray())
            .joinToString("") { "%02x".format(it) }
}
