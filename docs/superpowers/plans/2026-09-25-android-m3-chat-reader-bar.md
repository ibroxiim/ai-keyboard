# Android M3 — chatni o'qish, takliflar paneli va ✨: implementatsiya rejasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Klaviaturada haqiqiy AI: 📖 bosilganda Accessibility xizmati yozilayotgan ilovaning chatini o'qiydi (matn, bo'lmasa skrinshot), panelda tarjima va 3 ta javob chiqadi, javob bosilsa maydonga tushadi; o'zbekcha qoralama ✨ bilan do'stning tiliga qayta yoziladi; kontekst yo'q paytda maqsad chipi orqali do'st/til tanlanadi.

**Architecture:** `reader/ChatLines` (sof: tugunlar → `[TOP]/[L]/[R]` qatorlar), `reader/ChatReaderService` (AccessibilityService, faqat so'ralganda o'qiydi) va `AccessibilityChatSource`. `ime/KeyboardAi` — 📖/✨/tanlash harakatlari (Android'siz, `ChatSource` va `InputTarget` orqali), `ime/ui/BarModel` — panel holati (sof funksiya), `ime/ui/SuggestionBar` — Compose'da chizish. `AiKeyboardService` Compose uchun `LifecycleOwner`/`SavedStateRegistryOwner` bo'ladi va panel + tugmalarni ustma-ust qo'yadi. Sinov uchun ilovada to'qima `DemoChatActivity`. Spec: `docs/superpowers/specs/2026-09-25-android-version-design.md` (3-bosqich).

**Tech Stack:** M1–M2 + Jetpack Compose (BOM 2026.06.01: ui 1.11.4, material3 1.4.0 — 1.12 compileSdk 37 talab qiladi), Kotlin compose compiler plugini 2.3.20.

## Global Constraints

- M1 va M2 cheklovlari amal qiladi (package, SDK 26/36, JDK/Gradle, commit va git qoidalari, kalit hech qachon commit/log qilinmaydi, faqat to'qima ismlar).
- Chat faqat 📖 bosilganda o'qiladi (avtomatik o'qish M4 da). Accessibility xizmati hodisalarni ishlatmaydi va hech narsa saqlamaydi.
- Pastdan eng ko'pi 40 ta xabar qatori (+ barcha `[TOP]` qatorlar); `[L]/[R]` 2 tadan kam bo'lsa — skrinshot (Android 11+, 720 px JPEG q70); Android 10 va eskisida — "Bu ilovadan chatni o'qib bo'lmadi".
- UI matnlari o'zbekcha (quyidagi `Notices` va panel yozuvlari aynan).
- Panel: holat qatori 36 dp, chip qatori 58 dp; chip qatori bo'sh bo'lsa yig'iladi.

## Fayllar

| Fayl | Vazifasi |
|---|---|
| `android/build.gradle.kts`, `android/app/build.gradle.kts` | Compose plugini va bog'liqliklar |
| `android/app/src/main/AndroidManifest.xml` | `INTERNET`, Accessibility xizmati, `DemoChatActivity` |
| `android/app/src/main/res/xml/chat_reader.xml`, `res/values/strings.xml` | Xizmat sozlamasi va matnlar |
| `.../reader/ChatLines.kt` | Tugunlar → belgilangan qatorlar, xesh (sof) |
| `.../reader/ChatReaderService.kt` | Oynani o'qish va skrinshot |
| `.../reader/AccessibilityChatSource.kt` | `ChatSource`ning Android tomoni |
| `.../ime/KeyboardController.kt` | `InputTarget`ga `currentText`, `replaceAll` |
| `.../ime/KeyboardAi.kt` | `ChatSource`, `AiUiState`, `KeyboardAi`, `Notices` |
| `.../ime/ui/BarModel.kt` | Panel holati (sof) |
| `.../ime/ui/SuggestionBar.kt` | Compose panel |
| `.../ime/KeysView.kt` | Navigatsiya inset'i tashqaridan; joy o'zgarsa layout log |
| `.../ime/AiKeyboardService.kt` | Lifecycle, panel + tugmalar, AI ulanishi |
| `.../app/DemoChatActivity.kt`, `.../app/MainActivity.kt` | To'qima demo chat va unga tugma |
| `android/app/src/test/.../reader/ChatLinesTest.kt`, `.../ime/KeyboardAiTest.kt`, `.../ime/ui/BarModelTest.kt` | JVM testlar |

`...` = `android/app/src/main/java/com/ibrokhim/aikeyboard`. Buyruqlar `android/` papkasida.

---

### Task 1: Compose bog'liqliklari va `ChatLines`

**Files:**
- Modify: `android/build.gradle.kts`, `android/app/build.gradle.kts`
- Create: `.../reader/ChatLines.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/reader/ChatLinesTest.kt`

**Interfaces:**
- Produces: `data class TextNode(text, left, top, right, bottom, editable)`, `data class WindowBounds(left, top, right, bottom)`, `ChatLines.build(nodes, window): List<String>`, `ChatLines.hasMessages(lines): Boolean`, `ChatLines.hash(lines): String`, `ChatLines.MAX_MESSAGE_LINES = 40`.

- [ ] **Step 1: Gradle**

`android/build.gradle.kts`:
```kotlin
plugins {
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.3.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.20" apply false
}
```

`android/app/build.gradle.kts`:
```kotlin
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The Gemini key lives in the gitignored local.properties (gemini.apiKey=...), never in the repo.
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.ibrokhim.aikeyboard"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.ibrokhim.aikeyboard"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        buildConfigField("String", "GEMINI_API_KEY", "\"${localProperties.getProperty("gemini.apiKey", "")}\"")
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Compose 1.12 needs compileSdk 37; the 2026.06 BOM (ui 1.11) builds against 36.
    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test:2.3.20")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
}
```

- [ ] **Step 2: Failing test**

`android/app/src/test/java/com/ibrokhim/aikeyboard/reader/ChatLinesTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatLinesTest {
    private val window = WindowBounds(0, 0, 1000, 2000)

    private fun node(text: String, left: Int, top: Int, right: Int, editable: Boolean = false) =
        TextNode(text, left, top, right, top + 60, editable)

    @Test fun tagsHeaderLeftAndRightInReadingOrder() {
        val lines = ChatLines.build(
            listOf(
                node("u free?", 40, 900, 500),
                node("Emma", 100, 100, 300),
                node("yes!", 600, 1000, 960),
                node("hi", 40, 800, 300),
            ),
            window,
        )
        assertEquals(listOf("[TOP] Emma", "[L] hi", "[L] u free?", "[R] yes!"), lines)
    }

    @Test fun draftFieldAndBlankTextAreSkipped() {
        val lines = ChatLines.build(
            listOf(node("hi", 40, 800, 300), node("my draft", 40, 1900, 900, editable = true), node("  ", 40, 850, 300)),
            window,
        )
        assertEquals(listOf("[L] hi"), lines)
    }

    @Test fun consecutiveDuplicatesCollapseAndNewlinesBecomeSpaces() {
        val lines = ChatLines.build(
            listOf(node("see u\nsoon", 600, 800, 960), node("see u soon", 610, 805, 950)),
            window,
        )
        assertEquals(listOf("[R] see u soon"), lines)
    }

    @Test fun keepsTheHeaderAndTheLastFortyMessages() {
        val messages = (1..50).map { node("message $it", 40, 400 + it * 30, 500) }
        val lines = ChatLines.build(listOf(node("Emma", 100, 100, 300)) + messages, window)
        assertEquals(41, lines.size)
        assertEquals("[TOP] Emma", lines.first())
        assertEquals("[L] message 11", lines[1])
        assertEquals("[L] message 50", lines.last())
    }

    @Test fun twoBubblesAreNeededToCountAsAChat() {
        assertTrue(ChatLines.hasMessages(listOf("[TOP] Emma", "[L] hi", "[R] hey")))
        assertFalse(ChatLines.hasMessages(listOf("[TOP] Emma", "[L] hi")))
    }

    @Test fun hashIsStableAndFollowsTheContent() {
        val a = listOf("[TOP] Emma", "[L] hi")
        assertEquals(ChatLines.hash(a), ChatLines.hash(a.toList()))
        assertNotEquals(ChatLines.hash(a), ChatLines.hash(a + "[R] hey"))
    }
}
```

- [ ] **Step 3: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*ChatLinesTest'`
Expected: FAIL — `Unresolved reference 'ChatLines'`.

- [ ] **Step 4: Implementation**

`android/app/src/main/java/com/ibrokhim/aikeyboard/reader/ChatLines.kt`:
```kotlin
package com.ibrokhim.aikeyboard.reader

import java.security.MessageDigest

/** One visible piece of text in the chat app's window, in screen pixels. */
data class TextNode(
    val text: String,
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
    val editable: Boolean,
)

data class WindowBounds(val left: Int, val top: Int, val right: Int, val bottom: Int)

/**
 * Turns a chat window's text into the tagged lines the transcript prompt expects: `[TOP]` for the header
 * (the top 15%), `[L]` for text left of the middle (them), `[R]` for the right (me). Timestamps and UI
 * labels are kept on purpose — the model drops them more reliably than a filter per messenger would.
 */
object ChatLines {
    const val MAX_MESSAGE_LINES = 40
    private const val HEADER_SHARE = 0.15

    fun build(nodes: List<TextNode>, window: WindowBounds): List<String> {
        val headerBottom = window.top + (window.bottom - window.top) * HEADER_SHARE
        val middle = (window.left + window.right) / 2.0
        val header = mutableListOf<String>()
        val messages = mutableListOf<String>()
        var previous: String? = null
        val ordered = nodes.filterNot { it.editable }.sortedWith(compareBy({ it.top }, { it.left }))
        for (node in ordered) {
            val text = node.text.replace('\n', ' ').trim()
            // A bubble's container often repeats its child's text as a content description.
            if (text.isEmpty() || text == previous) continue
            previous = text
            when {
                node.bottom <= headerBottom -> header.add("[TOP] $text")
                (node.left + node.right) / 2.0 < middle -> messages.add("[L] $text")
                else -> messages.add("[R] $text")
            }
        }
        return header + messages.takeLast(MAX_MESSAGE_LINES)
    }

    /** At least two bubbles; fewer means the app draws its text where the tree cannot see it. */
    fun hasMessages(lines: List<String>): Boolean = lines.count { !it.startsWith("[TOP]") } >= 2

    fun hash(lines: List<String>): String =
        MessageDigest.getInstance("SHA-256")
            .digest(lines.joinToString("\n").toByteArray())
            .joinToString("") { "%02x".format(it) }
}
```

- [ ] **Step 5: Run — passes**

Run: `./gradlew :app:testDebugUnitTest --tests '*ChatLinesTest'`
Expected: `BUILD SUCCESSFUL`, 6 test PASS.

- [ ] **Step 6: Commit**

```bash
cd .. && git add android && git commit -m "Android: Compose bog'liqliklari va chat qatorlari (ChatLines)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 2: `ChatReaderService` va `AccessibilityChatSource`

**Files:**
- Create: `.../reader/ChatReaderService.kt`, `.../reader/AccessibilityChatSource.kt`, `android/app/src/main/res/xml/chat_reader.xml`
- Modify: `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/values/strings.xml`
- Temporarily create: `.../ime/KeyboardAi.kt` faqat `ChatSource` interfeysi bilan (Task 3 to'ldiradi)

**Interfaces:**
- Consumes: `ChatLines`, `TextNode`, `WindowBounds` (Task 1); `ChatInput` (M2).
- Produces: `ChatReaderService.instance: ChatReaderService?`, `ChatReaderService.isEnabled(context)`, `fun readLines(packageName: String): List<String>?`, `suspend fun screenshotJpeg(): ByteArray?`; `interface ChatSource { val available: Boolean; suspend fun read(packageName: String): ChatInput? }`; `class AccessibilityChatSource : ChatSource`.

- [ ] **Step 1: Manifest, sozlama, matnlar**

`android/app/src/main/AndroidManifest.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:label="@string/app_name"
        android:supportsRtl="false"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">

        <activity
            android:name=".app.MainActivity"
            android:exported="true"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <activity
            android:name=".app.DemoChatActivity"
            android:exported="false"
            android:windowSoftInputMode="adjustResize" />

        <service
            android:name=".ime.AiKeyboardService"
            android:exported="true"
            android:label="@string/app_name"
            android:permission="android.permission.BIND_INPUT_METHOD">
            <intent-filter>
                <action android:name="android.view.InputMethod" />
            </intent-filter>
            <meta-data
                android:name="android.view.im"
                android:resource="@xml/method" />
        </service>

        <service
            android:name=".reader.ChatReaderService"
            android:exported="true"
            android:label="@string/reader_label"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/chat_reader" />
        </service>
    </application>
</manifest>
```

`android/app/src/main/res/xml/chat_reader.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Reads windows only when the keyboard asks (📖); events are not used. -->
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagRetrieveInteractiveWindows|flagIncludeNotImportantViews"
    android:canRetrieveWindowContent="true"
    android:canTakeScreenshot="true"
    android:description="@string/reader_description"
    android:notificationTimeout="1000" />
```

`android/app/src/main/res/values/strings.xml`:
```xml
<resources>
    <string name="app_name">AI Keyboard</string>
    <string name="subtype_uz">Oʻzbekcha</string>
    <string name="reader_label">AI Keyboard — chatni o\'qish</string>
    <string name="reader_description">Klaviaturadagi 📖 bosilganda yozayotgan ilovangizdagi chat matnini o\'qiydi va tarjima hamda javoblar uchun Gemini\'ga yuboradi. Boshqa paytda hech narsa o\'qimaydi va saqlamaydi.</string>
</resources>
```

- [ ] **Step 2: `ChatSource` (vaqtinchalik fayl)**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeyboardAi.kt` (Task 3 da to'liq fayl bilan almashtiriladi):
```kotlin
package com.ibrokhim.aikeyboard.ime

import com.ibrokhim.aikeyboard.ai.ChatInput

/** Where the keyboard gets the chat from. The Android side is the accessibility service. */
interface ChatSource {
    /** False while the chat reader service is switched off. */
    val available: Boolean

    /** The chat in [packageName]'s window, or null if nothing readable is on screen. */
    suspend fun read(packageName: String): ChatInput?
}
```

- [ ] **Step 3: Xizmat va manba**

`android/app/src/main/java/com/ibrokhim/aikeyboard/reader/ChatReaderService.kt`:
```kotlin
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
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/reader/AccessibilityChatSource.kt`:
```kotlin
package com.ibrokhim.aikeyboard.reader

import com.ibrokhim.aikeyboard.ai.ChatInput
import com.ibrokhim.aikeyboard.ime.ChatSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Text first (fast, cheap, exact); a screenshot only when the app shows no readable bubbles. */
class AccessibilityChatSource : ChatSource {
    override val available: Boolean
        get() = ChatReaderService.instance != null

    override suspend fun read(packageName: String): ChatInput? {
        val service = ChatReaderService.instance ?: return null
        val lines = withContext(Dispatchers.Default) { service.readLines(packageName) }
        if (lines != null && ChatLines.hasMessages(lines)) return ChatInput.Transcript(lines)
        val jpeg = service.screenshotJpeg() ?: return null
        return ChatInput.Screenshot(jpeg)
    }
}
```

- [ ] **Step 4: Build**

Run: `./gradlew :app:testDebugUnitTest :app:assembleDebug`
Expected: `BUILD SUCCESSFUL`, avvalgi testlar PASS.

- [ ] **Step 5: Commit**

```bash
cd .. && git add android && git commit -m "Android: chatni o'qiydigan Accessibility xizmati (matn, zaxira skrinshot)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 3: `KeyboardAi` (📖, ✨, tanlash, maqsad)

**Files:**
- Modify: `.../ime/KeyboardController.kt` (`InputTarget`), `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/KeyboardControllerTest.kt` (`FakeTarget`)
- Create (almashtiradi): `.../ime/KeyboardAi.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/KeyboardAiTest.kt`

**Interfaces:**
- Consumes: `SharedStore`, `Friend`, `Suggestion` (M2); `Translator`, `ChatAnalysisService`, `ChatInput` (M2); `InputTarget` (M1).
- Produces: `InputTarget.currentText(): String`, `InputTarget.replaceAll(text: String)`; `data class AiUiState(variants, rewriting, notice, pickerOpen)`; `class KeyboardAi(store, translator, analysis, target, chatSource, scope, clock = System::currentTimeMillis, openReaderSetup: () -> Unit = {})` with `val ui: StateFlow<AiUiState>`, `readChat(packageName: String?)`, `magic()`, `pick(suggestion)`, `dismissVariants()`, `dismissContext()`, `togglePicker()`, `selectFriend(friend)`, `selectLanguage(language)`; `object Notices { READER_OFF, UNREADABLE, WRITE_FIRST, PICK_OR_WRITE, FAILED }`.

- [ ] **Step 1: `InputTarget` kengaytmasi**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeyboardController.kt` — `InputTarget` interfeysini quyidagiga almashtiring (fayldagi qolgan kod o'zgarmaydi):
```kotlin
/** What the controller types into. `AiKeyboardService` backs it with the current `InputConnection`. */
interface InputTarget {
    fun textBeforeCursor(length: Int): String
    fun commit(text: String)
    fun deleteBackward()
    fun moveCursor(offset: Int)
    fun enter()
    fun switchKeyboard()

    /** The whole field — in a DM that is just the draft. */
    fun currentText(): String

    /** Replaces the whole field: a picked reply or ✨ variant replaces the draft. */
    fun replaceAll(text: String)

    /** False for passwords, emails, URLs and fields that do not ask for capitals. */
    val autoCapitalize: Boolean
}
```

`KeyboardControllerTest.kt` dagi `FakeTarget` ichiga `switchKeyboard()`dan keyin qo'shing:
```kotlin
        override fun currentText() = text.toString()
        override fun replaceAll(text: String) {
            this.text.clear()
            this.text.append(text)
        }
```

- [ ] **Step 2: Failing test**

`android/app/src/test/java/com/ibrokhim/aikeyboard/ime/KeyboardAiTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import com.ibrokhim.aikeyboard.ai.ChatAnalysisService
import com.ibrokhim.aikeyboard.ai.ChatInput
import com.ibrokhim.aikeyboard.ai.LlmClient
import com.ibrokhim.aikeyboard.ai.Part
import com.ibrokhim.aikeyboard.ai.Translator
import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.data.Suggestion
import java.io.File
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class KeyboardAiTest {
    @get:Rule val folder = TemporaryFolder()

    private class Field : InputTarget {
        val text = StringBuilder()
        override val autoCapitalize = false
        override fun textBeforeCursor(length: Int) = text.takeLast(length).toString()
        override fun commit(text: String) {
            this.text.append(text)
        }
        override fun deleteBackward() = Unit
        override fun moveCursor(offset: Int) = Unit
        override fun enter() = Unit
        override fun switchKeyboard() = Unit
        override fun currentText() = text.toString()
        override fun replaceAll(text: String) {
            this.text.clear()
            this.text.append(text)
        }
    }

    private class Source(var input: ChatInput? = null) : ChatSource {
        val asked = mutableListOf<String>()
        override var available = true
        override suspend fun read(packageName: String): ChatInput? {
            asked.add(packageName)
            return input
        }
    }

    private class Llm : LlmClient {
        override suspend fun generate(system: String, parts: List<Part>, schema: JsonObject): String = when {
            system.contains("- partner:") ->
                """{"partner":"Emma","language":"English","tone":"casual","last_incoming_uz":"Bo'shmisan?"}"""
            system.contains("- suggestions:") ->
                """{"summary_uz":"x","transcript":[{"from":"them","text":"u free?"}],"suggestions":[{"text":"yes!","uz":"ha!"}]}"""
            else -> """{"variants":[{"text":"we're getting plov on saturday","uz":"Shanba kuni osh yeymiz"}]}"""
        }
    }

    private val field = Field()
    private val source = Source(input = ChatInput.Transcript(listOf("[TOP] Emma", "[L] u free?", "[R] maybe")))
    private var setupOpened = 0

    private fun TestScope.ai(): Pair<KeyboardAi, SharedStore> {
        val store = SharedStore(File(folder.root, "state.json"))
        val translator = Translator(Llm())
        val analysis = ChatAnalysisService(store, translator) { 1_000 }
        return KeyboardAi(store, translator, analysis, field, source, this, { 1_000 }) { setupOpened++ } to store
    }

    @Test fun readChatAnalysesTheChatOfTheFocusedApp() = runTest {
        val (ai, store) = ai()
        ai.readChat("com.example.chat")
        advanceUntilIdle()
        assertEquals(listOf("com.example.chat"), source.asked)
        assertEquals("Emma", store.value.context?.partner)
        assertEquals("yes!", store.value.context?.suggestions?.single()?.text)
    }

    @Test fun readerOffExplainsAndOpensSetup() = runTest {
        val (ai, _) = ai()
        source.available = false
        ai.readChat("com.example.chat")
        assertEquals(Notices.READER_OFF, ai.ui.value.notice)
        assertEquals(1, setupOpened)
        advanceTimeBy(KeyboardAi.NOTICE_MS + 1)
        assertNull(ai.ui.value.notice)
    }

    @Test fun unreadableChatSaysSo() = runTest {
        val (ai, store) = ai()
        source.input = null
        ai.readChat("com.example.chat")
        advanceTimeBy(1)
        assertEquals(Notices.UNREADABLE, ai.ui.value.notice)
        assertNull(store.value.context)
    }

    @Test fun magicWithoutADraftAsksForOne() = runTest {
        val (ai, _) = ai()
        ai.magic()
        assertEquals(Notices.WRITE_FIRST, ai.ui.value.notice)
    }

    @Test fun magicRewritesTheDraftAndPickReplacesIt() = runTest {
        val (ai, _) = ai()
        field.text.append("shanba kuni plov yeymiz")
        ai.magic()
        advanceUntilIdle()
        assertEquals("we're getting plov on saturday", ai.ui.value.variants.single().text)
        assertFalse(ai.ui.value.rewriting)
        ai.pick(ai.ui.value.variants.single())
        assertEquals("we're getting plov on saturday", field.text.toString())
        assertEquals(emptyList<Suggestion>(), ai.ui.value.variants)
    }

    @Test fun pickerSelectionsSetTheTarget() = runTest {
        val (ai, store) = ai()
        ai.togglePicker()
        assertEquals(true, ai.ui.value.pickerOpen)
        ai.selectFriend(Friend("Minji", "Korean", "friendly", 0))
        assertEquals("Minji", store.value.activeFriend)
        assertEquals("Korean", store.value.targetLanguage)
        assertFalse(ai.ui.value.pickerOpen)
        ai.selectLanguage("Turkish")
        assertNull(store.value.activeFriend)
        assertEquals("Turkish", store.value.targetLanguage)
    }

    @Test fun dismissContextClearsIt() = runTest {
        val (ai, store) = ai()
        store.update { it.copy(context = ChatAnalysis(partner = "Emma"), contextDate = 1_000) }
        ai.dismissContext()
        assertNull(store.value.context)
    }
}
```

- [ ] **Step 3: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*KeyboardAiTest'`
Expected: FAIL — `Unresolved reference 'KeyboardAi'`.

- [ ] **Step 4: Implementation**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeyboardAi.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import com.ibrokhim.aikeyboard.ai.ChatAnalysisService
import com.ibrokhim.aikeyboard.ai.ChatInput
import com.ibrokhim.aikeyboard.ai.Translator
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.data.Suggestion
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Where the keyboard gets the chat from. The Android side is the accessibility service. */
interface ChatSource {
    /** False while the chat reader service is switched off. */
    val available: Boolean

    /** The chat in [packageName]'s window, or null if nothing readable is on screen. */
    suspend fun read(packageName: String): ChatInput?
}

/** Keyboard-local AI state; the shared part (context, friends, target) lives in `SharedStore`. */
data class AiUiState(
    val variants: List<Suggestion> = emptyList(),
    val rewriting: Boolean = false,
    val notice: String? = null,
    val pickerOpen: Boolean = false,
)

object Notices {
    const val READER_OFF = "Chatni o'qish uchun Sozlamalar → Accessibility → AI Keyboard'ni yoqing"
    const val UNREADABLE = "Bu ilovadan chatni o'qib bo'lmadi"
    const val WRITE_FIRST = "Avval o'zbekcha yozing, keyin ✨ ni bosing"
    const val PICK_OR_WRITE = "Tayyor javoblardan birini tanlang yoki o'zbekcha yozib ✨ ni bosing"
    const val FAILED = "Xatolik yuz berdi"
}

/** The keyboard's AI actions — 📖, ✨, picking a reply, choosing the target — the AI half of iOS `KeyboardModel`. */
class KeyboardAi(
    private val store: SharedStore,
    private val translator: Translator,
    private val analysis: ChatAnalysisService,
    private val target: InputTarget,
    private val chatSource: ChatSource,
    private val scope: CoroutineScope,
    private val clock: () -> Long = System::currentTimeMillis,
    private val openReaderSetup: () -> Unit = {},
) {
    private val state = MutableStateFlow(AiUiState())
    val ui: StateFlow<AiUiState> = state

    private var readJob: Job? = null
    private var rewriteJob: Job? = null
    private var rewriteToken = 0
    private var noticeJob: Job? = null

    /** 📖 — read the chat of the app being typed into and analyse it. */
    fun readChat(packageName: String?) {
        if (!chatSource.available) {
            flash(Notices.READER_OFF)
            openReaderSetup()
            return
        }
        if (packageName == null) {
            flash(Notices.UNREADABLE)
            return
        }
        state.update { it.copy(variants = emptyList(), pickerOpen = false) }
        readJob?.cancel()
        readJob = scope.launch {
            val input = chatSource.read(packageName)
            if (input == null) {
                flash(Notices.UNREADABLE)
                return@launch
            }
            try {
                analysis.run(input)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // ChatAnalysisService already put the error into the store; the bar shows it.
            }
        }
    }

    /** ✨ — rewrite the draft into the conversation language, fitted to the chat. */
    fun magic() {
        val draft = target.currentText().trim()
        val shared = store.value
        val now = clock()
        if (draft.isEmpty()) {
            flash(if (shared.freshContext(now) == null) Notices.WRITE_FIRST else Notices.PICK_OR_WRITE)
            return
        }
        rewriteJob?.cancel()
        val token = ++rewriteToken
        state.update { it.copy(rewriting = true, pickerOpen = false) }
        rewriteJob = scope.launch {
            try {
                val variants = translator.rewrite(
                    draft, shared.freshContext(now), shared.activeFriendProfile(now), shared.language(now),
                )
                state.update { it.copy(variants = variants) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                flash(e.message ?: Notices.FAILED)
            } finally {
                if (token == rewriteToken) state.update { it.copy(rewriting = false) }
            }
        }
    }

    fun pick(suggestion: Suggestion) {
        target.replaceAll(suggestion.text)
        state.update { it.copy(variants = emptyList()) }
    }

    fun dismissVariants() = state.update { it.copy(variants = emptyList()) }

    fun dismissContext() {
        store.update { it.copy(context = null, contextDate = null) }
        state.update { it.copy(variants = emptyList()) }
    }

    fun togglePicker() = state.update { it.copy(pickerOpen = !it.pickerOpen) }

    fun selectFriend(friend: Friend) {
        store.update { it.copy(activeFriend = friend.name, targetLanguage = friend.language) }
        state.update { it.copy(pickerOpen = false) }
    }

    fun selectLanguage(language: String) {
        store.update { it.copy(targetLanguage = language, activeFriend = null) }
        state.update { it.copy(pickerOpen = false) }
    }

    private fun flash(text: String) {
        state.update { it.copy(notice = text) }
        noticeJob?.cancel()
        noticeJob = scope.launch {
            delay(NOTICE_MS)
            state.update { if (it.notice == text) it.copy(notice = null) else it }
        }
    }

    companion object {
        const val NOTICE_MS = 4_000L
    }
}
```

- [ ] **Step 5: Run — passes**

Run: `./gradlew :app:testDebugUnitTest`
Expected: `BUILD SUCCESSFUL`, `KeyboardAiTest` 7 PASS, qolganlari PASS.

- [ ] **Step 6: Commit**

```bash
cd .. && git add android && git commit -m "Android: KeyboardAi — chatni o'qish, ✨, javob tanlash va maqsad

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 4: `BarModel` va Compose panel

**Files:**
- Create: `.../ime/ui/BarModel.kt`, `.../ime/ui/SuggestionBar.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/ui/BarModelTest.kt`

**Interfaces:**
- Consumes: `SharedState`, `Friend`, `Suggestion`, `Languages` (M2); `AiUiState`, `KeyboardAi` (Task 3); `KeyboardTheme` (M1).
- Produces: `sealed interface Status { Notice(text); Reading; Translation(partner, text); Variants; Failed(message); Idle(target) }`, `sealed interface Chips { None; Preparing; Replies(items); Picker(friends, languages) }`, `data class BarModel(status, chips, rewriting) { val expanded }`, `fun barModel(state: SharedState, ui: AiUiState, now: Long): BarModel`, `fun targetLabel(state: SharedState, now: Long): String`; `@Composable fun SuggestionBar(model: BarModel, theme: KeyboardTheme, ai: KeyboardAi, onRead: () -> Unit)`.

- [ ] **Step 1: Failing test**

`android/app/src/test/java/com/ibrokhim/aikeyboard/ime/ui/BarModelTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime.ui

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.SharedState
import com.ibrokhim.aikeyboard.data.Suggestion
import com.ibrokhim.aikeyboard.ime.AiUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BarModelTest {
    private val now = 10_000_000L
    private val emma = Friend("Emma", "English", "casual", now)
    private val idle = AiUiState()

    @Test fun idleShowsTheTargetWithTheActiveFriendAndStaysCompact() {
        val model = barModel(SharedState(targetLanguage = "English", activeFriend = "Emma", friends = listOf(emma)), idle, now)
        assertEquals(Status.Idle("✨ → 🇬🇧 English · Emma"), model.status)
        assertEquals(Chips.None, model.chips)
        assertFalse(model.expanded)
    }

    @Test fun readingShowsBothPlaceholders() {
        val model = barModel(SharedState(analyzingSince = now), idle, now)
        assertEquals(Status.Reading, model.status)
        assertEquals(Chips.Preparing, model.chips)
        assertTrue(model.expanded)
    }

    @Test fun translationArrivesBeforeTheReplies() {
        val quickOnly = ChatAnalysis(partner = "Emma", lastIncomingUz = "Bo'shmisan?")
        val reading = SharedState(context = quickOnly, contextDate = now, analyzingSince = now)
        assertEquals(Status.Translation("Emma", "Bo'shmisan?"), barModel(reading, idle, now).status)
        assertEquals(Chips.Preparing, barModel(reading, idle, now).chips)

        val replies = listOf(Suggestion("yes!", "ha!"))
        val done = SharedState(context = quickOnly.copy(suggestions = replies), contextDate = now)
        assertEquals(Chips.Replies(replies), barModel(done, idle, now).chips)
    }

    @Test fun variantsAndNoticesTakeOver() {
        val variants = listOf(Suggestion("we're getting plov on saturday", "Shanba kuni osh yeymiz"))
        val withVariants = barModel(SharedState(), AiUiState(variants = variants), now)
        assertEquals(Status.Variants, withVariants.status)
        assertEquals(Chips.Replies(variants), withVariants.chips)
        assertEquals(Status.Notice("x"), barModel(SharedState(), AiUiState(notice = "x", variants = variants), now).status)
    }

    @Test fun recentErrorIsShownUntilItExpires() {
        val state = SharedState(lastError = "Gemini javob bermadi", lastErrorDate = now)
        assertEquals(Status.Failed("Gemini javob bermadi"), barModel(state, idle, now).status)
        assertTrue(barModel(state, idle, now + 120_000).status is Status.Idle)
    }

    @Test fun staleContextFallsBackToIdle() {
        val state = SharedState(context = ChatAnalysis(partner = "Emma", language = "English"), contextDate = now - 16 * 60_000)
        assertTrue(barModel(state, idle, now).status is Status.Idle)
    }

    @Test fun pickerListsFriendsAndOtherLanguages() {
        val model = barModel(SharedState(targetLanguage = "Korean", friends = listOf(emma)), AiUiState(pickerOpen = true), now)
        val picker = model.chips as Chips.Picker
        assertEquals(listOf(emma), picker.friends)
        assertFalse(picker.languages.contains("Korean"))
        assertTrue(picker.languages.contains("English"))
    }

    @Test fun rewritingSpinsTheMagicButton() {
        assertTrue(barModel(SharedState(), AiUiState(rewriting = true), now).rewriting)
    }
}
```

- [ ] **Step 2: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*BarModelTest'`
Expected: FAIL — `Unresolved reference 'barModel'`.

- [ ] **Step 3: `BarModel`**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/ui/BarModel.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime.ui

import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.Languages
import com.ibrokhim.aikeyboard.data.SharedState
import com.ibrokhim.aikeyboard.data.Suggestion
import com.ibrokhim.aikeyboard.ime.AiUiState

/** The status row: what the keyboard is doing or showing right now. */
sealed interface Status {
    data class Notice(val text: String) : Status
    data object Reading : Status
    data class Translation(val partner: String, val text: String) : Status
    data object Variants : Status
    data class Failed(val message: String) : Status
    data class Idle(val target: String) : Status
}

/** The chip row under it; `None` collapses the bar to the status row. */
sealed interface Chips {
    data object None : Chips
    data object Preparing : Chips
    data class Replies(val items: List<Suggestion>) : Chips
    data class Picker(val friends: List<Friend>, val languages: List<String>) : Chips
}

data class BarModel(val status: Status, val chips: Chips, val rewriting: Boolean) {
    val expanded: Boolean get() = chips != Chips.None
}

fun barModel(state: SharedState, ui: AiUiState, now: Long): BarModel {
    val context = state.freshContext(now)
    val analyzing = state.isAnalyzing(now)
    val error = state.recentError(now)
    val status = when {
        ui.notice != null -> Status.Notice(ui.notice)
        ui.variants.isNotEmpty() -> Status.Variants
        context != null -> Status.Translation(context.partner, context.lastIncomingUz)
        analyzing -> Status.Reading
        error != null -> Status.Failed(error)
        else -> Status.Idle(targetLabel(state, now))
    }
    val chips = when {
        ui.variants.isNotEmpty() -> Chips.Replies(ui.variants)
        context != null && context.suggestions.isNotEmpty() -> Chips.Replies(context.suggestions)
        analyzing -> Chips.Preparing
        ui.pickerOpen -> Chips.Picker(state.friends, Languages.common.filter { it != state.language(now) })
        else -> Chips.None
    }
    return BarModel(status, chips, ui.rewriting)
}

/** "✨ → 🇬🇧 English · Emma": where ✨ writes to when there is no chat on screen. */
fun targetLabel(state: SharedState, now: Long): String {
    val language = state.language(now)
    val friend = state.activeFriendProfile(now)?.name
    return "✨ → ${Languages.flag(language)} $language" + (friend?.let { " · $it" } ?: "")
}
```

- [ ] **Step 4: Run — passes**

Run: `./gradlew :app:testDebugUnitTest --tests '*BarModelTest'`
Expected: `BUILD SUCCESSFUL`, 8 test PASS.

- [ ] **Step 5: Compose panel**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/ui/SuggestionBar.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ibrokhim.aikeyboard.data.Languages
import com.ibrokhim.aikeyboard.data.Suggestion
import com.ibrokhim.aikeyboard.ime.KeyboardAi
import com.ibrokhim.aikeyboard.ime.KeyboardTheme

private class BarColors(theme: KeyboardTheme) {
    val background = Color(theme.background)
    val ink = Color(theme.label)
    val muted = Color(theme.label).copy(alpha = 0.6f)
    val chip = Color(theme.key)
    val accent = Color(theme.accent)
    val onAccent = Color(theme.onAccent)
}

/** Status row (+ chip row when it has something) above the keys — the iOS `SuggestionBar`. */
@Composable
fun SuggestionBar(model: BarModel, theme: KeyboardTheme, ai: KeyboardAi, onRead: () -> Unit) {
    val colors = BarColors(theme)
    Column(
        Modifier
            .fillMaxWidth()
            .background(colors.background)
            .padding(start = 8.dp, end = 8.dp, top = 6.dp, bottom = if (model.expanded) 4.dp else 6.dp),
    ) {
        Row(Modifier.fillMaxWidth().height(36.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { StatusRow(model.status, colors, ai, onRead) }
            Spacer(Modifier.width(8.dp))
            MagicButton(model.rewriting, colors) { ai.magic() }
        }
        if (model.expanded) {
            Spacer(Modifier.height(6.dp))
            Box(Modifier.fillMaxWidth().height(58.dp)) { ChipRow(model.chips, colors, ai) }
        }
    }
}

@Composable
private fun StatusRow(status: Status, colors: BarColors, ai: KeyboardAi, onRead: () -> Unit) {
    when (status) {
        is Status.Notice -> Line(status.text, colors.muted)
        Status.Reading -> Busy("Suhbat o'qilmoqda…", colors)
        is Status.Translation -> Row(verticalAlignment = Alignment.CenterVertically) {
            val who = status.partner.ifEmpty { "Suhbatdosh" }
            Text(
                "💬 $who: ${status.text}", color = colors.ink, fontSize = 13.sp, lineHeight = 16.sp,
                maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
            Close(colors) { ai.dismissContext() }
        }
        Status.Variants -> Row(verticalAlignment = Alignment.CenterVertically) {
            Text("✨ Variantlar — birini tanlang", color = colors.ink, fontSize = 13.sp, modifier = Modifier.weight(1f))
            Close(colors) { ai.dismissVariants() }
        }
        is Status.Failed -> Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "⚠ ${status.message}", color = colors.muted, fontSize = 13.sp, maxLines = 1,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
            Pill("📖 Qayta", colors, accent = true, onClick = onRead)
        }
        is Status.Idle -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Pill("📖 Chatni o'qish", colors, accent = true, onClick = onRead)
            Pill(status.target + " ▾", colors, accent = false) { ai.togglePicker() }
        }
    }
}

@Composable
private fun ChipRow(chips: Chips, colors: BarColors, ai: KeyboardAi) {
    when (chips) {
        Chips.None -> Unit
        Chips.Preparing -> Busy("Javoblar tayyorlanmoqda…", colors)
        is Chips.Replies -> LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(chips.items) { suggestion -> ReplyChip(suggestion, colors) { ai.pick(suggestion) } }
        }
        is Chips.Picker -> LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items(chips.friends) { friend ->
                Pill("${friend.name} · ${Languages.flag(friend.language)}", colors, accent = false) { ai.selectFriend(friend) }
            }
            items(chips.languages) { language ->
                Pill("${Languages.flag(language)} $language", colors, accent = false) { ai.selectLanguage(language) }
            }
        }
    }
}

@Composable
private fun ReplyChip(suggestion: Suggestion, colors: BarColors, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxHeight()
            .widthIn(max = 250.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(colors.chip)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            suggestion.text, color = colors.ink, fontSize = 14.sp, lineHeight = 17.sp,
            fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
        Text(suggestion.uz, color = colors.muted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Pill(text: String, colors: BarColors, accent: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .height(32.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(if (accent) colors.accent else colors.chip)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text, color = if (accent) colors.onAccent else colors.ink, fontSize = 13.sp,
            fontWeight = FontWeight.Medium, maxLines = 1,
        )
    }
}

@Composable
private fun MagicButton(rewriting: Boolean, colors: BarColors, onClick: () -> Unit) {
    Box(
        Modifier
            .size(width = 48.dp, height = 32.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(colors.accent)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (rewriting) {
            CircularProgressIndicator(Modifier.size(16.dp), color = colors.onAccent, strokeWidth = 2.dp)
        } else {
            Text("✨", fontSize = 16.sp)
        }
    }
}

@Composable
private fun Close(colors: BarColors, onClick: () -> Unit) {
    Box(
        Modifier.size(28.dp).clip(CircleShape).background(colors.chip).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text("✕", color = colors.muted, fontSize = 13.sp)
    }
}

@Composable
private fun Busy(text: String, colors: BarColors) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxHeight()) {
        CircularProgressIndicator(Modifier.size(14.dp), color = colors.accent, strokeWidth = 2.dp)
        Spacer(Modifier.width(8.dp))
        Text(text, color = colors.muted, fontSize = 13.sp)
    }
}

@Composable
private fun Line(text: String, color: Color) {
    Text(text, color = color, fontSize = 13.sp, lineHeight = 16.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
}
```

- [ ] **Step 6: Build**

Run: `./gradlew :app:testDebugUnitTest :app:assembleDebug`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 7: Commit**

```bash
cd .. && git add android && git commit -m "Android: takliflar paneli — BarModel va Compose ko'rinishi

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 5: Servisga ulash, demo chat va emulyatorda to'liq oqim

**Files:**
- Modify: `.../ime/KeysView.kt`, `.../ime/AiKeyboardService.kt` (to'liq almashtiriladi), `.../app/MainActivity.kt`
- Create: `.../app/DemoChatActivity.kt`

**Interfaces:**
- Consumes: hammasi (Tasks 1–4, M1, M2).
- Produces: `KeysView.setNavigationInset(px: Int)`; ilova ichida `DemoChatActivity`.

- [ ] **Step 1: `KeysView` — inset tashqaridan, joy o'zgarsa log**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeysView.kt` da:

1. `init` blokini quyidagiga almashtiring (inset listener servisga ko'chadi — panel `ComposeView` inset'larni o'ziga olib qolishi mumkin):
```kotlin
    init {
        setBackgroundColor(theme.background)
    }

    /** Android 15+ draws the keyboard behind the navigation bar; the service passes its height here. */
    fun setNavigationInset(px: Int) {
        if (px != navigationInset) {
            navigationInset = px
            requestLayout()
        }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        // The bar above grows and shrinks, which moves the keys on screen.
        if (changed) logLayoutSoon()
    }
```
2. Endi ishlatilmaydigan importlarni olib tashlang: `import android.os.Build`, `import android.view.WindowInsets`.

- [ ] **Step 2: Servis**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/AiKeyboardService.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import android.content.Intent
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.LinearLayout
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.ibrokhim.aikeyboard.BuildConfig
import com.ibrokhim.aikeyboard.ai.ChatAnalysisService
import com.ibrokhim.aikeyboard.ai.GeminiClient
import com.ibrokhim.aikeyboard.ai.OkHttpGeminiTransport
import com.ibrokhim.aikeyboard.ai.Translator
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.ime.ui.SuggestionBar
import com.ibrokhim.aikeyboard.ime.ui.barModel
import com.ibrokhim.aikeyboard.reader.AccessibilityChatSource
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

class AiKeyboardService : InputMethodService(), LifecycleOwner, SavedStateRegistryOwner {
    // Compose in an input method needs the owners an Activity would normally provide.
    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateController = SavedStateRegistryController.create(this)
    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val savedStateRegistry: SavedStateRegistry get() = savedStateController.savedStateRegistry

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val prefs by lazy { getSharedPreferences("keyboard", MODE_PRIVATE) }
    private lateinit var controller: KeyboardController
    private lateinit var store: SharedStore
    private lateinit var ai: KeyboardAi
    private var keysView: KeysView? = null
    private var editorInfo: EditorInfo? = null
    private var savedAlphabet = Alphabet.LATIN
    /** Compose state, so the bar recolours when the system switches light/dark. */
    private val barTheme = mutableStateOf<KeyboardTheme?>(null)

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

        override fun currentText(): String {
            val ic = currentInputConnection ?: return ""
            val before = ic.getTextBeforeCursor(MAX_FIELD, 0)?.toString().orEmpty()
            val after = ic.getTextAfterCursor(MAX_FIELD, 0)?.toString().orEmpty()
            return before + after
        }

        override fun replaceAll(text: String) {
            val ic = currentInputConnection ?: return
            val before = ic.getTextBeforeCursor(MAX_FIELD, 0)?.length ?: 0
            val after = ic.getTextAfterCursor(MAX_FIELD, 0)?.length ?: 0
            ic.beginBatchEdit()
            ic.deleteSurroundingText(before, after)
            ic.commitText(text, 1) // also replaces a selection, if there was one
            ic.endBatchEdit()
        }

        override val autoCapitalize: Boolean
            get() = EditorRules.autoCapitalize(editorInfo?.inputType ?: 0)
    }

    override fun onCreate() {
        super.onCreate()
        savedStateController.performRestore(null)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_START)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)

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

        store = SharedStore.get(this)
        val translator = Translator(GeminiClient(OkHttpGeminiTransport(), { BuildConfig.GEMINI_API_KEY }))
        ai = KeyboardAi(
            store, translator, ChatAnalysisService(store, translator), target, AccessibilityChatSource(), scope,
            openReaderSetup = ::openReaderSettings,
        )
        barTheme.value = KeyboardTheme.from(this)
    }

    override fun onCreateInputView(): View {
        window.window?.decorView?.let {
            it.setViewTreeLifecycleOwner(this)
            it.setViewTreeSavedStateRegistryOwner(this)
        }
        val keys = KeysView(this, controller).also { keysView = it }
        val bar = ComposeView(this).apply {
            setContent {
                val shared by store.state.collectAsState()
                val ui by ai.ui.collectAsState()
                barTheme.value?.let { current ->
                    SuggestionBar(barModel(shared, ui, System.currentTimeMillis()), current, ai) {
                        ai.readChat(editorInfo?.packageName)
                    }
                }
            }
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(bar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(keys, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            if (Build.VERSION.SDK_INT >= 30) {
                setOnApplyWindowInsetsListener { _, insets ->
                    keys.setNavigationInset(insets.getInsets(WindowInsets.Type.navigationBars()).bottom)
                    insets
                }
            }
        }
    }

    /** The keyboard never takes over the whole screen in landscape. */
    override fun onEvaluateFullscreenMode() = false

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        editorInfo = info
        controller.showsGlobe = if (Build.VERSION.SDK_INT >= 28) shouldOfferSwitchingToNextInputMethod() else true
        val current = KeyboardTheme.from(this)
        barTheme.value = current
        keysView?.apply {
            this.theme = current
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

    override fun onDestroy() {
        scope.cancel()
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        super.onDestroy()
    }

    private fun openReaderSettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { startActivity(intent) }
    }

    private companion object {
        const val MAX_FIELD = 10_000
    }
}
```

- [ ] **Step 3: Demo chat**

`android/app/src/main/java/com/ibrokhim/aikeyboard/app/DemoChatActivity.kt`:
```kotlin
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
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/app/MainActivity.kt`:
```kotlin
package com.ibrokhim.aikeyboard.app

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.WindowInsets
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/** Stand-in until milestone 5: a field to type into and the demo chat. Setup steps replace it later. */
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
        root.addView(Button(this).apply {
            text = "Demo chatni ochish"
            setOnClickListener { startActivity(Intent(this@MainActivity, DemoChatActivity::class.java)) }
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
```

- [ ] **Step 4: Build va testlar**

Run: `./gradlew :app:testDebugUnitTest :app:assembleDebug`
Expected: `BUILD SUCCESSFUL`, barcha testlar PASS (Live test SKIPPED).

- [ ] **Step 5: Emulyatorda to'liq oqim**

Run (emulyator yoqilgan, `ANDROID_SERIAL=emulator-5554`, scratchpad `android-reinstall.sh` — M1 dan):
```bash
android-reinstall.sh
$ADB shell settings put secure enabled_accessibility_services com.ibrokhim.aikeyboard/com.ibrokhim.aikeyboard.reader.ChatReaderService
$ADB shell settings put secure accessibility_enabled 1
$ADB shell am start -n com.ibrokhim.aikeyboard/.app.DemoChatActivity
```
Keyin: `Message…` maydonini bosish → skrinshot (panelda "📖 Chatni o'qish" va maqsad chipi) → `uiautomator dump` dan "📖 Chatni o'qish" markazini bosish → 2–10 s ichida skrinshot: "💬 Emma: …" tarjimasi va 3 ta javob chipi → birinchi chipni bosish → maydon matni = javob → maydonni tozalab `android/tools/adb-type.py "shanba kuni plov yeymiz"` → ✨ → variantlar → birinchisini bosish → maydonda inglizcha matn.

Expected: har bosqich skrinshot va `uiautomator dump` bilan tasdiqlanadi.

- [ ] **Step 6: Commit**

```bash
cd .. && git add android && git commit -m "Android: panel klaviaturaga ulandi, demo chat — 📖 → tarjima → javob → ✨ emulyatorda ishlaydi

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

## Keyingi rejalar

M4 (emoji paneli, popup'lar, tebranish/ovoz, `ContextDetails`, avtomatik o'qish), M5 (sozlash ekrani va Accessibility tushuntirishi, foydalanuvchi API kaliti, README, APK).

## Eslatma

- Demo chat spec'da M5 (sozlash ekranidagi "Sinov") edi — 📖 ni emulyatorda sinash uchun M3 ga ko'chdi.
- Tarjima qatori bosilganda `ContextDetails` M4 da (hozir faqat ✕).
