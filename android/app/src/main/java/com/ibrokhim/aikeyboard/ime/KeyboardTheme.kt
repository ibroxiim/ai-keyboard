package com.ibrokhim.aikeyboard.ime

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color

/** Material You-leaning colours; the brand blue marks only Enter here (✨ and chips later). */
data class KeyboardTheme(
    val background: Int,
    val key: Int,
    val functionKey: Int,
    val pressed: Int,
    val label: Int,
    val accent: Int,
    val onAccent: Int,
) {
    companion object {
        fun from(context: Context): KeyboardTheme {
            val nightBits = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
            return if (nightBits == Configuration.UI_MODE_NIGHT_YES) {
                KeyboardTheme(
                    background = Color.parseColor("#1B1C1F"),
                    key = Color.parseColor("#3A3B40"),
                    functionKey = Color.parseColor("#2B2C30"),
                    pressed = Color.parseColor("#55565C"),
                    label = Color.parseColor("#E8E8EC"),
                    accent = Color.parseColor("#5B8CFF"),
                    onAccent = Color.WHITE,
                )
            } else {
                KeyboardTheme(
                    background = Color.parseColor("#E9ECF1"),
                    key = Color.WHITE,
                    functionKey = Color.parseColor("#D2D7DF"),
                    pressed = Color.parseColor("#C3C9D3"),
                    label = Color.parseColor("#1D1F24"),
                    accent = Color.parseColor("#3D7BFF"),
                    onAccent = Color.WHITE,
                )
            }
        }
    }
}
