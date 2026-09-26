package com.ibrokhim.aikeyboard.data

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class ModelsTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test fun analysisReadsTheSnakeCaseJsonTheModelReturns() {
        val details = json.decodeFromString(
            ChatDetails.serializer(),
            """{"summary_uz":"Emma uchrashuv taklif qilyapti.","transcript":[{"from":"me","text":"hi"},""" +
                """{"from":"them","text":"u free?"},{"from":"them","text":"we could grab food"}],""" +
                """"suggestions":[{"text":"yes!","uz":"ha!"}]}""",
        )
        val quick = QuickRead("Emma...", "English", "casual", "Bo'shmisan?")
        val analysis = ChatAnalysis.of(quick, details)
        assertEquals("Emma", analysis.partner)
        assertEquals("u free? we could grab food", analysis.lastIncoming)
        assertEquals("yes!", analysis.suggestions.single().text)
    }

    @Test fun missingHalvesLeaveEmptyFields() {
        val analysis = ChatAnalysis.of(null, null)
        assertEquals("", analysis.partner)
        assertEquals(emptyList<Suggestion>(), analysis.suggestions)
    }

    @Test fun flags() {
        assertEquals("🇰🇷", Languages.flag("Korean"))
        assertEquals("🌐", Languages.flag("Klingon"))
    }
}
