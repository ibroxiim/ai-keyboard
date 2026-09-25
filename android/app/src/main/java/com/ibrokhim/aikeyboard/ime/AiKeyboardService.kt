package com.ibrokhim.aikeyboard.ime

import android.inputmethodservice.InputMethodService
import android.view.View

class AiKeyboardService : InputMethodService() {
    override fun onCreateInputView(): View = View(this)
}
