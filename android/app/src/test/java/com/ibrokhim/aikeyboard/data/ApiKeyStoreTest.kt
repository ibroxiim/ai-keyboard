package com.ibrokhim.aikeyboard.data

import org.junit.Assert.assertEquals
import org.junit.Test

class ApiKeyStoreTest {
    @Test fun theUsersKeyWins() {
        assertEquals("user", ApiKeyStore.resolveKey(" user ", "build"))
    }

    @Test fun buildKeyIsTheFallbackAndReleaseHasNone() {
        assertEquals("build", ApiKeyStore.resolveKey(null, "build"))
        assertEquals("build", ApiKeyStore.resolveKey("   ", "build"))
        assertEquals("", ApiKeyStore.resolveKey(null, ""))
    }
}
