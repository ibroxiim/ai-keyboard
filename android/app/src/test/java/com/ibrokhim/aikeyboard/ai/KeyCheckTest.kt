package com.ibrokhim.aikeyboard.ai

import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyCheckTest {
    @Test fun googleRefusingTheKeyMeansDoNotSave() {
        for (code in listOf(400, 401, 403)) {
            val outcome = KeyCheck.outcomeOf(GeminiException.Http(code, "API key not valid"))
            assertEquals(KeyCheck.Outcome.Rejected(KeyCheck.REJECTED), outcome)
            assertFalse(outcome.shouldSave)
        }
        assertFalse(KeyCheck.outcomeOf(GeminiException.MissingKey()).shouldSave)
    }

    @Test fun anythingUncertainStillSavesButSaysSo() {
        assertEquals(KeyCheck.Outcome.Valid, KeyCheck.outcomeOf(null))
        val quota = KeyCheck.outcomeOf(GeminiException.Http(429, "quota"))
        assertEquals(KeyCheck.Outcome.Unverified("Gemini 429: quota"), quota)
        assertTrue(quota.shouldSave)
        val offline = KeyCheck.outcomeOf(GeminiException.Network(IOException("down")))
        assertTrue(offline is KeyCheck.Outcome.Unverified)
        assertTrue(offline.shouldSave)
    }
}
