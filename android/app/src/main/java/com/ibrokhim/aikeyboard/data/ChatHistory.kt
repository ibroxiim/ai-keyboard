package com.ibrokhim.aikeyboard.data

/**
 * A friend's chat as far as the chat reads have shown it. Each read shows a screenful; consecutive ones overlap,
 * so the new screenful is joined to the saved history at the place they agree.
 */
object ChatHistory {
    /** Messages kept per friend, oldest dropped first. */
    const val LIMIT = 40

    /** One short line ("ok", "lol") is in every chat, so it cannot tell where two reads meet. */
    private const val MIN_ANCHOR = 8

    /**
     * [old] (oldest first) extended with the screenful [new]. The overlap is searched from the newest end of
     * [old]; a screenful wholly inside [old] (scrolled up) adds nothing; without any overlap [new] is taken to be
     * the newer one — the usual case for a read days later.
     */
    fun merged(old: List<ChatLine>, new: List<ChatLine>): List<ChatLine> {
        if (new.isEmpty()) return capped(old)
        if (old.isEmpty()) return capped(new)
        for (start in old.indices.reversed()) {
            val overlap = minOf(old.size - start, new.size)
            if (!anchors(overlap, new)) continue
            if ((0 until overlap).any { !same(old[start + it], new[it]) }) continue
            val result = old.subList(0, start) +
                (0 until overlap).map { fuller(old[start + it], new[it]) } +
                old.subList(start + overlap, old.size) +
                new.subList(overlap, new.size)
            return capped(result)
        }
        return capped(old + new)
    }

    private fun capped(lines: List<ChatLine>) = lines.takeLast(LIMIT)

    private fun anchors(overlap: Int, new: List<ChatLine>) = overlap >= 2 || key(new[0].text).length >= MIN_ANCHOR

    /**
     * Same sender, and the same words up to letter case and punctuation. A bubble cut off by the top of the
     * screen shows only the end of its text, so one that is the start or end of the other counts too.
     */
    private fun same(a: ChatLine, b: ChatLine): Boolean {
        if (a.from != b.from) return false
        val x = key(a.text)
        val y = key(b.text)
        if (x == y) return true
        val (short, long) = if (x.length < y.length) x to y else y to x
        return short.length >= MIN_ANCHOR && (long.startsWith(short) || long.endsWith(short))
    }

    private fun fuller(a: ChatLine, b: ChatLine) = if (key(b.text).length > key(a.text).length) b else a

    /** Letters and digits, lower-cased; a message of only emoji or punctuation falls back to its own text. */
    private fun key(text: String): String {
        val letters = text.lowercase().filter { it.isLetterOrDigit() }
        return letters.ifEmpty { text.trim() }
    }
}
