package com.ibrokhim.aikeyboard.data

/**
 * What the keyboard learns when the user changes a ✨ variant before sending it. The Gemini chat the user
 * compares us to got better over years of such corrections; here they are kept per friend and shown to the model.
 */
object EditLearning {
    /** Examples kept per friend, oldest dropped first. */
    const val LIMIT = 20
    /** Examples that go to the model with a rewrite. */
    const val PROMPT_LIMIT = 10

    /**
     * The example a sent message makes, or null when there is nothing to learn from it: the user sent the
     * variant as it was, or the field only showed part of it (a prefix or a suffix of the variant is not an edit).
     */
    fun example(draft: String, picked: String, sent: String): Friend.Example? {
        val sentText = sent.trim()
        val pickedText = picked.trim()
        if (sentText.length < 2 || pickedText == sentText) return null
        if (pickedText.startsWith(sentText) || pickedText.endsWith(sentText)) return null
        return Friend.Example(draft.trim(), pickedText, sentText)
    }
}
