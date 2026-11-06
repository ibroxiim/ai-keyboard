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

    @Test fun pastedKeysLoseSpacesAndLineBreaks() {
        assertEquals("AIzaSy-12_3", ApiKeyStore.normalize("  AIza Sy-12_3\n"))
        assertEquals(null, ApiKeyStore.normalize(" \n\t "))
        assertEquals(null, ApiKeyStore.normalize(null))
    }

    @Test fun maskingShowsOnlyTheLastFour() {
        assertEquals("••••wxyz", ApiKeyStore.masked("AIzaSyABCDwxyz"))
        assertEquals("•••", ApiKeyStore.masked("abc"))
    }
}
