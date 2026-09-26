package com.ibrokhim.aikeyboard.app

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Brand blue/purple on Material 3 — the same accent the keyboard uses for ✨. */
@Composable
fun AppTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) {
        darkColorScheme(primary = Color(0xFF6F98FF), secondary = Color(0xFF9A7BFF))
    } else {
        lightColorScheme(primary = Color(0xFF3D7BFF), secondary = Color(0xFF7B4BFF))
    }
    MaterialTheme(colorScheme = scheme, content = content)
}
