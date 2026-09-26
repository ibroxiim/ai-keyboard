package com.ibrokhim.aikeyboard.data

import android.content.Context
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.Json

/**
 * One JSON file in app storage, mirrored in a StateFlow. The keyboard, the chat reader and the app run
 * in one process, so collectors see every update at once (iOS needed an App Group and Darwin notifications).
 */
class SharedStore(private val file: File) {
    private val lock = Any()
    private val flow = MutableStateFlow(read())

    val state: StateFlow<SharedState> = flow
    val value: SharedState get() = flow.value

    fun update(change: (SharedState) -> SharedState): SharedState = synchronized(lock) {
        val next = change(flow.value)
        if (next != flow.value) {
            write(next)
            flow.value = next
        }
        next
    }

    private fun read(): SharedState = try {
        if (file.exists()) json.decodeFromString(SharedState.serializer(), file.readText()) else SharedState()
    } catch (e: Exception) {
        SharedState() // a corrupt file must not keep the keyboard from starting
    }

    private fun write(state: SharedState) {
        val dir = file.absoluteFile.parentFile
        dir?.mkdirs()
        val tmp = File(dir, file.name + ".tmp")
        tmp.writeText(json.encodeToString(SharedState.serializer(), state))
        if (!tmp.renameTo(file)) {
            file.delete()
            tmp.renameTo(file)
        }
    }

    companion object {
        val json = Json {
            ignoreUnknownKeys = true
            explicitNulls = false
        }

        @Volatile private var instance: SharedStore? = null

        fun get(context: Context): SharedStore = instance ?: synchronized(this) {
            instance ?: SharedStore(File(context.applicationContext.filesDir, "state.json")).also { instance = it }
        }
    }
}
