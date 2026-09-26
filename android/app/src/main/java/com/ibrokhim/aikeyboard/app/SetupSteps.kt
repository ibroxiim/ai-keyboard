package com.ibrokhim.aikeyboard.app

import android.content.Context
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import com.ibrokhim.aikeyboard.data.ApiKeyStore
import com.ibrokhim.aikeyboard.reader.ChatReaderService

/** The four setup steps, in order: enable the keyboard, select it, allow chat reading, add a Gemini key. */
data class SetupStatus(
    val keyboardEnabled: Boolean,
    val keyboardSelected: Boolean,
    val readerEnabled: Boolean,
    val hasKey: Boolean,
) {
    val steps: List<Boolean> get() = listOf(keyboardEnabled, keyboardSelected, readerEnabled, hasKey)

    /** Index of the first unfinished step, or null when everything is set up. */
    val current: Int? get() = steps.indexOfFirst { !it }.takeIf { it >= 0 }

    val done: Boolean get() = current == null
}

/** Reads what the app cannot store itself: the system's keyboard and accessibility settings. */
fun readSetupStatus(context: Context, keys: ApiKeyStore): SetupStatus {
    val imm = context.getSystemService(InputMethodManager::class.java)
    val enabled = imm.enabledInputMethodList.any { it.packageName == context.packageName }
    val selected = Settings.Secure.getString(context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
        ?.startsWith(context.packageName + "/") == true
    return SetupStatus(enabled, selected, ChatReaderService.isEnabled(context), keys.effectiveKey().isNotBlank())
}
