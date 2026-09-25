package com.ibrokhim.aikeyboard.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorRulesTest {
    @Test fun enterActionFollowsImeOptions() {
        assertEquals(EnterAction.SEND, EditorRules.enterAction(EditorInfo.IME_ACTION_SEND))
        assertEquals(EnterAction.SEARCH, EditorRules.enterAction(EditorInfo.IME_ACTION_SEARCH))
        assertEquals(EnterAction.NEWLINE, EditorRules.enterAction(EditorInfo.IME_ACTION_UNSPECIFIED))
    }

    @Test fun noEnterActionFlagMeansNewline() {
        val options = EditorInfo.IME_ACTION_SEND or EditorInfo.IME_FLAG_NO_ENTER_ACTION
        assertEquals(EnterAction.NEWLINE, EditorRules.enterAction(options))
        assertNull(EditorRules.imeAction(EnterAction.NEWLINE))
        assertEquals(EditorInfo.IME_ACTION_SEND, EditorRules.imeAction(EnterAction.SEND))
    }

    @Test fun capitalisesPlainTextWithACapsFlag() {
        val text = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        assertTrue(EditorRules.autoCapitalize(text))
        assertFalse(EditorRules.autoCapitalize(InputType.TYPE_CLASS_TEXT))
    }

    @Test fun neverCapitalisesPasswordsEmailsUrlsOrNumbers() {
        val caps = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        assertFalse(EditorRules.autoCapitalize(caps or InputType.TYPE_TEXT_VARIATION_PASSWORD))
        assertFalse(EditorRules.autoCapitalize(caps or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS))
        assertFalse(EditorRules.autoCapitalize(caps or InputType.TYPE_TEXT_VARIATION_URI))
        assertFalse(EditorRules.autoCapitalize(InputType.TYPE_CLASS_NUMBER))
    }
}
