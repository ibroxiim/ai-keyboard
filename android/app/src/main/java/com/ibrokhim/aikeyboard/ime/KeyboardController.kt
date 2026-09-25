package com.ibrokhim.aikeyboard.ime

/** What the controller types into. `AiKeyboardService` backs it with the current `InputConnection`. */
interface InputTarget {
    fun textBeforeCursor(length: Int): String
    fun commit(text: String)
    fun deleteBackward()
    fun moveCursor(offset: Int)
    fun enter()
    fun switchKeyboard()

    /** The whole field — in a DM that is just the draft. */
    fun currentText(): String

    /** Replaces the whole field: a picked reply or ✨ variant replaces the draft. */
    fun replaceAll(text: String)

    /** False for passwords, emails, URLs and fields that do not ask for capitals. */
    val autoCapitalize: Boolean
}

/** Keyboard state and typing behaviour — the Android counterpart of the iOS `KeyboardModel`. */
class KeyboardController(
    private val target: InputTarget,
    private val clock: () -> Long,
    initialAlphabet: Alphabet = Alphabet.LATIN,
) {
    var layer = Layer.LETTERS
        private set
    var shift = ShiftState.OFF
        private set
    var alphabet = initialAlphabet
        private set
    var showsGlobe = false
    var emojiKey = false

    /** Called after every state change the keys should redraw for. */
    var onChange: () -> Unit = {}

    private var lastSpaceAt: Long? = null
    private var lastShiftAt: Long? = null

    /** With the emoji key there is no way back from Cyrillic, so it implies Latin (as on iOS). */
    val config: KeysConfig
        get() = KeysConfig(layer, if (emojiKey) Alphabet.LATIN else alphabet, showsGlobe, emojiKey)

    fun press(key: Key) {
        when (key) {
            is Key.Text -> type(key.value)
            Key.Space -> space()
            Key.Backspace -> {
                target.deleteBackward()
                autoCapitalize()
            }
            Key.Enter -> {
                target.enter()
                autoCapitalize()
            }
            Key.Shift -> tapShift()
            Key.AlphabetToggle -> {
                alphabet = if (alphabet == Alphabet.LATIN) Alphabet.CYRILLIC else Alphabet.LATIN
                onChange()
            }
            Key.Globe -> target.switchKeyboard()
            Key.Emoji -> Unit // the emoji panel arrives in milestone 4
            is Key.LayerSwitch -> setLayer(key.layer)
        }
    }

    fun moveCursor(offset: Int) = target.moveCursor(offset)

    fun setLayer(value: Layer) {
        if (layer != value) {
            layer = value
            onChange()
        }
        autoCapitalize()
    }

    fun autoCapitalize() {
        if (layer != Layer.LETTERS || shift == ShiftState.LOCKED) return
        if (!target.autoCapitalize) {
            setShift(ShiftState.OFF)
            return
        }
        val startsSentence = TextRules.startsSentence(target.textBeforeCursor(64))
        setShift(if (startsSentence) ShiftState.ONCE else ShiftState.OFF)
    }

    private fun type(text: String) {
        target.commit(if (shift == ShiftState.OFF) text else text.uppercase())
        if (shift == ShiftState.ONCE) setShift(ShiftState.OFF)
        autoCapitalize()
    }

    private fun space() {
        val now = clock()
        val before = target.textBeforeCursor(2)
        if (TextRules.isDoubleSpace(before, lastSpaceAt?.let { now - it })) {
            target.deleteBackward()
            target.commit(". ")
            lastSpaceAt = null
        } else {
            target.commit(" ")
            lastSpaceAt = now
        }
        setLayer(Layer.LETTERS)
    }

    private fun tapShift() {
        val now = clock()
        val last = lastShiftAt
        if (last != null && now - last < TextRules.DOUBLE_SHIFT_WINDOW_MS) {
            setShift(ShiftState.LOCKED)
        } else {
            setShift(if (shift == ShiftState.OFF) ShiftState.ONCE else ShiftState.OFF)
        }
        lastShiftAt = now
    }

    private fun setShift(value: ShiftState) {
        if (shift != value) {
            shift = value
            onChange()
        }
    }
}
