package com.ibrokhim.aikeyboard.ime

import android.annotation.SuppressLint
import android.content.Context
import android.widget.FrameLayout

/**
 * Holds the keys (first child) and the panels drawn over them. It takes its height from the keys alone and
 * gives every panel exactly that height — a plain FrameLayout lets a fill-the-parent panel stretch the
 * keyboard over the whole screen.
 */
@SuppressLint("ViewConstructor")
class LowerFrame(context: Context) : FrameLayout(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val keys = getChildAt(0)
        keys.measure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
        val exact = MeasureSpec.makeMeasureSpec(keys.measuredHeight, MeasureSpec.EXACTLY)
        for (i in 1 until childCount) getChildAt(i).measure(widthMeasureSpec, exact)
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), keys.measuredHeight)
    }
}
