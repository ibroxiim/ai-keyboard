package com.ibrokhim.aikeyboard.ime

import com.ibrokhim.aikeyboard.ai.ChatAnalysisService
import com.ibrokhim.aikeyboard.ai.ChatInput
import com.ibrokhim.aikeyboard.ai.Translator
import com.ibrokhim.aikeyboard.ai.quality
import com.ibrokhim.aikeyboard.data.ClipboardOffer
import com.ibrokhim.aikeyboard.data.EditLearning
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.RewriteTweak
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.data.Suggestion
import com.ibrokhim.aikeyboard.reader.ChatLines
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

    /**
     * The chat in [packageName]'s window, or null if nothing readable is on screen. A screenshot is the
     * fallback for apps without readable text — only when [allowScreenshot] (never for auto-read).
     */
    suspend fun read(packageName: String, allowScreenshot: Boolean = true): ChatInput?
}

/** The system clipboard as the keyboard sees it. Looking at [stamp] costs nothing; reading [text] shows the user a toast. */
interface ClipboardSource {
    /** Identifies the current clip when it holds text; null when there is none. */
    fun stamp(): Long?
    fun text(): CharSequence?
    /** The clip the keyboard last offered or used, so a 📋 button does not reappear for it. */
    var seen: Long
}

object NoClipboard : ClipboardSource {
    override fun stamp(): Long? = null
    override fun text(): CharSequence? = null
    override var seen: Long = 0
}

/** Keyboard-local AI state; the shared part (context, friends, target) lives in `SharedStore`. */
data class AiUiState(
    /** ✨ results for the draft; they stay after one is picked, so another one — or the draft — can be put in instead. */
    val variants: List<Suggestion> = emptyList(),
    /** What was in the field when ✨ was tapped, so a picked variant is not a one-way door. Lives with [variants]. */
    val originalDraft: String? = null,
    /** The variant now in the field (its text), for the highlight; null while the field holds the original draft. */
    val picked: String? = null,
    /** "qisqaroq", "iliqroq"… asked of the current variants; every change asks for them again. */
    val tweaks: List<RewriteTweak> = emptyList(),
    val rewriting: Boolean = false,
    val notice: String? = null,
    val pickerOpen: Boolean = false,
    /** The full conversation replaces the keys (tap on the translation). */
    val detailsOpen: Boolean = false,
    /** Every reply in full in place of the keys (long press on a chip, or ⤢). */
    val variantsOpen: Boolean = false,
    val variantsFocus: String? = null,
    /** 📋: the clipboard holds text the keyboard has not offered yet. */
    val clipboardOffered: Boolean = false,
) {
    fun clearedVariants() = copy(
        variants = emptyList(), originalDraft = null, picked = null, tweaks = emptyList(),
        variantsOpen = false, variantsFocus = null,
    )
}

object Notices {
    const val READER_OFF = "Chatni o'qish uchun Sozlamalar → Accessibility → AI Keyboard'ni yoqing"
    const val UNREADABLE = "Bu ilovadan chatni o'qib bo'lmadi"
    const val WRITE_FIRST = "Avval o'zbekcha yozing, keyin ✨ ni bosing"
    const val PICK_OR_WRITE = "Tayyor javoblardan birini tanlang yoki o'zbekcha yozib ✨ ni bosing"
    const val FAILED = "Xatolik yuz berdi"
    const val CLIPBOARD_EMPTY = "Nusxada matn yo'q"
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
    private val clipboard: ClipboardSource = NoClipboard,
    private val openReaderSetup: () -> Unit = {},
) {
    private val state = MutableStateFlow(AiUiState())
    val ui: StateFlow<AiUiState> = state

    private var readJob: Job? = null
    private var rewriteJob: Job? = null
    private var rewriteToken = 0
    private var noticeJob: Job? = null
    /** `replaceAll` empties the field on its way; `textChanged` must not take that for a sent message. */
    private var replacing = false
    /** The field's last non-empty text while a variant was in it — what the user sent once it is empty. */
    private var lastSeenText: String? = null
    private var clipboardChecked = Long.MIN_VALUE / 2

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
        state.update { it.clearedVariants().copy(pickerOpen = false, detailsOpen = false) }
        readJob?.cancel()
        readJob = scope.launch {
            val input = chatSource.read(packageName, allowScreenshot = true)
            if (input == null) {
                flash(Notices.UNREADABLE)
                return@launch
            }
            analyse(input)
        }
    }

    /**
     * Keyboard opened in a messenger with auto-read on: read the chat's text (no screenshot) and analyse it,
     * unless it is the same chat whose analysis is still on screen.
     */
    fun autoRead(packageName: String?, inputType: Int, privateImeOptions: String? = null) {
        val shared = store.value
        if (!AutoRead.eligible(packageName, inputType, shared.autoRead, privateImeOptions)) return
        if (packageName == null || !chatSource.available || shared.isAnalyzing(clock())) return
        readJob?.cancel()
        readJob = scope.launch {
            delay(AUTO_READ_DELAY_MS) // let the app settle behind the keyboard's slide-in
            val input = chatSource.read(packageName, allowScreenshot = false) as? ChatInput.Transcript ?: return@launch
            val hash = ChatLines.hash(input.lines)
            if (!AutoRead.isNew(hash, store.value, clock())) return@launch
            store.update { it.copy(lastReadHash = hash) }
            analyse(input)
        }
    }

    private suspend fun analyse(input: ChatInput) {
        try {
            analysis.run(input)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // ChatAnalysisService already put the error into the store; the bar shows it.
        }
    }

    /** ✨ — rewrite the draft into the conversation language, fitted to the chat. */
    fun magic() {
        val original = target.currentText()
        val draft = original.trim()
        if (draft.isEmpty()) {
            flash(if (store.value.freshContext(clock()) == null) Notices.WRITE_FIRST else Notices.PICK_OR_WRITE)
            return
        }
        // A new ✨ starts plain; the tweaks belonged to the previous variants.
        state.update { it.copy(tweaks = emptyList()) }
        rewrite(original, replacingField = false)
    }

    /**
     * qisqaroq / iliqroq / …: toggles the tweak and asks for the variants of the same draft again — the way the
     * user would say "biroz qisqaroq" to a chat model. A variant already in the field is swapped for the new
     * first one, so the request changes the text like it would in the chat.
     */
    fun refine(tweak: RewriteTweak) {
        val original = state.value.originalDraft ?: return
        state.update { it.copy(tweaks = if (tweak in it.tweaks) it.tweaks - tweak else it.tweaks + tweak) }
        rewrite(original, replacingField = state.value.picked != null)
    }

    private fun rewrite(original: String, replacingField: Boolean) {
        val draft = original.trim()
        val shared = store.value
        val now = clock()
        val tweaks = state.value.tweaks
        rewriteJob?.cancel()
        val token = ++rewriteToken
        state.update { it.copy(rewriting = true, pickerOpen = false) }
        rewriteJob = scope.launch {
            try {
                val variants = translator.rewrite(
                    draft, shared.freshContext(now), shared.activeFriendProfile(now), shared.language(now),
                    formality = shared.chosenFormality, history = shared.rememberedMessages,
                    notes = shared.activeFriendRecord?.notes, tweaks = tweaks, examples = shared.rememberedExamples,
                    style = shared.translationStyle, quality = shared.quality,
                )
                state.update { it.copy(variants = variants, originalDraft = original, picked = null) }
                if (replacingField) variants.firstOrNull()?.let { pick(it) }
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
        replace(suggestion.text)
        lastSeenText = suggestion.text
        // The chat-read replies always stayed on the row; the ✨ variants do too, with the picked one lit.
        state.update {
            it.copy(picked = if (it.variants.isNotEmpty()) suggestion.text else it.picked, variantsOpen = false, variantsFocus = null)
        }
    }

    /** ↩︎ Asli — what the user had typed before ✨. */
    fun restoreOriginal() {
        val original = state.value.originalDraft ?: return
        replace(original)
        state.update { it.copy(picked = null, variantsOpen = false, variantsFocus = null) }
    }

    private fun replace(text: String) {
        replacing = true
        try {
            target.replaceAll(text)
        } finally {
            replacing = false
        }
    }

    fun dismissVariants() {
        state.update { it.clearedVariants() }
        lastSeenText = null
    }

    /**
     * The field changed. A sent message empties it: the variants were for that message, and what the user changed
     * in the picked one before sending is worth remembering.
     */
    fun textChanged() {
        checkClipboard()
        if (replacing || state.value.variants.isEmpty()) return
        val text = target.currentText()
        if (text.isNotEmpty()) {
            if (state.value.picked != null) lastSeenText = text
            return
        }
        learnFromSentMessage()
        dismissVariants()
    }

    private fun learnFromSentMessage() {
        val ui = state.value
        val picked = ui.picked ?: return
        val sent = lastSeenText ?: return
        val original = ui.originalDraft ?: return
        val example = EditLearning.example(original, picked, sent) ?: return
        store.update { it.learn(example) }
    }

    fun dismissContext() {
        store.update { it.copy(context = null, contextDate = null) }
        state.update { it.clearedVariants().copy(detailsOpen = false) }
    }

    fun openDetails() {
        if (store.value.freshContext(clock()) != null) state.update { it.copy(detailsOpen = true, variantsOpen = false) }
    }

    fun closeDetails() = state.update { it.copy(detailsOpen = false) }

    /** Every reply in full, over the keys; [focus] is the one to scroll to (long press on its chip). */
    fun openVariants(focus: Suggestion? = null) {
        val hasReplies = state.value.variants.isNotEmpty() ||
            store.value.freshContext(clock())?.suggestions?.isNotEmpty() == true
        if (!hasReplies) return
        state.update { it.copy(variantsOpen = true, variantsFocus = focus?.text, detailsOpen = false, pickerOpen = false) }
    }

    fun closeVariants() = state.update { it.copy(variantsOpen = false, variantsFocus = null) }

    fun togglePicker() = state.update { it.copy(pickerOpen = !it.pickerOpen) }

    fun selectFriend(friend: Friend) {
        store.update { it.copy(activeFriend = friend.name, targetLanguage = friend.language) }
        state.update { it.copy(pickerOpen = false) }
    }

    fun selectLanguage(language: String) {
        store.update { it.copy(targetLanguage = language, activeFriend = null) }
        state.update { it.copy(pickerOpen = false) }
    }

    // MARK: Clipboard

    /**
     * Something copied since the keyboard last looked — a message in the chat, most likely — earns a 📋 button.
     * Throttled: it is also called on text changes.
     */
    fun checkClipboard(force: Boolean = false) {
        val now = clock()
        if (!force && now - clipboardChecked < CLIPBOARD_CHECK_MS) return
        clipboardChecked = now
        val stamp = clipboard.stamp()
        val offered = stamp != null && stamp != clipboard.seen
        state.update { if (it.clipboardOffered == offered) it else it.copy(clipboardOffered = offered) }
    }

    /** 📋 Tarjima — the copied message, read like a chat but from its exact text. */
    fun translateClipboard() {
        clipboard.stamp()?.let { clipboard.seen = it }
        state.update { it.copy(clipboardOffered = false) }
        val text = ClipboardOffer.usable(clipboard.text())
        if (text == null) {
            flash(Notices.CLIPBOARD_EMPTY)
            return
        }
        val shared = store.value
        // The same state a chat read writes, so the spinner, the line, the card and ✨ just follow.
        store.update { it.copy(analyzingSince = clock(), context = null, contextDate = null) }
        readJob?.cancel()
        readJob = scope.launch {
            try {
                val analysis = translator.readClipboard(text, shared.activeFriendRecord, shared.translationStyle, shared.quality)
                val now = clock()
                store.update {
                    it.copy(context = analysis, contextDate = now, analyzingSince = null, lastError = null, lastErrorDate = null)
                        .remember(analysis, now)
                }
            } catch (e: CancellationException) {
                store.update { it.copy(analyzingSince = null) }
                throw e
            } catch (e: Exception) {
                store.update { it.copy(analyzingSince = null, lastError = e.message ?: Notices.FAILED, lastErrorDate = clock()) }
            }
        }
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
        const val AUTO_READ_DELAY_MS = 300L
        const val CLIPBOARD_CHECK_MS = 2_000L
    }
}
