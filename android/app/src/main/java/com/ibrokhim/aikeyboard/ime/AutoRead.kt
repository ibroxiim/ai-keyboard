package com.ibrokhim.aikeyboard.ime

import com.ibrokhim.aikeyboard.data.SharedState

/** When the keyboard may read a chat on its own — an opt-in setting, only in messengers, never twice. */
object AutoRead {
    val MESSENGERS = setOf(
        "com.instagram.android",
        "org.telegram.messenger",
        "com.whatsapp",
        "com.facebook.orca",
        "com.snapchat.android",
        "com.discord",
        "jp.naver.line.android",
        "com.kakao.talk",
    )

    /**
     * Set on the in-app demo chat's field (EditorInfo.privateImeOptions). Allowing the whole app package
     * would also auto-read its settings screen and send that to Gemini.
     */
    const val DEMO_CHAT_OPTION = "com.ibrokhim.aikeyboard.demoChat"

    fun eligible(packageName: String?, inputType: Int, enabled: Boolean, privateImeOptions: String? = null): Boolean {
        if (!enabled || !EditorRules.isChatField(inputType)) return false
        return packageName in MESSENGERS || privateImeOptions?.contains(DEMO_CHAT_OPTION) == true
    }

    /** An unchanged chat whose analysis is still on screen is not sent to Gemini again. */
    fun isNew(hash: String, state: SharedState, now: Long): Boolean =
        !(hash == state.lastReadHash && state.freshContext(now) != null)
}
