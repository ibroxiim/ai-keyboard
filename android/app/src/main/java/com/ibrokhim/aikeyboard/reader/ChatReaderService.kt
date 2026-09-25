package com.ibrokhim.aikeyboard.reader

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.provider.Settings
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import java.io.ByteArrayOutputStream
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Reads the chat on request only: it uses no events and keeps nothing. The keyboard asks for the text of
 * the app being typed into; a screenshot is the fallback for apps whose text the tree cannot see.
 */
class ChatReaderService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    /** Tagged chat lines of [packageName]'s window, or null if that window is not on screen. */
    fun readLines(packageName: String): List<String>? {
        val window = windows.firstOrNull {
            it.type == AccessibilityWindowInfo.TYPE_APPLICATION && it.root?.packageName?.toString() == packageName
        } ?: return null
        val root = window.root ?: return null
        val bounds = Rect().also { window.getBoundsInScreen(it) }
        val nodes = mutableListOf<TextNode>()
        collect(root, nodes, depth = 0)
        return ChatLines.build(nodes, WindowBounds(bounds.left, bounds.top, bounds.right, bounds.bottom))
    }

    private fun collect(node: AccessibilityNodeInfo, out: MutableList<TextNode>, depth: Int) {
        if (depth > MAX_DEPTH || !node.isVisibleToUser) return
        val text = (node.text ?: node.contentDescription)?.toString()
        if (!text.isNullOrBlank()) {
            val r = Rect().also { node.getBoundsInScreen(it) }
            out.add(TextNode(text, r.left, r.top, r.right, r.bottom, node.isEditable))
        }
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { collect(it, out, depth + 1) }
        }
    }

    /** Android 11+: the screen as a 720 px wide JPEG, or null. */
    suspend fun screenshotJpeg(): ByteArray? {
        if (Build.VERSION.SDK_INT < 30) return null
        return suspendCancellableCoroutine { continuation ->
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(result: ScreenshotResult) {
                        val jpeg = result.hardwareBuffer.use { buffer ->
                            Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)?.let(::toJpeg)
                        }
                        if (continuation.isActive) continuation.resume(jpeg)
                    }

                    override fun onFailure(errorCode: Int) {
                        if (continuation.isActive) continuation.resume(null)
                    }
                },
            )
        }
    }

    private fun toJpeg(hardware: Bitmap): ByteArray {
        val software = hardware.copy(Bitmap.Config.ARGB_8888, false)
        val scale = minOf(1f, 720f / software.width)
        val scaled = Bitmap.createScaledBitmap(
            software, (software.width * scale).toInt(), (software.height * scale).toInt(), true,
        )
        return ByteArrayOutputStream().use { out ->
            scaled.compress(Bitmap.CompressFormat.JPEG, 70, out)
            out.toByteArray()
        }
    }

    companion object {
        private const val MAX_DEPTH = 60

        @Volatile
        var instance: ChatReaderService? = null
            private set

        fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val me = ComponentName(context, ChatReaderService::class.java)
            return enabled.split(':').any { ComponentName.unflattenFromString(it) == me }
        }
    }
}
