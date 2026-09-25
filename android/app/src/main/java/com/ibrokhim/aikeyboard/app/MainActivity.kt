package com.ibrokhim.aikeyboard.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.mutableIntStateOf

class MainActivity : ComponentActivity() {
    /** Bumped on every return from Settings, so the ✓ steps re-read the system state. */
    private val resumeTick = mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { AppTheme { SetupScreen(resumeTick.intValue) } }
    }

    override fun onResume() {
        super.onResume()
        resumeTick.intValue++
    }
}
