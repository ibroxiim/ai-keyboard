package com.ibrokhim.aikeyboard.app

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowInsets
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** A DM look-alike for trying 📖 without a messenger installed. People and chats are fictional. */
class DemoChatActivity : Activity() {
    private val messages = listOf(
        false to "omg ur samarkand pics are unreal 😭😭",
        true to "thank you! it was so beautiful",
        false to "ngl i lowkey wanna visit now lol",
        false to "btw i'm landing in tashkent on friday w my sister ✈️",
        false to "u free this weekend? we could grab food, ur call on the spot 🍜",
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(8), dp(12), dp(8))
        }
        fun bubble(mine: Boolean, text: String) {
            val view = TextView(this).apply {
                this.text = text
                textSize = 16f
                setTextColor(if (mine) Color.WHITE else Color.parseColor("#0F1117"))
                background = GradientDrawable().apply {
                    cornerRadius = dp(18).toFloat()
                    setColor(Color.parseColor(if (mine) "#3D7BFF" else "#EEF0F6"))
                }
                setPadding(dp(12), dp(8), dp(12), dp(8))
                maxWidth = (resources.displayMetrics.widthPixels * 0.72).toInt()
            }
            list.addView(view, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = if (mine) Gravity.END else Gravity.START
                topMargin = dp(4)
            })
        }
        messages.forEach { (mine, text) -> bubble(mine, text) }

        val scroll = ScrollView(this).apply { addView(list) }
        val header = TextView(this).apply {
            text = "Emma"
            textSize = 18f
            setTypeface(typeface, Typeface.BOLD)
            setPadding(dp(16), dp(12), dp(16), dp(12))
        }
        val field = EditText(this).apply {
            hint = "Message…"
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or
                InputType.TYPE_TEXT_FLAG_MULTI_LINE
            maxLines = 4
        }
        val send = Button(this).apply { text = "➤" }
        send.setOnClickListener {
            val text = field.text.toString().trim()
            if (text.isNotEmpty()) {
                bubble(true, text)
                field.setText("")
                scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
            }
        }
        val inputRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
            addView(field, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
            addView(send, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(header)
            addView(scroll, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
            addView(inputRow)
        }
        if (Build.VERSION.SDK_INT >= 30) {
            root.setOnApplyWindowInsetsListener { view, insets ->
                val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
                insets
            }
        }
        setContentView(root)
    }
}
