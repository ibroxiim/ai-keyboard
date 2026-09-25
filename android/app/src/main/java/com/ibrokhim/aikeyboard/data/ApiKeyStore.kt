package com.ibrokhim.aikeyboard.data

import android.content.Context
import android.content.SharedPreferences
import com.ibrokhim.aikeyboard.BuildConfig

/**
 * The user's own Gemini key, kept in the app's private storage (backups are off in the manifest).
 * A public APK carries no key; debug builds fall back to the developer's key from local.properties.
 */
class ApiKeyStore(private val prefs: SharedPreferences) {
    var userKey: String?
        get() = prefs.getString(KEY, null)?.takeIf { it.isNotBlank() }
        set(value) {
            val editor = prefs.edit()
            if (value.isNullOrBlank()) editor.remove(KEY) else editor.putString(KEY, value.trim())
            editor.apply()
        }

    fun effectiveKey(): String = resolveKey(userKey, BuildConfig.GEMINI_API_KEY)

    companion object {
        private const val KEY = "geminiApiKey"

        fun resolveKey(user: String?, build: String): String = user?.trim()?.takeIf { it.isNotEmpty() } ?: build

        fun get(context: Context) = ApiKeyStore(context.applicationContext.getSharedPreferences("secrets", Context.MODE_PRIVATE))
    }
}
