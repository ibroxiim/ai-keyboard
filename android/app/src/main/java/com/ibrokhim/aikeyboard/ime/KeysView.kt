package com.ibrokhim.aikeyboard.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import com.ibrokhim.aikeyboard.BuildConfig
import com.ibrokhim.aikeyboard.R
import kotlin.math.abs

/**
 * Draws the keys and turns touches into `KeyboardController` presses. A custom view rather than
 * Compose for the lowest touch latency — the iOS keyboard moved to UIKit keys for the same reason.
 */
@SuppressLint("ViewConstructor")
class KeysView(context: Context, private val controller: KeyboardController) : View(context) {

    private val density = resources.displayMetrics.density
    private fun dp(value: Float) = value * density

    private val keyHeight = dp(46f)
    private val rowGap = dp(10f)
    private val keyGap = dp(6f)
    private val sideInset = dp(4f)
    private val topInset = dp(8f)
    private val bottomInset = dp(6f)
    private val radius = dp(8f)

    var theme = KeyboardTheme.from(context)
        set(value) {
            field = value
            setBackgroundColor(value.background)
            invalidate()
        }

    var enterAction = EnterAction.NEWLINE
        set(value) {
            field = value
            invalidate()
        }

    /** Android 15+ draws the keyboard behind the navigation bar; keep the keys above it. */
    private var navigationInset = 0

    private val iconSize = dp(24f)
    private val icons = mutableMapOf<Int, Drawable>()

    private fun icon(id: Int): Drawable = icons.getOrPut(id) { context.getDrawable(id)!!.mutate() }

    private class Cap(val key: Key, val frame: RectF, val hit: RectF)

    private class Pointer(val id: Int, val index: Int, val startX: Float) {
        var dragging = false
        var consumedX = 0f
    }

    private var caps: List<Cap> = emptyList()
    private var builtFor: KeysConfig? = null
    private var builtWidth = 0
    private val pointers = mutableListOf<Pointer>()
    private val repeatHandler = Handler(Looper.getMainLooper())
    private var repeating: Runnable? = null

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }

    init {
        setBackgroundColor(theme.background)
        if (Build.VERSION.SDK_INT >= 30) {
            setOnApplyWindowInsetsListener { _, insets ->
                val bottom = insets.getInsets(WindowInsets.Type.navigationBars()).bottom
                if (bottom != navigationInset) {
                    navigationInset = bottom
                    requestLayout()
                }
                insets
            }
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val height = topInset + keyHeight * 4 + rowGap * 3 + bottomInset + navigationInset
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), height.toInt())
    }

    private fun ensureLayout() {
        val config = controller.config
        if (width == 0 || (config == builtFor && width == builtWidth)) return
        cancelPointers()
        builtFor = config
        builtWidth = width
        val rows = KeyLayouts.rows(config, width.toFloat(), keyGap, sideInset)
        val full = width - sideInset * 2
        val built = mutableListOf<Cap>()
        rows.forEachIndexed { r, row ->
            val top = topInset + r * (keyHeight + rowGap)
            val rowWidth = row.sumOf { it.width.toDouble() }.toFloat() + keyGap * (row.size - 1)
            var x = sideInset + (full - rowWidth) / 2
            row.forEachIndexed { i, placed ->
                val frame = RectF(x, top, x + placed.width, top + keyHeight)
                // Hit areas fill the gaps (and the edges) so no touch lands on nothing.
                val hit = RectF(
                    if (i == 0) 0f else frame.left - keyGap / 2,
                    if (r == 0) 0f else top - rowGap / 2,
                    if (i == row.lastIndex) width.toFloat() else frame.right + keyGap / 2,
                    if (r == rows.lastIndex) height.toFloat() else frame.bottom + rowGap / 2,
                )
                built.add(Cap(placed.key, frame, hit))
                x += placed.width + keyGap
            }
        }
        caps = built
        logLayoutSoon()
    }

    override fun onDraw(canvas: Canvas) {
        ensureLayout()
        val pressed = pointers.map { it.index }.toSet()
        caps.forEachIndexed { i, cap ->
            val isEnter = cap.key == Key.Enter
            fill.color = when {
                i in pressed -> theme.pressed
                isEnter -> theme.accent
                cap.key == Key.Shift && controller.shift != ShiftState.OFF -> theme.key
                cap.key is Key.Text || cap.key == Key.Space -> theme.key
                else -> theme.functionKey
            }
            canvas.drawRoundRect(cap.frame, radius, radius, fill)
            drawLabel(canvas, cap, isEnter)
        }
    }

    /** Keys drawn with a Material icon; everything else gets a text label. */
    private fun iconFor(key: Key): Int? = when (key) {
        Key.Shift -> when (controller.shift) {
            ShiftState.OFF -> R.drawable.key_shift
            ShiftState.ONCE -> R.drawable.key_shift_once
            ShiftState.LOCKED -> R.drawable.key_shift_locked
        }
        Key.Backspace -> R.drawable.key_backspace
        Key.Globe -> R.drawable.key_globe
        Key.Emoji -> R.drawable.key_emoji
        Key.Enter -> when (enterAction) {
            EnterAction.NEWLINE -> R.drawable.key_enter
            EnterAction.SEND -> R.drawable.key_send
            EnterAction.GO -> R.drawable.key_go
            EnterAction.SEARCH -> R.drawable.key_search
            EnterAction.NEXT -> R.drawable.key_next
            EnterAction.DONE -> R.drawable.key_done
            EnterAction.PREVIOUS -> R.drawable.key_previous
        }
        else -> null
    }

    private fun label(key: Key): String = when (key) {
        is Key.Text -> if (controller.shift == ShiftState.OFF) key.value else key.value.uppercase()
        Key.Space -> if (controller.config.alphabet == Alphabet.LATIN) "Oʻzbekcha" else "Ўзбекча"
        Key.AlphabetToggle -> if (controller.alphabet == Alphabet.LATIN) "КИР" else "LAT"
        is Key.LayerSwitch -> key.label
        else -> ""
    }

    private fun drawLabel(canvas: Canvas, cap: Cap, isEnter: Boolean) {
        val color = if (isEnter) theme.onAccent else theme.label
        val iconId = iconFor(cap.key)
        if (iconId != null) {
            val drawable = icon(iconId)
            val half = (iconSize / 2).toInt()
            val cx = cap.frame.centerX().toInt()
            val cy = cap.frame.centerY().toInt()
            drawable.setBounds(cx - half, cy - half, cx + half, cy + half)
            drawable.setTint(color)
            drawable.draw(canvas)
            return
        }
        text.textSize = when (cap.key) {
            is Key.Text -> dp(22f)
            Key.Space -> dp(14f)
            else -> dp(15f)
        }
        text.color = color
        text.typeface = Typeface.DEFAULT
        val y = cap.frame.centerY() - (text.descent() + text.ascent()) / 2
        canvas.drawText(label(cap.key), cap.frame.centerX(), y, text)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        ensureLayout()
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = event.actionIndex
                val index = indexAt(event.getX(i), event.getY(i))
                if (index != null) {
                    val pointer = Pointer(event.getPointerId(i), index, event.getX(i))
                    pointers.add(pointer)
                    onDown(pointer)
                }
            }
            MotionEvent.ACTION_MOVE -> {
                for (i in 0 until event.pointerCount) {
                    val pointer = pointers.find { it.id == event.getPointerId(i) } ?: continue
                    onMove(pointer, event.getX(i))
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val id = event.getPointerId(event.actionIndex)
                val pointer = pointers.find { it.id == id }
                if (pointer != null) {
                    pointers.remove(pointer)
                    onUp(pointer)
                }
            }
            MotionEvent.ACTION_CANCEL -> cancelPointers()
        }
        invalidate()
        return true
    }

    private fun indexAt(x: Float, y: Float): Int? =
        caps.indexOfFirst { it.hit.contains(x, y) }.takeIf { it >= 0 }

    /** Letters type on touch-down so fast two-thumb typing (rollover) never drops a key. */
    private fun onDown(pointer: Pointer) {
        when (val key = caps[pointer.index].key) {
            is Key.Text, Key.Shift -> controller.press(key)
            Key.Backspace -> {
                controller.press(key)
                startRepeat()
            }
            else -> Unit // space, enter, layer, alphabet and globe act on release
        }
    }

    /** Dragging on the space bar moves the cursor, one character per 10 dp. */
    private fun onMove(pointer: Pointer, x: Float) {
        if (caps.getOrNull(pointer.index)?.key != Key.Space) return
        val dx = x - pointer.startX
        if (!pointer.dragging && abs(dx) > dp(14f)) pointer.dragging = true
        if (!pointer.dragging) return
        val step = dp(10f)
        val steps = ((dx - pointer.consumedX) / step).toInt()
        if (steps != 0) {
            controller.moveCursor(steps)
            pointer.consumedX += steps * step
        }
    }

    private fun onUp(pointer: Pointer) {
        when (val key = caps.getOrNull(pointer.index)?.key ?: return) {
            Key.Backspace -> stopRepeat()
            Key.Space -> if (!pointer.dragging) controller.press(key)
            is Key.Text, Key.Shift -> Unit
            else -> controller.press(key)
        }
    }

    private fun startRepeat() {
        stopRepeat()
        val runnable = object : Runnable {
            override fun run() {
                controller.press(Key.Backspace)
                repeatHandler.postDelayed(this, 60)
            }
        }
        repeating = runnable
        repeatHandler.postDelayed(runnable, 400)
    }

    private fun stopRepeat() {
        repeating?.let { repeatHandler.removeCallbacks(it) }
        repeating = null
    }

    private fun cancelPointers() {
        pointers.clear()
        stopRepeat()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        cancelPointers()
    }

    /** Debug builds: key centres in screen pixels, read by `android/tools/adb-type.py`. */
    fun logLayoutSoon() {
        if (BuildConfig.DEBUG) post { logLayout() }
    }

    private fun logLayout() {
        ensureLayout()
        val origin = IntArray(2).also { getLocationOnScreen(it) }
        val json = caps.joinToString(",", "{", "}") { cap ->
            val x = (origin[0] + cap.frame.centerX()).toInt()
            val y = (origin[1] + cap.frame.centerY()).toInt()
            "\"${debugName(cap.key)}\":[$x,$y]"
        }
        Log.d("AIKeys", "layout $json")
    }

    private fun debugName(key: Key): String = when (key) {
        is Key.Text -> key.value.replace("\\", "\\\\").replace("\"", "\\\"")
        Key.Shift -> "shift"
        Key.Backspace -> "backspace"
        Key.Globe -> "globe"
        Key.Space -> "space"
        Key.Enter -> "enter"
        Key.AlphabetToggle -> "alphabet"
        Key.Emoji -> "emoji"
        is Key.LayerSwitch -> "layer:${key.label}"
    }
}
