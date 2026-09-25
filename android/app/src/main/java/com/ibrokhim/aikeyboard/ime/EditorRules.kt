package com.ibrokhim.aikeyboard.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo

enum class EnterAction(val glyph: String) {
    NEWLINE("⏎"), SEND("➤"), GO("→"), SEARCH("⌕"), NEXT("⇥"), DONE("✓"), PREVIOUS("⇤"),
}

/** Reads what the focused field asks for from its `EditorInfo` bits. */
object EditorRules {
    fun enterAction(imeOptions: Int): EnterAction {
        if ((imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0) return EnterAction.NEWLINE
        return when (imeOptions and EditorInfo.IME_MASK_ACTION) {
            EditorInfo.IME_ACTION_SEND -> EnterAction.SEND
            EditorInfo.IME_ACTION_GO -> EnterAction.GO
            EditorInfo.IME_ACTION_SEARCH -> EnterAction.SEARCH
            EditorInfo.IME_ACTION_NEXT -> EnterAction.NEXT
            EditorInfo.IME_ACTION_DONE -> EnterAction.DONE
            EditorInfo.IME_ACTION_PREVIOUS -> EnterAction.PREVIOUS
            else -> EnterAction.NEWLINE
        }
    }

    fun imeAction(action: EnterAction): Int? = when (action) {
        EnterAction.NEWLINE -> null
        EnterAction.SEND -> EditorInfo.IME_ACTION_SEND
        EnterAction.GO -> EditorInfo.IME_ACTION_GO
        EnterAction.SEARCH -> EditorInfo.IME_ACTION_SEARCH
        EnterAction.NEXT -> EditorInfo.IME_ACTION_NEXT
        EnterAction.DONE -> EditorInfo.IME_ACTION_DONE
        EnterAction.PREVIOUS -> EditorInfo.IME_ACTION_PREVIOUS
    }

    private val noCapsVariations = setOf(
        InputType.TYPE_TEXT_VARIATION_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
        InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
        InputType.TYPE_TEXT_VARIATION_URI,
    )

    /** Only text fields that ask for capitals get them, like the system keyboard. */
    fun autoCapitalize(inputType: Int): Boolean {
        if ((inputType and InputType.TYPE_MASK_CLASS) != InputType.TYPE_CLASS_TEXT) return false
        if ((inputType and InputType.TYPE_MASK_VARIATION) in noCapsVariations) return false
        val caps = InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or
            InputType.TYPE_TEXT_FLAG_CAP_WORDS or
            InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
        return (inputType and caps) != 0
    }
}
