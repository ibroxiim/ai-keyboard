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
import android.widget.LinearLayout
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.ibrokhim.aikeyboard.BuildConfig
import com.ibrokhim.aikeyboard.ai.ChatAnalysisService
import com.ibrokhim.aikeyboard.ai.GeminiClient
import com.ibrokhim.aikeyboard.ai.OkHttpGeminiTransport
import com.ibrokhim.aikeyboard.ai.Translator
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.ime.ui.SuggestionBar
import com.ibrokhim.aikeyboard.ime.ui.barModel
import com.ibrokhim.aikeyboard.reader.AccessibilityChatSource
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

class AiKeyboardService : InputMethodService(), LifecycleOwner, SavedStateRegistryOwner {
    // Compose in an input method needs the owners an Activity would normally provide.
    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateController = SavedStateRegistryController.create(this)
    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val savedStateRegistry: SavedStateRegistry get() = savedStateController.savedStateRegistry

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val prefs by lazy { getSharedPreferences("keyboard", MODE_PRIVATE) }
    private lateinit var controller: KeyboardController
    private lateinit var store: SharedStore
    private lateinit var ai: KeyboardAi
    private var keysView: KeysView? = null
    private var editorInfo: EditorInfo? = null
    private var savedAlphabet = Alphabet.LATIN
    /** Compose state, so the bar recolours when the system switches light/dark. */
    private val barTheme = mutableStateOf<KeyboardTheme?>(null)

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
        }

        store = SharedStore.get(this)
        val translator = Translator(GeminiClient(OkHttpGeminiTransport(), { BuildConfig.GEMINI_API_KEY }))
        ai = KeyboardAi(
            store, translator, ChatAnalysisService(store, translator), target, AccessibilityChatSource(), scope,
            openReaderSetup = ::openReaderSettings,
        )
        barTheme.value = KeyboardTheme.from(this)
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
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(bar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(keys, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            if (Build.VERSION.SDK_INT >= 30) {
                setOnApplyWindowInsetsListener { _, insets ->
                    keys.setNavigationInset(insets.getInsets(WindowInsets.Type.navigationBars()).bottom)
                    insets
                }
            }
        }
    }

    /** The keyboard never takes over the whole screen in landscape. */
    override fun onEvaluateFullscreenMode() = false

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        editorInfo = info
        controller.showsGlobe = if (Build.VERSION.SDK_INT >= 28) shouldOfferSwitchingToNextInputMethod() else true
        val current = KeyboardTheme.from(this)
        barTheme.value = current
        keysView?.apply {
            this.theme = current
            enterAction = EditorRules.enterAction(info.imeOptions)
        }
        controller.setLayer(Layer.LETTERS)
        controller.autoCapitalize()
        keysView?.invalidate()
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
