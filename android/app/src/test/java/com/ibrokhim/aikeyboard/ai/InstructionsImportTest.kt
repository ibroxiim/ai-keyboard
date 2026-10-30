package com.ibrokhim.aikeyboard.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class InstructionsImportTest {
    @Test fun utf8FileComesBackTrimmedWithUnixLineEndings() {
        assertEquals("# Uslub\n\nOddiy yoz.", InstructionsImport.text("\n# Uslub\r\n\r\nOddiy yoz.\n\n".toByteArray()))
    }

    @Test fun byteOrderMarksAreHandled() {
        assertEquals("salom", InstructionsImport.text(byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + "salom".toByteArray()))
        assertEquals("salom dunyo", InstructionsImport.text("salom dunyo".toByteArray(Charsets.UTF_16)))
    }

    @Test fun aLongFileIsCutAtTheLimit() {
        assertEquals(Prompts.STYLE_LIMIT, InstructionsImport.text("a".repeat(Prompts.STYLE_LIMIT + 500).toByteArray())?.length)
    }

    @Test fun garbageAndEmptyFilesAreRefused() {
        assertNull(InstructionsImport.text(byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)))
        assertNull(InstructionsImport.text(ByteArray(0)))
        assertNull(InstructionsImport.text("  \n ".toByteArray()))
    }
}
