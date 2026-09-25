package com.ibrokhim.aikeyboard.ime

import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import kotlin.math.abs

class AiKeyboardService : InputMethodService() {
    private val prefs by lazy { getSharedPreferences("keyboard", MODE_PRIVATE) }
    private lateinit var controller: KeyboardController
    private var keysView: KeysView? = null
    private var editorInfo: EditorInfo? = null
    private var savedAlphabet = Alphabet.LATIN

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

        override val autoCapitalize: Boolean
            get() = EditorRules.autoCapitalize(editorInfo?.inputType ?: 0)
    }

    override fun onCreate() {
        super.onCreate()
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
    }

    override fun onCreateInputView(): View = KeysView(this, controller).also { keysView = it }

    /** The keyboard never takes over the whole screen in landscape. */
    override fun onEvaluateFullscreenMode() = false

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        editorInfo = info
        controller.showsGlobe = if (Build.VERSION.SDK_INT >= 28) shouldOfferSwitchingToNextInputMethod() else true
        keysView?.apply {
            theme = KeyboardTheme.from(this@AiKeyboardService)
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
}
