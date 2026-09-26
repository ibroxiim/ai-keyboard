package com.ibrokhim.aikeyboard.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SetupStepsTest {
    @Test fun theFirstUnfinishedStepIsCurrent() {
        assertEquals(0, SetupStatus(false, false, false, false).current)
        assertEquals(1, SetupStatus(true, false, true, true).current)
        assertEquals(3, SetupStatus(true, true, true, false).current)
    }

    @Test fun allDone() {
        val status = SetupStatus(true, true, true, true)
        assertNull(status.current)
        assertTrue(status.done)
    }
}
