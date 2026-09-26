package com.ibrokhim.aikeyboard.ime

import android.text.InputType
import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.SharedState
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoReadTest {
    private val text = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES

    @Test fun onlyMessengersWithTheSettingOn() {
        assertTrue(AutoRead.eligible("org.telegram.messenger", text, enabled = true))
        assertFalse(AutoRead.eligible("org.telegram.messenger", text, enabled = false))
        assertFalse(AutoRead.eligible("com.android.chrome", text, enabled = true))
        assertFalse(AutoRead.eligible(null, text, enabled = true))
    }

    @Test fun neverInPasswordEmailUrlOrNumberFields() {
        val pkg = "com.whatsapp"
        assertFalse(AutoRead.eligible(pkg, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD, true))
        assertFalse(AutoRead.eligible(pkg, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS, true))
        assertFalse(AutoRead.eligible(pkg, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI, true))
        assertFalse(AutoRead.eligible(pkg, InputType.TYPE_CLASS_NUMBER, true))
    }

    @Test fun unchangedChatWithAFreshContextIsSkipped() {
        val now = 10_000_000L
        val fresh = SharedState(context = ChatAnalysis(partner = "Emma"), contextDate = now, lastReadHash = "h")
        assertFalse(AutoRead.isNew("h", fresh, now))
        assertTrue(AutoRead.isNew("other", fresh, now))
        assertTrue(AutoRead.isNew("h", fresh.copy(contextDate = now - 16 * 60_000), now))
    }

    @Test fun ourOwnAppOnlyInTheMarkedDemoChat() {
        assertFalse(AutoRead.eligible("com.ibrokhim.aikeyboard", text, enabled = true))
        assertTrue(AutoRead.eligible("com.ibrokhim.aikeyboard", text, enabled = true, AutoRead.DEMO_CHAT_OPTION))
    }
}
