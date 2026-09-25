package com.ibrokhim.aikeyboard.app

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.WindowInsets
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/** Milestone 1 stand-in: a field to type into. Setup steps and settings replace it in milestone 5. */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pad = (16 * resources.displayMetrics.density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
        }
        root.addView(TextView(this).apply {
            text = "AI Keyboard — sinov maydoni"
            textSize = 20f
        })
        root.addView(EditText(this).apply {
            hint = "Shu yerga yozing"
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or
                InputType.TYPE_TEXT_FLAG_MULTI_LINE
            minLines = 3
        })
        if (Build.VERSION.SDK_INT >= 30) {
            // targetSdk 36 draws edge to edge; keep the field clear of the status bar and the keyboard.
            root.setOnApplyWindowInsetsListener { view, insets ->
                val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                view.setPadding(pad + bars.left, pad + bars.top, pad + bars.right, pad + bars.bottom)
                insets
            }
        }
        setContentView(root)
    }
}
