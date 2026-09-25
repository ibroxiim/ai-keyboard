package com.ibrokhim.aikeyboard.ime

enum class Layer { LETTERS, NUMBERS, SYMBOLS }

enum class Alphabet { LATIN, CYRILLIC }

enum class ShiftState { OFF, ONCE, LOCKED }

sealed interface Key {
    data class Text(val value: String) : Key
    data object Shift : Key
    data object Backspace : Key
    data object Globe : Key
    data object Space : Key
    data object Enter : Key
    /** КИР/LAT. */
    data object AlphabetToggle : Key
    /** Replaces КИР/LAT when the emoji-key setting is on (panel arrives in milestone 4). */
    data object Emoji : Key
    data class LayerSwitch(val layer: Layer, val label: String) : Key
}

data class KeysConfig(
    val layer: Layer,
    val alphabet: Alphabet,
    val showsGlobe: Boolean,
    val emojiKey: Boolean,
)

/** A key and its width in pixels. Keys in a row are separated by the layout's gap. */
data class PlacedKey(val key: Key, val width: Float)

/** Same tables and width arithmetic as the iOS `KeysUIView`. */
object KeyLayouts {
    private val latin = listOf(
        listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"),
        listOf("a", "s", "d", "f", "g", "h", "j", "k", "l"),
        listOf("z", "x", "c", "v", "b", "n", "m"),
    )

    /** Uzbek Cyrillic on the ЙЦУКЕН base; ғ and ҳ sit in the bottom row, like oʻ/gʻ in Latin. */
    private val cyrillic = listOf(
        listOf("й", "ц", "у", "к", "е", "н", "г", "ш", "ў", "з", "х", "ъ"),
        listOf("ф", "қ", "в", "а", "п", "р", "о", "л", "д", "ж", "э"),
        listOf("я", "ч", "с", "м", "и", "т", "ь", "б", "ю"),
    )
    private val numbers = listOf(
        listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"),
        listOf("-", "/", ":", ";", "(", ")", "$", "&", "@", "\""),
    )
    private val symbols = listOf(
        listOf("[", "]", "{", "}", "#", "%", "^", "*", "+", "="),
        listOf("_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"),
    )
    private val punctuation = listOf(".", ",", "?", "!", "'")

    private fun extras(alphabet: Alphabet) =
        if (alphabet == Alphabet.LATIN) listOf("oʻ", "gʻ") else listOf("ғ", "ҳ")

    fun rows(config: KeysConfig, width: Float, gap: Float, sideInset: Float): List<List<PlacedKey>> {
        val full = width - sideInset * 2
        val baseUnit = (full - gap * 9) / 10
        val rows = mutableListOf<List<PlacedKey>>()

        when (config.layer) {
            Layer.LETTERS -> {
                val letters = if (config.alphabet == Alphabet.LATIN) latin else cyrillic
                val columns = letters[0].size
                val unit = (full - gap * (columns - 1)) / columns
                val bottomLetters = letters[2].size
                val side = (full - unit * bottomLetters - gap * (bottomLetters + 1)) / 2
                rows.add(letters[0].map { PlacedKey(Key.Text(it), unit) })
                rows.add(letters[1].map { PlacedKey(Key.Text(it), unit) })
                rows.add(
                    listOf(PlacedKey(Key.Shift, side)) +
                        letters[2].map { PlacedKey(Key.Text(it), unit) } +
                        PlacedKey(Key.Backspace, side),
                )
            }
            Layer.NUMBERS, Layer.SYMBOLS -> {
                val chars = if (config.layer == Layer.NUMBERS) numbers else symbols
                val toggle = if (config.layer == Layer.NUMBERS) {
                    Key.LayerSwitch(Layer.SYMBOLS, "#+=")
                } else {
                    Key.LayerSwitch(Layer.NUMBERS, "123")
                }
                val side = baseUnit * 1.5f + gap / 2
                val punctuationWidth = (full - side * 2 - gap * 6) / 5
                rows.add(chars[0].map { PlacedKey(Key.Text(it), baseUnit) })
                rows.add(chars[1].map { PlacedKey(Key.Text(it), baseUnit) })
                rows.add(
                    listOf(PlacedKey(toggle, side)) +
                        punctuation.map { PlacedKey(Key.Text(it), punctuationWidth) } +
                        PlacedKey(Key.Backspace, side),
                )
            }
        }

        val bottom = mutableListOf<PlacedKey>()
        val layerKey = if (config.layer == Layer.LETTERS) {
            Key.LayerSwitch(Layer.NUMBERS, "123")
        } else {
            Key.LayerSwitch(Layer.LETTERS, "ABC")
        }
        bottom.add(PlacedKey(layerKey, baseUnit * 1.25f))
        if (config.showsGlobe) bottom.add(PlacedKey(Key.Globe, baseUnit * 1.1f))
        if (config.layer == Layer.LETTERS) {
            bottom.add(PlacedKey(if (config.emojiKey) Key.Emoji else Key.AlphabetToggle, baseUnit * 1.25f))
            extras(config.alphabet).forEach { bottom.add(PlacedKey(Key.Text(it), baseUnit)) }
        }
        val enterWidth = baseUnit * 2
        val used = bottom.sumOf { it.width.toDouble() }.toFloat() + enterWidth + gap * (bottom.size + 1)
        bottom.add(PlacedKey(Key.Space, maxOf(baseUnit * 2, full - used)))
        bottom.add(PlacedKey(Key.Enter, enterWidth))
        rows.add(bottom)
        return rows
    }
}
