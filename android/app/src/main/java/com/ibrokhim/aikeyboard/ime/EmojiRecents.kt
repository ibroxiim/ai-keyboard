package com.ibrokhim.aikeyboard.ime

/** Recently used emoji, most recent first. Storage is injected so the rule stays testable. */
class EmojiRecents(private val load: () -> List<String>, private val save: (List<String>) -> Unit) {
    val all: List<String> get() = load()

    fun add(emoji: String) {
        save((listOf(emoji) + load().filter { it != emoji }).take(LIMIT))
    }

    companion object {
        const val LIMIT = 32
    }
}
