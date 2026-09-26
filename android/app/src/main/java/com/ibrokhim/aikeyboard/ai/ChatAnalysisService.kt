package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.SharedStore
import kotlinx.coroutines.CancellationException

/** Chat → Gemini → shared state. The keyboard follows `store.state` and shows each step. */
class ChatAnalysisService(
    private val store: SharedStore,
    private val translator: Translator,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    suspend fun run(input: ChatInput): ChatAnalysis {
        // A new read means a new chat — the previous chat's suggestions must not linger.
        store.update { it.copy(analyzingSince = clock(), context = null, contextDate = null) }
        try {
            val known = store.value.friends.map { it.name }
            val result = translator.analyze(input, known) { quick ->
                // The keyboard shows the translation now; suggestions follow when the second call lands.
                store.update { it.copy(context = ChatAnalysis.of(quick, null), contextDate = clock()) }
            }
            val now = clock()
            store.update {
                it.copy(
                    context = result.analysis,
                    contextDate = now,
                    analyzingSince = null,
                    lastError = result.partialError?.message,
                    lastErrorDate = result.partialError?.let { now },
                ).remember(result.analysis, now)
            }
            return result.analysis
        } catch (e: CancellationException) {
            store.update { it.copy(analyzingSince = null) }
            throw e
        } catch (e: Exception) {
            store.update { it.copy(analyzingSince = null, lastError = e.message, lastErrorDate = clock()) }
            throw e
        }
    }
}
