package com.ibrokhim.aikeyboard.ime

import android.content.Intent
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalDensity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.ibrokhim.aikeyboard.ai.ChatAnalysisService
import com.ibrokhim.aikeyboard.ai.GeminiClient
import com.ibrokhim.aikeyboard.ai.OkHttpGeminiTransport
import com.ibrokhim.aikeyboard.ai.Translator
import com.ibrokhim.aikeyboard.data.ApiKeyStore
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.ime.ui.ContextDetails
import com.ibrokhim.aikeyboard.ime.ui.EmojiPanel
import com.ibrokhim.aikeyboard.ime.ui.SuggestionBar
import com.ibrokhim.aikeyboard.ime.ui.barModel
import com.ibrokhim.aikeyboard.reader.AccessibilityChatSource
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

class AiKeyboardService : InputMethodService(), LifecycleOwner, SavedStateRegistryOwner {
    // Compose in an input method needs the owners an Activity would normally provide.
    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateController = SavedStateRegistryController.create(this)
    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val savedStateRegistry: SavedStateRegistry get() = savedStateController.savedStateRegistry

    /** What sits where the keys are. */
    private enum class LowerArea { KEYS, EMOJI, DETAILS }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val prefs by lazy { getSharedPreferences("keyboard", MODE_PRIVATE) }
    private lateinit var controller: KeyboardController
    private lateinit var store: SharedStore
    private lateinit var ai: KeyboardAi
    private lateinit var recents: EmojiRecents
    private var keysView: KeysView? = null
    private var panelView: ComposeView? = null
    private var editorInfo: EditorInfo? = null
    private var savedAlphabet = Alphabet.LATIN

    // Compose state read by the bar and the panels.
    private val barTheme = mutableStateOf<KeyboardTheme?>(null)
    private val lowerArea = mutableStateOf(LowerArea.KEYS)
    private val navigationInset = mutableIntStateOf(0)
    private val recentEmoji = mutableStateOf<List<String>>(emptyList())

    private val target = object : InputTarget {
        override fun textBeforeCursor(length: Int): String =
            currentInputConnection?.getTextBeforeCursor(length, 0)?.toString().orEmpty()

        override fun commit(text: String) {
            currentInputConnection?.commitText(text, 1)
        }

        /**
         * Edits through the InputConnection keep their order with commitText; a KEYCODE_DEL key event
         * can land after a following commit (double space turned "word ." instead of "word. ").
         */
        override fun deleteBackward() {
            val ic = currentInputConnection ?: return
            if (!ic.getSelectedText(0).isNullOrEmpty()) {
                ic.commitText("", 1)
                return
            }
            val before = ic.getTextBeforeCursor(16, 0)
            if (before == null) {
                sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL) // editors that cannot report text
                return
            }
            val length = TextRules.lastGraphemeLength(before.toString())
            if (length > 0) ic.deleteSurroundingText(length, 0)
        }

        override fun moveCursor(offset: Int) {
            val code = if (offset < 0) KeyEvent.KEYCODE_DPAD_LEFT else KeyEvent.KEYCODE_DPAD_RIGHT
            repeat(abs(offset)) { sendDownUpKeyEvents(code) }
        }

        override fun enter() {
            val action = EditorRules.imeAction(EditorRules.enterAction(editorInfo?.imeOptions ?: 0))
            if (action != null) {
                currentInputConnection?.performEditorAction(action)
            } else {
                sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
            }
        }

        override fun switchKeyboard() {
            if (Build.VERSION.SDK_INT >= 28) {
                switchToNextInputMethod(false)
            } else {
                val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
                @Suppress("DEPRECATION")
                imm.switchToNextInputMethod(window.window?.attributes?.token, false)
            }
        }

        override fun currentText(): String {
            val ic = currentInputConnection ?: return ""
            val before = ic.getTextBeforeCursor(MAX_FIELD, 0)?.toString().orEmpty()
            val after = ic.getTextAfterCursor(MAX_FIELD, 0)?.toString().orEmpty()
            return before + after
        }

        override fun replaceAll(text: String) {
            val ic = currentInputConnection ?: return
            val before = ic.getTextBeforeCursor(MAX_FIELD, 0)?.length ?: 0
            val after = ic.getTextAfterCursor(MAX_FIELD, 0)?.length ?: 0
            ic.beginBatchEdit()
            ic.deleteSurroundingText(before, after)
            ic.commitText(text, 1) // also replaces a selection, if there was one
            ic.endBatchEdit()
        }

        override val autoCapitalize: Boolean
            get() = EditorRules.autoCapitalize(editorInfo?.inputType ?: 0)
    }

    override fun onCreate() {
        super.onCreate()
        savedStateController.performRestore(null)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_START)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)

        savedAlphabet = prefs.getString("alphabet", null)
            ?.let { name -> Alphabet.entries.find { it.name == name } }
            ?: Alphabet.LATIN
        controller = KeyboardController(target, SystemClock::uptimeMillis, savedAlphabet)
        controller.onChange = {
            if (controller.alphabet != savedAlphabet) {
                savedAlphabet = controller.alphabet
                prefs.edit().putString("alphabet", savedAlphabet.name).apply()
            }
            keysView?.invalidate()
            updateLowerArea()
        }
        recents = EmojiRecents(
            load = { prefs.getString("emojiRecents", "").orEmpty().split('\n').filter { it.isNotEmpty() } },
            save = { prefs.edit().putString("emojiRecents", it.joinToString("\n")).apply() },
        )
        recentEmoji.value = recents.all

        store = SharedStore.get(this)
        val apiKeys = ApiKeyStore.get(this)
        val translator = Translator(GeminiClient(OkHttpGeminiTransport(), { apiKeys.effectiveKey() }))
        ai = KeyboardAi(
            store, translator, ChatAnalysisService(store, translator), target, AccessibilityChatSource(), scope,
            openReaderSetup = ::openReaderSettings,
        )
        barTheme.value = KeyboardTheme.from(this)

        scope.launch {
            combine(store.state, ai.ui) { shared, _ -> shared.emojiKey }.collect { emojiKey ->
                if (controller.emojiKey != emojiKey) {
                    controller.emojiKey = emojiKey
                    if (!emojiKey) controller.closeEmoji()
                    keysView?.invalidate()
                }
                updateLowerArea()
            }
        }
    }

    override fun onCreateInputView(): View {
        window.window?.decorView?.let {
            it.setViewTreeLifecycleOwner(this)
            it.setViewTreeSavedStateRegistryOwner(this)
        }
        val keys = KeysView(this, controller).also { keysView = it }
        val bar = ComposeView(this).apply {
            setContent {
                val shared by store.state.collectAsState()
                val ui by ai.ui.collectAsState()
                barTheme.value?.let { current ->
                    SuggestionBar(barModel(shared, ui, System.currentTimeMillis()), current, ai) {
                        ai.readChat(editorInfo?.packageName)
                    }
                }
            }
        }
        val panel = ComposeView(this).apply {
            visibility = View.GONE
            setContent {
                val shared by store.state.collectAsState()
                val current = barTheme.value ?: return@setContent
                val inset = with(LocalDensity.current) { navigationInset.intValue.toDp() }
                when (lowerArea.value) {
                    LowerArea.KEYS -> Unit
                    LowerArea.EMOJI -> EmojiPanel(
                        recents = recentEmoji.value,
                        theme = current,
                        bottomInset = inset,
                        onEmoji = { emoji ->
                            controller.insertEmoji(emoji)
                            recents.add(emoji)
                        },
                        onAbc = { controller.closeEmoji() },
                        onBackspace = { controller.press(Key.Backspace) },
                    )
                    LowerArea.DETAILS -> shared.freshContext(System.currentTimeMillis())?.let { context ->
                        ContextDetails(context, current, inset) { ai.closeDetails() }
                    }
                }
            }
        }.also { panelView = it }
        // The keys stay laid out (INVISIBLE) under a panel, so the keyboard keeps its height.
        val lower = LowerFrame(this).apply {
            clipChildren = false
            clipToPadding = false
            addView(keys, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(panel, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            // Letter balloons on the top row rise over the bar.
            clipChildren = false
            clipToPadding = false
            addView(bar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(lower, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            if (Build.VERSION.SDK_INT >= 30) {
                setOnApplyWindowInsetsListener { _, insets ->
                    // The system draws its own ⌄ and keyboard-switch buttons in a 48 dp strip at the bottom of
                    // the keyboard window: that is the tappable-element inset, twice the navigation bar hint.
                    val bottom = maxOf(
                        insets.getInsets(WindowInsets.Type.navigationBars()).bottom,
                        insets.getInsets(WindowInsets.Type.tappableElement()).bottom,
                    )
                    keys.setNavigationInset(bottom)
                    navigationInset.intValue = bottom
                    insets
                }
            }
        }
    }

    private fun updateLowerArea() {
        val details = ai.ui.value.detailsOpen && store.value.freshContext(System.currentTimeMillis()) != null
        val area = when {
            details -> LowerArea.DETAILS
            controller.showsEmoji -> LowerArea.EMOJI
            else -> LowerArea.KEYS
        }
        if (area == LowerArea.EMOJI && lowerArea.value != LowerArea.EMOJI) recentEmoji.value = recents.all
        lowerArea.value = area
        keysView?.visibility = if (area == LowerArea.KEYS) View.VISIBLE else View.INVISIBLE
        panelView?.visibility = if (area == LowerArea.KEYS) View.GONE else View.VISIBLE
    }

    /** The keyboard never takes over the whole screen in landscape. */
    override fun onEvaluateFullscreenMode() = false

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        editorInfo = info
        val current = KeyboardTheme.from(this)
        barTheme.value = current
        keysView?.apply {
            this.theme = current
            enterAction = EditorRules.enterAction(info.imeOptions)
        }
        controller.closeEmoji()
        ai.closeDetails()
        controller.setLayer(Layer.LETTERS)
        controller.autoCapitalize()
        keysView?.invalidate()
        if (!restarting) ai.autoRead(info.packageName, info.inputType, info.privateImeOptions)
    }

    override fun onWindowShown() {
        super.onWindowShown()
        keysView?.logLayoutSoon()
    }

    override fun onUpdateSelection(
        oldSelStart: Int,
        oldSelEnd: Int,
        newSelStart: Int,
        newSelEnd: Int,
        candidatesStart: Int,
        candidatesEnd: Int,
    ) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        controller.autoCapitalize()
    }

    override fun onDestroy() {
        scope.cancel()
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        super.onDestroy()
    }

    private fun openReaderSettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { startActivity(intent) }
    }

    private companion object {
        const val MAX_FIELD = 10_000
    }
}
