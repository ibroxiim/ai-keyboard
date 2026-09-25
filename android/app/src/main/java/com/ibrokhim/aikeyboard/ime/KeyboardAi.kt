package com.ibrokhim.aikeyboard.ime

import com.ibrokhim.aikeyboard.ai.ChatAnalysisService
import com.ibrokhim.aikeyboard.ai.ChatInput
import com.ibrokhim.aikeyboard.ai.Translator
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.data.Suggestion
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Where the keyboard gets the chat from. The Android side is the accessibility service. */
interface ChatSource {
    /** False while the chat reader service is switched off. */
    val available: Boolean

    /** The chat in [packageName]'s window, or null if nothing readable is on screen. */
    suspend fun read(packageName: String): ChatInput?
}

/** Keyboard-local AI state; the shared part (context, friends, target) lives in `SharedStore`. */
data class AiUiState(
    val variants: List<Suggestion> = emptyList(),
    val rewriting: Boolean = false,
    val notice: String? = null,
    val pickerOpen: Boolean = false,
)

object Notices {
    const val READER_OFF = "Chatni o'qish uchun Sozlamalar → Accessibility → AI Keyboard'ni yoqing"
    const val UNREADABLE = "Bu ilovadan chatni o'qib bo'lmadi"
    const val WRITE_FIRST = "Avval o'zbekcha yozing, keyin ✨ ni bosing"
    const val PICK_OR_WRITE = "Tayyor javoblardan birini tanlang yoki o'zbekcha yozib ✨ ni bosing"
    const val FAILED = "Xatolik yuz berdi"
}

/** The keyboard's AI actions — 📖, ✨, picking a reply, choosing the target — the AI half of iOS `KeyboardModel`. */
class KeyboardAi(
    private val store: SharedStore,
    private val translator: Translator,
    private val analysis: ChatAnalysisService,
    private val target: InputTarget,
    private val chatSource: ChatSource,
    private val scope: CoroutineScope,
    private val clock: () -> Long = System::currentTimeMillis,
    private val openReaderSetup: () -> Unit = {},
) {
    private val state = MutableStateFlow(AiUiState())
    val ui: StateFlow<AiUiState> = state

    private var readJob: Job? = null
    private var rewriteJob: Job? = null
    private var rewriteToken = 0
    private var noticeJob: Job? = null

    /** 📖 — read the chat of the app being typed into and analyse it. */
    fun readChat(packageName: String?) {
        if (!chatSource.available) {
            flash(Notices.READER_OFF)
            openReaderSetup()
            return
        }
        if (packageName == null) {
            flash(Notices.UNREADABLE)
            return
        }
        state.update { it.copy(variants = emptyList(), pickerOpen = false) }
        readJob?.cancel()
        readJob = scope.launch {
            val input = chatSource.read(packageName)
            if (input == null) {
                flash(Notices.UNREADABLE)
                return@launch
            }
            try {
                analysis.run(input)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // ChatAnalysisService already put the error into the store; the bar shows it.
            }
        }
    }

    /** ✨ — rewrite the draft into the conversation language, fitted to the chat. */
    fun magic() {
        val draft = target.currentText().trim()
        val shared = store.value
        val now = clock()
        if (draft.isEmpty()) {
            flash(if (shared.freshContext(now) == null) Notices.WRITE_FIRST else Notices.PICK_OR_WRITE)
            return
        }
        rewriteJob?.cancel()
        val token = ++rewriteToken
        state.update { it.copy(rewriting = true, pickerOpen = false) }
        rewriteJob = scope.launch {
            try {
                val variants = translator.rewrite(
                    draft, shared.freshContext(now), shared.activeFriendProfile(now), shared.language(now),
                )
                state.update { it.copy(variants = variants) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                flash(e.message ?: Notices.FAILED)
            } finally {
                if (token == rewriteToken) state.update { it.copy(rewriting = false) }
            }
        }
    }

    fun pick(suggestion: Suggestion) {
        target.replaceAll(suggestion.text)
        state.update { it.copy(variants = emptyList()) }
    }

    fun dismissVariants() = state.update { it.copy(variants = emptyList()) }

    fun dismissContext() {
        store.update { it.copy(context = null, contextDate = null) }
        state.update { it.copy(variants = emptyList()) }
    }

    fun togglePicker() = state.update { it.copy(pickerOpen = !it.pickerOpen) }

    fun selectFriend(friend: Friend) {
        store.update { it.copy(activeFriend = friend.name, targetLanguage = friend.language) }
        state.update { it.copy(pickerOpen = false) }
    }

    fun selectLanguage(language: String) {
        store.update { it.copy(targetLanguage = language, activeFriend = null) }
        state.update { it.copy(pickerOpen = false) }
    }

    private fun flash(text: String) {
        state.update { it.copy(notice = text) }
        noticeJob?.cancel()
        noticeJob = scope.launch {
            delay(NOTICE_MS)
            state.update { if (it.notice == text) it.copy(notice = null) else it }
        }
    }

    companion object {
        const val NOTICE_MS = 4_000L
    }
}
