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
            val key = normalize(value)
            if (key == null) editor.remove(KEY) else editor.putString(KEY, key)
            editor.apply()
        }

    fun effectiveKey(): String = resolveKey(userKey, BuildConfig.GEMINI_API_KEY)

    companion object {
        private const val KEY = "geminiApiKey"

        fun resolveKey(user: String?, build: String): String = normalize(user) ?: build

        /** Pasted keys often carry spaces or line breaks; null when nothing is left (iOS `APIKey.normalized`). */
        fun normalize(text: String?): String? = text?.filter { !it.isWhitespace() }?.takeIf { it.isNotEmpty() }

        /** Shows which key is saved without showing the key: four dots and the last four characters. */
        fun masked(key: String): String = if (key.length <= 4) "•".repeat(key.length) else "••••" + key.takeLast(4)

        fun get(context: Context) = ApiKeyStore(context.applicationContext.getSharedPreferences("secrets", Context.MODE_PRIVATE))
    }
}
