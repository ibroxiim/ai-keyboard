# Android M1 — skelet va ishlaydigan klaviatura: implementatsiya rejasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `android/` da Gradle loyiha va Android klaviatura (IME): lotin/kirill harflar, raqamlar, belgilar qatlamlari, shift, avtomatik katta harf, ikki probel → ". ", backspace takrori, probel bilan kursor — emulyatorda yozish ishlaydi.

**Architecture:** Toza Kotlin mantiq (`KeyLayouts`, `TextRules`, `EditorRules`, `KeyboardController`) Android'ga bog'liq emas va JVM testlari bilan yopilgan. `KeysView` (Canvas) chizadi va touch'ni `KeyboardController`ga uzatadi; `AiKeyboardService` controller'ni `InputConnection`ga ulaydi. Spec: `docs/superpowers/specs/2026-09-25-android-version-design.md` (1-bosqich). 2–5-bosqichlar alohida rejalar bo'ladi.

**Tech Stack:** Kotlin 2.3.20, AGP 9.0.1, Gradle 9.1.0, JDK 21 (Android Studio JBR), JUnit 4.13.2, Android SDK 36, emulyator `Pixel_9_Pro` (Android 17, 1280×2856, 480 dpi).

## Global Constraints

- Package va applicationId: `com.ibrokhim.aikeyboard`; minSdk 26, targetSdk 36, compileSdk 36, jvmTarget 17.
- Kotlin `org.jetbrains.kotlin.android` plugini orqali: `android.builtInKotlin=false`, `android.newDsl=false` (Mac'dagi Flutter loyihasida ishlayotgan sozlama).
- Buyruqlar oldidan: `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`; `ADB=~/Library/Android/sdk/platform-tools/adb`.
- `android/local.properties` gitignore'da; API kalit hech qachon commit qilinmaydi (M1 da kalit yo'q).
- UI matnlari o'zbekcha; kod, izohlar va nomlar inglizcha. Haqiqiy DM ismlari/matnlari hech qayerga yozilmaydi.
- Commit xabarlari o'zbekcha, oxirida `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Faqat `android/` va reja fayllari commit qilinadi — repodagi boshqa commit qilinmagan iOS o'zgarishlariga tegilmaydi (`git commit -- <paths>`).
- Branch: `android`. Push qilinmaydi.

## Fayllar

| Fayl | Vazifasi |
|---|---|
| `android/settings.gradle.kts`, `android/build.gradle.kts`, `android/gradle.properties`, `android/.gitignore`, `android/gradlew*`, `android/gradle/wrapper/*` | Gradle loyiha |
| `android/app/build.gradle.kts` | app moduli |
| `android/app/src/main/AndroidManifest.xml`, `res/xml/method.xml`, `res/values/strings.xml` | IME va sinov ekrani e'loni |
| `.../ime/KeyLayouts.kt` | Tugma turlari, qatlam jadvallari, qator kengliklari (sof) |
| `.../ime/TextRules.kt` | Gap boshi va ikki probel qoidalari (sof) |
| `.../ime/EditorRules.kt` | Enter harakati va avtomatik katta harf `EditorInfo`dan (sof) |
| `.../ime/KeyboardController.kt` | Klaviatura holati va matn kiritish; `InputTarget` orqali |
| `.../ime/KeyboardTheme.kt` | Yorug'/tungi ranglar |
| `.../ime/KeysView.kt` | Tugmalarni chizish, multi-touch, takror, kursor |
| `.../ime/AiKeyboardService.kt` | `InputMethodService` — hammasini ulaydi |
| `.../app/MainActivity.kt` | M1 uchun sinov maydoni |
| `android/tools/adb-type.py` | Emulyatorda matnni tugmalar bilan yozish (debug log'dan koordinatalar) |
| `android/app/src/test/.../ime/*Test.kt` | JVM testlar |

`...` = `android/app/src/main/java/com/ibrokhim/aikeyboard`.

---

### Task 1: Gradle skeleti, IME e'loni va sinov ekrani

**Files:**
- Create: `android/.gitignore`, `android/settings.gradle.kts`, `android/build.gradle.kts`, `android/gradle.properties`, `android/local.properties` (commit qilinmaydi)
- Create: `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/xml/method.xml`, `android/app/src/main/res/values/strings.xml`
- Create: `android/app/src/main/java/com/ibrokhim/aikeyboard/ime/AiKeyboardService.kt` (vaqtinchalik), `android/app/src/main/java/com/ibrokhim/aikeyboard/app/MainActivity.kt`
- Generate: `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.{jar,properties}`

**Interfaces:**
- Produces: `com.ibrokhim.aikeyboard.ime.AiKeyboardService` (manifestdagi IME), `com.ibrokhim.aikeyboard.app.MainActivity`, `BuildConfig.DEBUG`.

- [ ] **Step 1: Gradle fayllarini yozish**

`android/.gitignore`:
```
.gradle/
.kotlin/
build/
local.properties
.idea/
*.iml
captures/
```

`android/settings.gradle.kts`:
```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "AIKeyboard"
include(":app")
```

`android/build.gradle.kts`:
```kotlin
plugins {
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}
```

`android/gradle.properties`:
```
org.gradle.jvmargs=-Xmx4g -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
# Kotlin comes from the kotlin-android plugin, the setup already proven with AGP 9 on this machine.
android.builtInKotlin=false
android.newDsl=false
kotlin.code.style=official
```

`android/local.properties` (gitignore'da):
```
sdk.dir=/Users/ibroxim/Library/Android/sdk
```

`android/app/build.gradle.kts`:
```kotlin
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
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
    }

    buildFeatures {
        buildConfig = true
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
    testImplementation("junit:junit:4.13.2")
}
```

- [ ] **Step 2: Manifest va resurslar**

`android/app/src/main/AndroidManifest.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

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
    </application>
</manifest>
```

`android/app/src/main/res/xml/method.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<input-method xmlns:android="http://schemas.android.com/apk/res/android"
    android:supportsSwitchingToNextInputMethod="true">
    <subtype
        android:label="@string/subtype_uz"
        android:imeSubtypeLocale="uz_UZ"
        android:languageTag="uz-Latn-UZ"
        android:imeSubtypeMode="keyboard" />
</input-method>
```

`android/app/src/main/res/values/strings.xml`:
```xml
<resources>
    <string name="app_name">AI Keyboard</string>
    <string name="subtype_uz">Oʻzbekcha</string>
</resources>
```

- [ ] **Step 3: Vaqtinchalik servis va sinov ekrani**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/AiKeyboardService.kt` (Task 5 da to'liq almashtiriladi):
```kotlin
package com.ibrokhim.aikeyboard.ime

import android.inputmethodservice.InputMethodService
import android.view.View

class AiKeyboardService : InputMethodService() {
    override fun onCreateInputView(): View = View(this)
}
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/app/MainActivity.kt`:
```kotlin
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
```

- [ ] **Step 4: Gradle wrapper yaratish (keshdagi Gradle 9.1.0 bilan)**

Run:
```bash
cd ~/Desktop/side-projects/ai-keyboard/android && export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" && ~/.gradle/wrapper/dists/gradle-9.1.0-all/7wzd0jkjit61aq2p43wpjgij9/gradle-9.1.0/bin/gradle wrapper --gradle-version 9.1.0 --distribution-type all
```
Expected: `BUILD SUCCESSFUL`, `gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar` paydo bo'ladi.

- [ ] **Step 5: Build**

Run: `./gradlew :app:assembleDebug`
Expected: `BUILD SUCCESSFUL`, `app/build/outputs/apk/debug/app-debug.apk` mavjud.

- [ ] **Step 6: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add android && git commit -m "Android: Gradle skeleti, IME e'loni va sinov ekrani

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 2: Klaviatura qatlamlari (`KeyLayouts`)

**Files:**
- Create: `android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeyLayouts.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/KeyLayoutsTest.kt`

**Interfaces:**
- Produces: `enum Layer { LETTERS, NUMBERS, SYMBOLS }`, `enum Alphabet { LATIN, CYRILLIC }`, `enum ShiftState { OFF, ONCE, LOCKED }`, `sealed interface Key` (`Text(value)`, `Shift`, `Backspace`, `Globe`, `Space`, `Enter`, `AlphabetToggle`, `Emoji`, `LayerSwitch(layer, label)`), `data class KeysConfig(layer, alphabet, showsGlobe, emojiKey)`, `data class PlacedKey(key, width: Float)`, `KeyLayouts.rows(config, width, gap, sideInset): List<List<PlacedKey>>`.

- [ ] **Step 1: Failing test**

`android/app/src/test/java/com/ibrokhim/aikeyboard/ime/KeyLayoutsTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyLayoutsTest {
    private val width = 1080f
    private val gap = 18f
    private val side = 12f
    private val full = width - side * 2

    private fun rows(
        layer: Layer = Layer.LETTERS,
        alphabet: Alphabet = Alphabet.LATIN,
        globe: Boolean = false,
        emoji: Boolean = false,
    ) = KeyLayouts.rows(KeysConfig(layer, alphabet, globe, emoji), width, gap, side)

    private fun rowWidth(row: List<PlacedKey>) = row.sumOf { it.width.toDouble() }.toFloat() + gap * (row.size - 1)

    private fun texts(row: List<PlacedKey>) = row.mapNotNull { (it.key as? Key.Text)?.value }

    @Test fun latinLettersFollowQwerty() {
        val r = rows()
        assertEquals(4, r.size)
        assertEquals(listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"), texts(r[0]))
        assertEquals(Key.Shift, r[2].first().key)
        assertEquals(Key.Backspace, r[2].last().key)
    }

    @Test fun fullRowsFillTheWidthAndNoRowOverflows() {
        for (layer in Layer.entries) for (alphabet in Alphabet.entries) {
            val r = rows(layer, alphabet)
            assertEquals(full, rowWidth(r[0]), 0.5f)
            assertEquals(full, rowWidth(r[2]), 0.5f)
            assertEquals(full, rowWidth(r[3]), 0.5f)
            r.forEach { assertTrue(rowWidth(it) <= full + 0.5f) }
        }
    }

    @Test fun bottomRowHasAlphabetToggleAndUzbekLetters() {
        val bottom = rows().last()
        assertEquals(Key.LayerSwitch(Layer.NUMBERS, "123"), bottom[0].key)
        assertEquals(Key.AlphabetToggle, bottom[1].key)
        assertEquals(listOf("oʻ", "gʻ"), texts(bottom))
        assertEquals(Key.Space, bottom[bottom.size - 2].key)
        assertEquals(Key.Enter, bottom.last().key)
    }

    @Test fun cyrillicHasTwelveColumnsAndItsOwnExtras() {
        val r = rows(alphabet = Alphabet.CYRILLIC)
        assertEquals(12, r[0].size)
        assertEquals(listOf("ғ", "ҳ"), texts(r.last()))
    }

    @Test fun emojiKeyReplacesAlphabetToggle() {
        assertEquals(Key.Emoji, rows(emoji = true).last()[1].key)
    }

    @Test fun globeAppearsOnlyWhenAsked() {
        assertTrue(rows(globe = true).last().any { it.key == Key.Globe })
        assertTrue(rows().last().none { it.key == Key.Globe })
    }

    @Test fun numberLayersToggleEachOtherAndReturnToLetters() {
        val numbers = rows(Layer.NUMBERS)
        assertEquals(Key.LayerSwitch(Layer.SYMBOLS, "#+="), numbers[2].first().key)
        assertEquals(listOf(".", ",", "?", "!", "'"), texts(numbers[2]))
        assertEquals(Key.LayerSwitch(Layer.LETTERS, "ABC"), numbers.last().first().key)
        assertEquals(Key.LayerSwitch(Layer.NUMBERS, "123"), rows(Layer.SYMBOLS)[2].first().key)
    }
}
```

- [ ] **Step 2: Run — fails**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests '*KeyLayoutsTest'`
Expected: FAIL — `Unresolved reference: KeyLayouts`.

- [ ] **Step 3: Implementation**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeyLayouts.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

enum class Layer { LETTERS, NUMBERS, SYMBOLS }

enum class Alphabet { LATIN, CYRILLIC }

enum class ShiftState { OFF, ONCE, LOCKED }

sealed interface Key {
    data class Text(val value: String) : Key
    data object Shift : Key
    data object Backspace : Key
    data object Globe : Key
    data object Space : Key
    data object Enter : Key
    /** КИР/LAT. */
    data object AlphabetToggle : Key
    /** Replaces КИР/LAT when the emoji-key setting is on (panel arrives in milestone 4). */
    data object Emoji : Key
    data class LayerSwitch(val layer: Layer, val label: String) : Key
}

data class KeysConfig(
    val layer: Layer,
    val alphabet: Alphabet,
    val showsGlobe: Boolean,
    val emojiKey: Boolean,
)

/** A key and its width in pixels. Keys in a row are separated by the layout's gap. */
data class PlacedKey(val key: Key, val width: Float)

/** Same tables and width arithmetic as the iOS `KeysUIView`. */
object KeyLayouts {
    private val latin = listOf(
        listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"),
        listOf("a", "s", "d", "f", "g", "h", "j", "k", "l"),
        listOf("z", "x", "c", "v", "b", "n", "m"),
    )

    /** Uzbek Cyrillic on the ЙЦУКЕН base; ғ and ҳ sit in the bottom row, like oʻ/gʻ in Latin. */
    private val cyrillic = listOf(
        listOf("й", "ц", "у", "к", "е", "н", "г", "ш", "ў", "з", "х", "ъ"),
        listOf("ф", "қ", "в", "а", "п", "р", "о", "л", "д", "ж", "э"),
        listOf("я", "ч", "с", "м", "и", "т", "ь", "б", "ю"),
    )
    private val numbers = listOf(
        listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"),
        listOf("-", "/", ":", ";", "(", ")", "$", "&", "@", "\""),
    )
    private val symbols = listOf(
        listOf("[", "]", "{", "}", "#", "%", "^", "*", "+", "="),
        listOf("_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"),
    )
    private val punctuation = listOf(".", ",", "?", "!", "'")

    private fun extras(alphabet: Alphabet) =
        if (alphabet == Alphabet.LATIN) listOf("oʻ", "gʻ") else listOf("ғ", "ҳ")

    fun rows(config: KeysConfig, width: Float, gap: Float, sideInset: Float): List<List<PlacedKey>> {
        val full = width - sideInset * 2
        val baseUnit = (full - gap * 9) / 10
        val rows = mutableListOf<List<PlacedKey>>()

        when (config.layer) {
            Layer.LETTERS -> {
                val letters = if (config.alphabet == Alphabet.LATIN) latin else cyrillic
                val columns = letters[0].size
                val unit = (full - gap * (columns - 1)) / columns
                val bottomLetters = letters[2].size
                val side = (full - unit * bottomLetters - gap * (bottomLetters + 1)) / 2
                rows.add(letters[0].map { PlacedKey(Key.Text(it), unit) })
                rows.add(letters[1].map { PlacedKey(Key.Text(it), unit) })
                rows.add(
                    listOf(PlacedKey(Key.Shift, side)) +
                        letters[2].map { PlacedKey(Key.Text(it), unit) } +
                        PlacedKey(Key.Backspace, side),
                )
            }
            Layer.NUMBERS, Layer.SYMBOLS -> {
                val chars = if (config.layer == Layer.NUMBERS) numbers else symbols
                val toggle = if (config.layer == Layer.NUMBERS) {
                    Key.LayerSwitch(Layer.SYMBOLS, "#+=")
                } else {
                    Key.LayerSwitch(Layer.NUMBERS, "123")
                }
                val side = baseUnit * 1.5f + gap / 2
                val punctuationWidth = (full - side * 2 - gap * 6) / 5
                rows.add(chars[0].map { PlacedKey(Key.Text(it), baseUnit) })
                rows.add(chars[1].map { PlacedKey(Key.Text(it), baseUnit) })
                rows.add(
                    listOf(PlacedKey(toggle, side)) +
                        punctuation.map { PlacedKey(Key.Text(it), punctuationWidth) } +
                        PlacedKey(Key.Backspace, side),
                )
            }
        }

        val bottom = mutableListOf<PlacedKey>()
        val layerKey = if (config.layer == Layer.LETTERS) {
            Key.LayerSwitch(Layer.NUMBERS, "123")
        } else {
            Key.LayerSwitch(Layer.LETTERS, "ABC")
        }
        bottom.add(PlacedKey(layerKey, baseUnit * 1.25f))
        if (config.showsGlobe) bottom.add(PlacedKey(Key.Globe, baseUnit * 1.1f))
        if (config.layer == Layer.LETTERS) {
            bottom.add(PlacedKey(if (config.emojiKey) Key.Emoji else Key.AlphabetToggle, baseUnit * 1.25f))
            extras(config.alphabet).forEach { bottom.add(PlacedKey(Key.Text(it), baseUnit)) }
        }
        val enterWidth = baseUnit * 2
        val used = bottom.sumOf { it.width.toDouble() }.toFloat() + enterWidth + gap * (bottom.size + 1)
        bottom.add(PlacedKey(Key.Space, maxOf(baseUnit * 2, full - used)))
        bottom.add(PlacedKey(Key.Enter, enterWidth))
        rows.add(bottom)
        return rows
    }
}
```

- [ ] **Step 4: Run — passes**

Run: `./gradlew :app:testDebugUnitTest --tests '*KeyLayoutsTest'`
Expected: `BUILD SUCCESSFUL`, 7 test PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add android && git commit -m "Android: klaviatura qatlamlari (lotin, kirill, raqamlar, belgilar)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 3: Matn va maydon qoidalari (`TextRules`, `EditorRules`)

**Files:**
- Create: `android/app/src/main/java/com/ibrokhim/aikeyboard/ime/TextRules.kt`, `android/app/src/main/java/com/ibrokhim/aikeyboard/ime/EditorRules.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/TextRulesTest.kt`, `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/EditorRulesTest.kt`

**Interfaces:**
- Produces: `TextRules.startsSentence(before: String): Boolean`, `TextRules.isDoubleSpace(before: String, msSinceLastSpace: Long?): Boolean`, `TextRules.DOUBLE_SPACE_WINDOW_MS = 350L`, `TextRules.DOUBLE_SHIFT_WINDOW_MS = 300L`; `enum EnterAction(glyph: String)` (`NEWLINE, SEND, GO, SEARCH, NEXT, DONE, PREVIOUS`), `EditorRules.enterAction(imeOptions: Int): EnterAction`, `EditorRules.imeAction(action: EnterAction): Int?`, `EditorRules.autoCapitalize(inputType: Int): Boolean`.

- [ ] **Step 1: Failing tests**

`android/app/src/test/java/com/ibrokhim/aikeyboard/ime/TextRulesTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TextRulesTest {
    @Test fun sentenceStarts() {
        assertTrue(TextRules.startsSentence(""))
        assertTrue(TextRules.startsSentence("   "))
        assertTrue(TextRules.startsSentence("Salom.\n"))
        assertTrue(TextRules.startsSentence("Salom. "))
        assertTrue(TextRules.startsSentence("Qalay? "))
        assertTrue(TextRules.startsSentence("Zo'r! "))
    }

    @Test fun midSentence() {
        assertFalse(TextRules.startsSentence("Salom"))
        assertFalse(TextRules.startsSentence("Salom "))
        assertFalse(TextRules.startsSentence("Salom."))
    }

    @Test fun doubleSpaceAfterAWordWithinTheWindow() {
        assertTrue(TextRules.isDoubleSpace("salom ", 200))
        assertTrue(TextRules.isDoubleSpace("5 ", 100))
    }

    @Test fun notADoubleSpace() {
        assertFalse(TextRules.isDoubleSpace("salom ", null))
        assertFalse(TextRules.isDoubleSpace("salom ", 350))
        assertFalse(TextRules.isDoubleSpace("salom", 100))
        assertFalse(TextRules.isDoubleSpace("salom. ", 100))
        assertFalse(TextRules.isDoubleSpace(" ", 100))
    }
}
```

`android/app/src/test/java/com/ibrokhim/aikeyboard/ime/EditorRulesTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorRulesTest {
    @Test fun enterActionFollowsImeOptions() {
        assertEquals(EnterAction.SEND, EditorRules.enterAction(EditorInfo.IME_ACTION_SEND))
        assertEquals(EnterAction.SEARCH, EditorRules.enterAction(EditorInfo.IME_ACTION_SEARCH))
        assertEquals(EnterAction.NEWLINE, EditorRules.enterAction(EditorInfo.IME_ACTION_UNSPECIFIED))
    }

    @Test fun noEnterActionFlagMeansNewline() {
        val options = EditorInfo.IME_ACTION_SEND or EditorInfo.IME_FLAG_NO_ENTER_ACTION
        assertEquals(EnterAction.NEWLINE, EditorRules.enterAction(options))
        assertNull(EditorRules.imeAction(EnterAction.NEWLINE))
        assertEquals(EditorInfo.IME_ACTION_SEND, EditorRules.imeAction(EnterAction.SEND))
    }

    @Test fun capitalisesPlainTextWithACapsFlag() {
        val text = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        assertTrue(EditorRules.autoCapitalize(text))
        assertFalse(EditorRules.autoCapitalize(InputType.TYPE_CLASS_TEXT))
    }

    @Test fun neverCapitalisesPasswordsEmailsUrlsOrNumbers() {
        val caps = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        assertFalse(EditorRules.autoCapitalize(caps or InputType.TYPE_TEXT_VARIATION_PASSWORD))
        assertFalse(EditorRules.autoCapitalize(caps or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS))
        assertFalse(EditorRules.autoCapitalize(caps or InputType.TYPE_TEXT_VARIATION_URI))
        assertFalse(EditorRules.autoCapitalize(InputType.TYPE_CLASS_NUMBER))
    }
}
```

- [ ] **Step 2: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*TextRulesTest' --tests '*EditorRulesTest'`
Expected: FAIL — `Unresolved reference: TextRules`.

- [ ] **Step 3: Implementation**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/TextRules.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

/** Typing conventions shared with the iOS keyboard (`KeyboardModel.autoCapitalize` / `space`). */
object TextRules {
    const val DOUBLE_SPACE_WINDOW_MS = 350L
    const val DOUBLE_SHIFT_WINDOW_MS = 300L

    /** The next letter starts a sentence: empty field, a new line, or right after ". ", "! ", "? ". */
    fun startsSentence(before: String): Boolean {
        val trimmed = before.trimEnd(' ')
        if (trimmed.isEmpty() || before.endsWith("\n")) return true
        return trimmed.last() in ".!?" && before.endsWith(" ")
    }

    /** A second space soon after the first, right after a word, becomes ". " like the system keyboard. */
    fun isDoubleSpace(before: String, msSinceLastSpace: Long?): Boolean {
        if (msSinceLastSpace == null || msSinceLastSpace >= DOUBLE_SPACE_WINDOW_MS) return false
        if (!before.endsWith(" ")) return false
        val previous = before.dropLast(1).lastOrNull() ?: return false
        return previous.isLetterOrDigit()
    }
}
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/EditorRules.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo

enum class EnterAction(val glyph: String) {
    NEWLINE("⏎"), SEND("➤"), GO("→"), SEARCH("⌕"), NEXT("⇥"), DONE("✓"), PREVIOUS("⇤"),
}

/** Reads what the focused field asks for from its `EditorInfo` bits. */
object EditorRules {
    fun enterAction(imeOptions: Int): EnterAction {
        if ((imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0) return EnterAction.NEWLINE
        return when (imeOptions and EditorInfo.IME_MASK_ACTION) {
            EditorInfo.IME_ACTION_SEND -> EnterAction.SEND
            EditorInfo.IME_ACTION_GO -> EnterAction.GO
            EditorInfo.IME_ACTION_SEARCH -> EnterAction.SEARCH
            EditorInfo.IME_ACTION_NEXT -> EnterAction.NEXT
            EditorInfo.IME_ACTION_DONE -> EnterAction.DONE
            EditorInfo.IME_ACTION_PREVIOUS -> EnterAction.PREVIOUS
            else -> EnterAction.NEWLINE
        }
    }

    fun imeAction(action: EnterAction): Int? = when (action) {
        EnterAction.NEWLINE -> null
        EnterAction.SEND -> EditorInfo.IME_ACTION_SEND
        EnterAction.GO -> EditorInfo.IME_ACTION_GO
        EnterAction.SEARCH -> EditorInfo.IME_ACTION_SEARCH
        EnterAction.NEXT -> EditorInfo.IME_ACTION_NEXT
        EnterAction.DONE -> EditorInfo.IME_ACTION_DONE
        EnterAction.PREVIOUS -> EditorInfo.IME_ACTION_PREVIOUS
    }

    private val noCapsVariations = setOf(
        InputType.TYPE_TEXT_VARIATION_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
        InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
        InputType.TYPE_TEXT_VARIATION_URI,
    )

    /** Only text fields that ask for capitals get them, like the system keyboard. */
    fun autoCapitalize(inputType: Int): Boolean {
        if ((inputType and InputType.TYPE_MASK_CLASS) != InputType.TYPE_CLASS_TEXT) return false
        if ((inputType and InputType.TYPE_MASK_VARIATION) in noCapsVariations) return false
        val caps = InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or
            InputType.TYPE_TEXT_FLAG_CAP_WORDS or
            InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
        return (inputType and caps) != 0
    }
}
```

- [ ] **Step 4: Run — passes**

Run: `./gradlew :app:testDebugUnitTest --tests '*TextRulesTest' --tests '*EditorRulesTest'`
Expected: `BUILD SUCCESSFUL`, 8 test PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add android && git commit -m "Android: katta harf, ikki probel va Enter qoidalari

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 4: `KeyboardController`

**Files:**
- Create: `android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeyboardController.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/KeyboardControllerTest.kt`

**Interfaces:**
- Consumes: `Key`, `Layer`, `Alphabet`, `ShiftState`, `KeysConfig` (Task 2); `TextRules` (Task 3).
- Produces:
  ```kotlin
  interface InputTarget {
      fun textBeforeCursor(length: Int): String
      fun commit(text: String)
      fun deleteBackward()
      fun moveCursor(offset: Int)
      fun enter()
      fun switchKeyboard()
      val autoCapitalize: Boolean
  }
  class KeyboardController(target: InputTarget, clock: () -> Long, initialAlphabet: Alphabet = Alphabet.LATIN) {
      val layer: Layer; val shift: ShiftState; val alphabet: Alphabet
      var showsGlobe: Boolean; var emojiKey: Boolean
      var onChange: () -> Unit
      val config: KeysConfig
      fun press(key: Key)
      fun moveCursor(offset: Int)
      fun setLayer(value: Layer)
      fun autoCapitalize()
  }
  ```

- [ ] **Step 1: Failing test**

`android/app/src/test/java/com/ibrokhim/aikeyboard/ime/KeyboardControllerTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import org.junit.Assert.assertEquals
import org.junit.Test

class KeyboardControllerTest {
    private class FakeTarget : InputTarget {
        val text = StringBuilder()
        var enters = 0
        var switches = 0
        override var autoCapitalize = true
        override fun textBeforeCursor(length: Int) = text.takeLast(length).toString()
        override fun commit(text: String) {
            this.text.append(text)
        }
        override fun deleteBackward() {
            if (text.isNotEmpty()) text.deleteCharAt(text.length - 1)
        }
        override fun moveCursor(offset: Int) = Unit
        override fun enter() {
            enters++
        }
        override fun switchKeyboard() {
            switches++
        }
    }

    private var now = 10_000L
    private val target = FakeTarget()
    private val controller = KeyboardController(target, { now })

    private fun type(word: String) = word.forEach { controller.press(Key.Text(it.toString())) }

    @Test fun capitalisesTheFirstLetterOnly() {
        controller.autoCapitalize()
        type("salom")
        assertEquals("Salom", target.text.toString())
    }

    @Test fun capitalisesAfterAFullStop() {
        controller.autoCapitalize()
        type("salom.")
        controller.press(Key.Space)
        type("qalay")
        assertEquals("Salom. Qalay", target.text.toString())
    }

    @Test fun quickDoubleSpaceBecomesFullStop() {
        controller.autoCapitalize()
        type("salom")
        controller.press(Key.Space)
        now += 200
        controller.press(Key.Space)
        assertEquals("Salom. ", target.text.toString())
        assertEquals(ShiftState.ONCE, controller.shift)
    }

    @Test fun slowDoubleSpaceStaysTwoSpaces() {
        type("salom")
        controller.press(Key.Space)
        now += 1_000
        controller.press(Key.Space)
        assertEquals("salom  ", target.text.toString())
    }

    @Test fun doubleTapShiftLocksCapitals() {
        target.autoCapitalize = false
        controller.press(Key.Shift)
        now += 150
        controller.press(Key.Shift)
        assertEquals(ShiftState.LOCKED, controller.shift)
        type("ok")
        assertEquals("OK", target.text.toString())
    }

    @Test fun uzbekLetterUppercasesWithItsModifier() {
        controller.autoCapitalize()
        controller.press(Key.Text("oʻ"))
        assertEquals("Oʻ", target.text.toString())
    }

    @Test fun fieldsWithoutCapsStayLowercase() {
        target.autoCapitalize = false
        controller.autoCapitalize()
        type("salom")
        assertEquals("salom", target.text.toString())
    }

    @Test fun spaceReturnsFromNumbersToLetters() {
        controller.press(Key.LayerSwitch(Layer.NUMBERS, "123"))
        assertEquals(Layer.NUMBERS, controller.layer)
        controller.press(Key.Space)
        assertEquals(Layer.LETTERS, controller.layer)
    }

    @Test fun alphabetToggleAndEmojiKeyConfig() {
        controller.press(Key.AlphabetToggle)
        assertEquals(Alphabet.CYRILLIC, controller.config.alphabet)
        controller.emojiKey = true
        assertEquals(Alphabet.LATIN, controller.config.alphabet)
    }

    @Test fun enterAndGlobeGoToTheTarget() {
        controller.press(Key.Enter)
        controller.press(Key.Globe)
        assertEquals(1, target.enters)
        assertEquals(1, target.switches)
    }

    @Test fun backspaceDeletes() {
        type("ab")
        controller.press(Key.Backspace)
        assertEquals("a", target.text.toString())
    }
}
```

- [ ] **Step 2: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*KeyboardControllerTest'`
Expected: FAIL — `Unresolved reference: KeyboardController`.

- [ ] **Step 3: Implementation**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeyboardController.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

/** What the controller types into. `AiKeyboardService` backs it with the current `InputConnection`. */
interface InputTarget {
    fun textBeforeCursor(length: Int): String
    fun commit(text: String)
    fun deleteBackward()
    fun moveCursor(offset: Int)
    fun enter()
    fun switchKeyboard()

    /** False for passwords, emails, URLs and fields that do not ask for capitals. */
    val autoCapitalize: Boolean
}

/** Keyboard state and typing behaviour — the Android counterpart of the iOS `KeyboardModel`. */
class KeyboardController(
    private val target: InputTarget,
    private val clock: () -> Long,
    initialAlphabet: Alphabet = Alphabet.LATIN,
) {
    var layer = Layer.LETTERS
        private set
    var shift = ShiftState.OFF
        private set
    var alphabet = initialAlphabet
        private set
    var showsGlobe = false
    var emojiKey = false

    /** Called after every state change the keys should redraw for. */
    var onChange: () -> Unit = {}

    private var lastSpaceAt: Long? = null
    private var lastShiftAt: Long? = null

    /** With the emoji key there is no way back from Cyrillic, so it implies Latin (as on iOS). */
    val config: KeysConfig
        get() = KeysConfig(layer, if (emojiKey) Alphabet.LATIN else alphabet, showsGlobe, emojiKey)

    fun press(key: Key) {
        when (key) {
            is Key.Text -> type(key.value)
            Key.Space -> space()
            Key.Backspace -> {
                target.deleteBackward()
                autoCapitalize()
            }
            Key.Enter -> {
                target.enter()
                autoCapitalize()
            }
            Key.Shift -> tapShift()
            Key.AlphabetToggle -> {
                alphabet = if (alphabet == Alphabet.LATIN) Alphabet.CYRILLIC else Alphabet.LATIN
                onChange()
            }
            Key.Globe -> target.switchKeyboard()
            Key.Emoji -> Unit // the emoji panel arrives in milestone 4
            is Key.LayerSwitch -> setLayer(key.layer)
        }
    }

    fun moveCursor(offset: Int) = target.moveCursor(offset)

    fun setLayer(value: Layer) {
        if (layer != value) {
            layer = value
            onChange()
        }
        autoCapitalize()
    }

    fun autoCapitalize() {
        if (layer != Layer.LETTERS || shift == ShiftState.LOCKED) return
        if (!target.autoCapitalize) {
            setShift(ShiftState.OFF)
            return
        }
        val startsSentence = TextRules.startsSentence(target.textBeforeCursor(64))
        setShift(if (startsSentence) ShiftState.ONCE else ShiftState.OFF)
    }

    private fun type(text: String) {
        target.commit(if (shift == ShiftState.OFF) text else text.uppercase())
        if (shift == ShiftState.ONCE) setShift(ShiftState.OFF)
        autoCapitalize()
    }

    private fun space() {
        val now = clock()
        val before = target.textBeforeCursor(2)
        if (TextRules.isDoubleSpace(before, lastSpaceAt?.let { now - it })) {
            target.deleteBackward()
            target.commit(". ")
            lastSpaceAt = null
        } else {
            target.commit(" ")
            lastSpaceAt = now
        }
        setLayer(Layer.LETTERS)
    }

    private fun tapShift() {
        val now = clock()
        val last = lastShiftAt
        if (last != null && now - last < TextRules.DOUBLE_SHIFT_WINDOW_MS) {
            setShift(ShiftState.LOCKED)
        } else {
            setShift(if (shift == ShiftState.OFF) ShiftState.ONCE else ShiftState.OFF)
        }
        lastShiftAt = now
    }

    private fun setShift(value: ShiftState) {
        if (shift != value) {
            shift = value
            onChange()
        }
    }
}
```

- [ ] **Step 4: Run — passes**

Run: `./gradlew :app:testDebugUnitTest`
Expected: `BUILD SUCCESSFUL`, barcha testlar (26 ta) PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add android && git commit -m "Android: KeyboardController — yozish mantig'i va holat

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 5: `KeysView`, mavzu, servis va emulyatorda tekshiruv

**Files:**
- Create: `android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeyboardTheme.kt`, `android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeysView.kt`, `android/tools/adb-type.py`
- Modify: `android/app/src/main/java/com/ibrokhim/aikeyboard/ime/AiKeyboardService.kt` (to'liq almashtiriladi)

**Interfaces:**
- Consumes: `KeyboardController`, `InputTarget` (Task 4); `KeyLayouts`, `Key`, `KeysConfig` (Task 2); `EditorRules`, `EnterAction` (Task 3).
- Produces: `KeysView(context, controller)` with `var theme: KeyboardTheme`, `var enterLabel: String`; debug-only logcat tag `AIKeys` with line `layout {"<name>":[x,y],...}` (screen px; names: letter text, `shift`, `backspace`, `globe`, `space`, `enter`, `alphabet`, `emoji`, `layer:<label>`); `android/tools/adb-type.py "<text>"`.

- [ ] **Step 1: Mavzu**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeyboardTheme.kt`:
```kotlin
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
```

- [ ] **Step 2: `KeysView`**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeysView.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.MotionEvent
import android.view.View
import com.ibrokhim.aikeyboard.BuildConfig
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

    var enterLabel = EnterAction.NEWLINE.glyph
        set(value) {
            field = value
            invalidate()
        }

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
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val height = topInset + keyHeight * 4 + rowGap * 3 + bottomInset
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
        if (BuildConfig.DEBUG) post { logLayout() }
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

    private fun label(key: Key): String = when (key) {
        is Key.Text -> if (controller.shift == ShiftState.OFF) key.value else key.value.uppercase()
        Key.Shift -> if (controller.shift == ShiftState.LOCKED) "⇪" else "⇧"
        Key.Backspace -> "⌫"
        Key.Globe -> "🌐"
        Key.Space -> if (controller.config.alphabet == Alphabet.LATIN) "Oʻzbekcha" else "Ўзбекча"
        Key.Enter -> enterLabel
        Key.AlphabetToggle -> if (controller.alphabet == Alphabet.LATIN) "КИР" else "LAT"
        Key.Emoji -> "😀"
        is Key.LayerSwitch -> key.label
    }

    private fun drawLabel(canvas: Canvas, cap: Cap, isEnter: Boolean) {
        val label = label(cap.key)
        text.textSize = when (cap.key) {
            is Key.Text -> dp(22f)
            Key.Space -> dp(14f)
            is Key.LayerSwitch, Key.AlphabetToggle -> dp(15f)
            else -> dp(20f)
        }
        text.color = if (isEnter) theme.onAccent else theme.label
        val bold = cap.key == Key.Shift && controller.shift != ShiftState.OFF
        text.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        val y = cap.frame.centerY() - (text.descent() + text.ascent()) / 2
        canvas.drawText(label, cap.frame.centerX(), y, text)
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
    private fun logLayout() {
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
```

- [ ] **Step 3: Servis**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/AiKeyboardService.kt` (to'liq almashtirish):
```kotlin
package com.ibrokhim.aikeyboard.ime

import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import kotlin.math.abs

class AiKeyboardService : InputMethodService() {
    private val prefs by lazy { getSharedPreferences("keyboard", MODE_PRIVATE) }
    private lateinit var controller: KeyboardController
    private var keysView: KeysView? = null
    private var editorInfo: EditorInfo? = null
    private var savedAlphabet = Alphabet.LATIN

    private val target = object : InputTarget {
        override fun textBeforeCursor(length: Int): String =
            currentInputConnection?.getTextBeforeCursor(length, 0)?.toString().orEmpty()

        override fun commit(text: String) {
            currentInputConnection?.commitText(text, 1)
        }

        /** A key event rather than deleteSurroundingText: editors then remove selections and emoji correctly. */
        override fun deleteBackward() = sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)

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

        override val autoCapitalize: Boolean
            get() = EditorRules.autoCapitalize(editorInfo?.inputType ?: 0)
    }

    override fun onCreate() {
        super.onCreate()
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
    }

    override fun onCreateInputView(): View = KeysView(this, controller).also { keysView = it }

    /** The keyboard never takes over the whole screen in landscape. */
    override fun onEvaluateFullscreenMode() = false

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        editorInfo = info
        controller.showsGlobe = if (Build.VERSION.SDK_INT >= 28) shouldOfferSwitchingToNextInputMethod() else true
        keysView?.apply {
            theme = KeyboardTheme.from(this@AiKeyboardService)
            enterLabel = EditorRules.enterAction(info.imeOptions).glyph
        }
        controller.setLayer(Layer.LETTERS)
        controller.autoCapitalize()
        keysView?.invalidate()
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
}
```

- [ ] **Step 4: adb bilan yozish skripti**

`android/tools/adb-type.py`:
```python
#!/usr/bin/env python3
"""Types text on the AI Keyboard in an emulator by tapping its keys.

Key centres come from the debug-build logcat line `AIKeys: layout {...}` that KeysView prints after
every layout. Lowercase letters, digits on the numbers layer, space and the Uzbek letters oʻ/gʻ.
Usage: tools/adb-type.py "salom dunyo"   (ADB env var overrides the adb path)
"""
import json, os, re, subprocess, sys, time

ADB = os.environ.get("ADB", os.path.expanduser("~/Library/Android/sdk/platform-tools/adb"))


def layout():
    log = subprocess.run([ADB, "logcat", "-d", "-s", "AIKeys:D"], capture_output=True, text=True).stdout
    lines = re.findall(r"layout (\{.*\})", log)
    if not lines:
        sys.exit("no AIKeys layout in logcat — is the debug keyboard on screen?")
    return json.loads(lines[-1])


def tap(point):
    subprocess.run([ADB, "shell", "input", "tap", str(point[0]), str(point[1])], check=True)
    time.sleep(0.08)


def main(text):
    keys = layout()
    i = 0
    while i < len(text):
        pair = text[i:i + 2]
        if pair in ("oʻ", "gʻ"):
            tap(keys[pair]); i += 2; continue
        ch = text[i]
        name = "space" if ch == " " else ch
        if name not in keys and "layer:123" in keys:
            tap(keys["layer:123"]); time.sleep(0.2); keys = layout()
        if name not in keys and "layer:ABC" in keys:
            tap(keys["layer:ABC"]); time.sleep(0.2); keys = layout()
        if name not in keys:
            sys.exit(f"no key for {ch!r}")
        tap(keys[name])
        if name == "space" and "layer:ABC" in keys:
            time.sleep(0.2); keys = layout()  # space returns to the letter layer
        i += 1


if __name__ == "__main__":
    main(sys.argv[1])
```

Run: `chmod +x android/tools/adb-type.py`

- [ ] **Step 5: Build va testlar**

Run: `cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug`
Expected: `BUILD SUCCESSFUL`, 26 test PASS.

- [ ] **Step 6: Emulyatorda tekshirish**

Run (emulyator oynasiz, fon rejimida):
```bash
~/Library/Android/sdk/emulator/emulator -avd Pixel_9_Pro -no-window -no-audio -no-boot-anim -no-snapshot-save &
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB wait-for-device && until [ "$($ADB shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done
$ADB install -r android/app/build/outputs/apk/debug/app-debug.apk
$ADB shell ime enable com.ibrokhim.aikeyboard/.ime.AiKeyboardService
$ADB shell ime set com.ibrokhim.aikeyboard/.ime.AiKeyboardService
$ADB logcat -c
$ADB shell am start -n com.ibrokhim.aikeyboard/.app.MainActivity
```
Keyin maydonni bosish (`uiautomator dump` dagi `EditText` markazi), `android/tools/adb-type.py "salom dunyo"` → `$ADB shell uiautomator dump /sdcard/ui.xml && $ADB shell cat /sdcard/ui.xml` da maydon matni `Salom dunyo` (birinchi harf avtomatik katta). Ikki tez probel: `adb-type.py "  "` ikki marta tez → `Salom dunyo. `. `$ADB exec-out screencap -p > /tmp/.../m1.png` bilan skrinshot: lotin qatlami, pastki qatorda `123 · КИР · oʻ · gʻ · Oʻzbekcha · ⏎`, Enter ko'k.

Expected: yuqoridagi matnlar maydonda; skrinshotda klaviatura to'g'ri chizilgan.

- [ ] **Step 7: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add android && git commit -m "Android: klaviatura ko'rinishi, touch va servis — emulyatorda yozish ishlaydi

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

## Keyingi rejalar

M2 (ma'lumot va AI), M3 (chatni o'qish, panel, ✨), M4 (emoji, popup, tebranish, tafsilotlar, avtomatik o'qish), M5 (sozlash ekrani, README, APK) — har biri shu spec asosida alohida reja faylida.
