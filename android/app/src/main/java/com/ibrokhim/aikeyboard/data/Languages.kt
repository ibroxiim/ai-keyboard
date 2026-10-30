package com.ibrokhim.aikeyboard.data

object Languages {
    data class Entry(val name: String, val flag: String)

    /** What the keyboard's chip row offers until the user edits the list in the app. The first ten of [catalog]. */
    val defaults = listOf(
        "English", "Korean", "Russian", "Turkish", "Japanese", "Chinese",
        "Arabic", "German", "Spanish", "French",
    )

    /** Kept for callers that predate the editable list. */
    val common: List<String> get() = defaults

    /**
     * What the app offers to add. Names are in English because they go to the model as the target language;
     * anything else can still be typed in by hand.
     */
    val catalog = listOf(
        Entry("English", "🇬🇧"), Entry("Korean", "🇰🇷"), Entry("Russian", "🇷🇺"), Entry("Turkish", "🇹🇷"),
        Entry("Japanese", "🇯🇵"), Entry("Chinese", "🇨🇳"), Entry("Arabic", "🇸🇦"), Entry("German", "🇩🇪"),
        Entry("Spanish", "🇪🇸"), Entry("French", "🇫🇷"), Entry("Italian", "🇮🇹"), Entry("Portuguese", "🇵🇹"),
        Entry("Hindi", "🇮🇳"), Entry("Indonesian", "🇮🇩"), Entry("Kazakh", "🇰🇿"), Entry("Uzbek", "🇺🇿"),
        Entry("Kyrgyz", "🇰🇬"), Entry("Tajik", "🇹🇯"), Entry("Turkmen", "🇹🇲"), Entry("Azerbaijani", "🇦🇿"),
        Entry("Ukrainian", "🇺🇦"), Entry("Polish", "🇵🇱"), Entry("Dutch", "🇳🇱"), Entry("Swedish", "🇸🇪"),
        Entry("Czech", "🇨🇿"), Entry("Romanian", "🇷🇴"), Entry("Greek", "🇬🇷"), Entry("Hebrew", "🇮🇱"),
        Entry("Persian", "🇮🇷"), Entry("Urdu", "🇵🇰"), Entry("Bengali", "🇧🇩"), Entry("Thai", "🇹🇭"),
        Entry("Vietnamese", "🇻🇳"), Entry("Malay", "🇲🇾"), Entry("Filipino", "🇵🇭"), Entry("Georgian", "🇬🇪"),
        Entry("Armenian", "🇦🇲"),
    )

    private val flags = catalog.associate { it.name.lowercase() to it.flag }

    fun flag(language: String): String = flags[language.lowercase()] ?: "🌐"

    /**
     * A language as typed → how it is stored: "  korean " → "Korean", "old english" → "Old English". Null when
     * there is nothing usable. The rest of each word is left as typed: a name outside the catalog is not ours to fix.
     */
    fun normalized(input: String): String? {
        val words = input.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.isEmpty()) return null
        val text = words.joinToString(" ")
        if (text.length > 30) return null
        catalog.firstOrNull { it.name.equals(text, ignoreCase = true) }?.let { return it.name }
        return words.joinToString(" ") { it.replaceFirstChar { c -> c.uppercaseChar() } }
    }

    /** [list] plus [input] at the end; unchanged when [input] is blank or already there (in any letter case). */
    fun adding(input: String, list: List<String>): List<String> {
        val language = normalized(input) ?: return list
        if (list.any { it.equals(language, ignoreCase = true) }) return list
        return list + language
    }

    /** Catalog entries not in [list] yet, in catalog order. */
    fun addable(list: List<String>): List<Entry> =
        catalog.filter { entry -> list.none { it.equals(entry.name, ignoreCase = true) } }
}
