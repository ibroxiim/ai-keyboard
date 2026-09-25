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
        "com.ibrokhim.aikeyboard", // the in-app demo chat
    )

    fun eligible(packageName: String?, inputType: Int, enabled: Boolean): Boolean =
        enabled && packageName in MESSENGERS && EditorRules.isChatField(inputType)

    /** An unchanged chat whose analysis is still on screen is not sent to Gemini again. */
    fun isNew(hash: String, state: SharedState, now: Long): Boolean =
        !(hash == state.lastReadHash && state.freshContext(now) != null)
}
