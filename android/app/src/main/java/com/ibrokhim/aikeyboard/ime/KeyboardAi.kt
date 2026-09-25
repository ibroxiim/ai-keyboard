package com.ibrokhim.aikeyboard.ime

import com.ibrokhim.aikeyboard.ai.ChatInput

/** Where the keyboard gets the chat from. The Android side is the accessibility service. */
interface ChatSource {
    /** False while the chat reader service is switched off. */
    val available: Boolean

    /** The chat in [packageName]'s window, or null if nothing readable is on screen. */
    suspend fun read(packageName: String): ChatInput?
}
