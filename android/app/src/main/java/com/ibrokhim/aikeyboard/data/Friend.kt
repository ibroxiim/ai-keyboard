package com.ibrokhim.aikeyboard.data

import java.text.Normalizer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Friend(
    val name: String,
    val language: String,
    val tone: String,
    /** Epoch milliseconds. */
    val lastSeen: Long,
    /** How formal ✨ writes to this friend when the user decided it, instead of the model guessing from the chat. */
    val formality: Formality? = null,
    /**
     * What was said in this chat, collected from chat reads (see [ChatHistory]); null when the user turned chat
     * memory off. Stays on the device; only ✨ sends it, and only for this friend.
     */
    val history: List<ChatLine>? = null,
    /** What the user wrote about this person for the model: who they are, how to translate and reply for them. */
    val notes: String? = null,
    /** ✨ variants the user changed before sending, for the model to learn their taste (see [EditLearning]). */
    val examples: List<Example>? = null,
) {
    @Serializable
    enum class Formality {
        @SerialName("informal") INFORMAL,
        @SerialName("formal") FORMAL;

        val label: String get() = if (this == INFORMAL) "Norasmiy" else "Rasmiy"
        /** For the prompt. */
        val word: String get() = name.lowercase()
    }

    /** One correction: what the user wrote in Uzbek, what ✨ offered, what they actually sent. */
    @Serializable
    data class Example(val draft: String, val suggested: String, val sent: String)

    /** Keeps the newest [EditLearning.LIMIT] examples, newest last. */
    fun learn(example: Example): Friend {
        val list = examples.orEmpty().filterNot { it == example } + example
        return copy(examples = list.takeLast(EditLearning.LIMIT))
    }

    companion object {
        /**
         * The model reads the name off each screen, so the same person comes back as "Christi..."
         * (truncated), "Christima" (misread), "christina 🌸" or "christina.lee". Compare letters and
         * digits only; a name that is the start of the other is the same person, and from 6 letters on
         * one misread, missing or extra letter is tolerated (not below: Maria ≠ Marta).
         */
        fun isSamePerson(a: String, b: String): Boolean {
            val x = key(a)
            val y = key(b)
            if (x.isEmpty() || y.isEmpty()) return false
            if (x == y) return true
            val (short, long) = if (x.length < y.length) x to y else y to x
            if (short.length < 4) return false
            if (long.startsWith(short)) return true
            return short.length >= 6 && prefixEditDistance(short, long) <= 1
        }

        /** Edit distance between `short` and the closest-length prefix of `long` (truncation is free). */
        private fun prefixEditDistance(short: String, long: String): Int {
            var row = IntArray(long.length + 1) { it }
            for (i in 1..short.length) {
                val next = IntArray(long.length + 1)
                next[0] = i
                for (j in 1..long.length) {
                    val cost = if (short[i - 1] == long[j - 1]) 0 else 1
                    next[j] = minOf(row[j] + 1, next[j - 1] + 1, row[j - 1] + cost)
                }
                row = next
            }
            val n = short.length
            return (maxOf(0, n - 1)..minOf(long.length, n + 1)).minOf { row[it] }
        }

        /** Lowercase letters and digits with accents stripped; Hangul and other scripts are kept. */
        fun key(name: String): String {
            val decomposed = Normalizer.normalize(name.lowercase(), Normalizer.Form.NFD)
            return Normalizer.normalize(decomposed.filter { it.isLetterOrDigit() }, Normalizer.Form.NFC)
        }

        /** Of several spellings, keep the most complete one. */
        fun bestName(names: List<String>): String =
            names.map { it.trim(' ', '.', '…') }.maxByOrNull { key(it).length }.orEmpty()
    }
}
