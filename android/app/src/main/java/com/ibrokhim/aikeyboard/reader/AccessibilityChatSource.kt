package com.ibrokhim.aikeyboard.reader

import com.ibrokhim.aikeyboard.ai.ChatInput
import com.ibrokhim.aikeyboard.ime.ChatSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Text first (fast, cheap, exact); a screenshot only when the app shows no readable bubbles. */
class AccessibilityChatSource : ChatSource {
    override val available: Boolean
        get() = ChatReaderService.instance != null

    override suspend fun read(packageName: String): ChatInput? {
        val service = ChatReaderService.instance ?: return null
        val lines = withContext(Dispatchers.Default) { service.readLines(packageName) }
        if (lines != null && ChatLines.hasMessages(lines)) return ChatInput.Transcript(lines)
        val jpeg = service.screenshotJpeg() ?: return null
        return ChatInput.Screenshot(jpeg)
    }
}
