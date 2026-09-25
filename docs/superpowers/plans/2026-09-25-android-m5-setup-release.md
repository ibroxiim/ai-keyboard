# Android M5 — sozlash ekrani, foydalanuvchi kaliti, ikonka va APK: implementatsiya rejasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android versiyani tarqatishga tayyorlash: foydalanuvchi o'z Gemini kalitini ilovada kiritadi (release APK ichida kalit yo'q), iOS `ContentView` tengi sozlash ekrani (✓ qadamlar, Accessibility tushuntirishi, kalit, sinov, til, klaviatura, do'stlar, oxirgi kontekst), ilova ikonkasi, README/CONTRIBUTING'da Android bo'limi va imzolangan release APK.

**Architecture:** `data/ApiKeyStore` (SharedPreferences, `resolveKey` sof), `ai/KeyCheck` (kalitni tekshirish), `app/SetupSteps` (qadamlar holati — sof `SetupStatus` + Android o'qish), `app/SetupScreen` + `app/AppTheme` (Compose, `ComponentActivity`). Release: `keystore.properties` (gitignore) + repodan tashqaridagi `.jks`; `GEMINI_API_KEY` faqat debug build'da. Push va GitHub Release foydalanuvchi tasdig'idan keyin (Task 6). Spec: `docs/superpowers/specs/2026-09-25-android-version-design.md` (5-bosqich).

**Tech Stack:** M1–M4 + `androidx.activity:activity-compose:1.12.4` (compileSdk 36 bilan mos), Material3 (BOM 2026.06.01).

## Global Constraints

- M1–M4 cheklovlari amal qiladi.
- Release build'da `BuildConfig.GEMINI_API_KEY == ""` — ommaviy APK ichida hech qanday kalit bo'lmaydi. Debug build `local.properties` kalitini zaxira sifatida ishlatadi; foydalanuvchi kaliti har doim ustun.
- Kalit ilovaning shaxsiy `SharedPreferences`ida (`secrets`); `android:allowBackup="false"` (kalit, chat konteksti va do'stlar bulutga zaxiralanmaydi). Kalit hech qachon log/terminal/commit'ga chiqmaydi.
- Release kalit fayli `~/.android/ai-keyboard-release.jks` (repodan tashqarida), paroli `android/keystore.properties` (gitignore). Ikkalasini foydalanuvchi zaxiralab qo'yishi kerak — yo'qolsa ilovani shu imzo bilan yangilab bo'lmaydi.
- Push, PR, GitHub Release — faqat foydalanuvchi aniq tasdiqlagandan keyin.
- Versiya: `versionName "0.1.0-beta"`, `versionCode 1`.

## Fayllar

| Fayl | Vazifasi |
|---|---|
| `.../data/ApiKeyStore.kt` | Foydalanuvchi kaliti, `resolveKey` |
| `.../ai/Gemini.kt`, `.../ai/KeyCheck.kt` | Kalit yo'qligi xabari; kalitni tekshirish |
| `.../data/SharedState.kt` | `forgetFriend` |
| `.../app/SetupSteps.kt` | `SetupStatus` (sof) va `readSetupStatus(context, keys)` |
| `.../app/AppTheme.kt`, `.../app/SetupScreen.kt`, `.../app/MainActivity.kt` | Compose sozlash ekrani |
| `android/tools/icon-foreground.html`, `android/tools/render_icon.sh` | Ikonka oldingi qatlami (SVG → PNG) |
| `res/drawable-nodpi/ic_launcher_foreground.png`, `res/drawable/ic_launcher_background.xml`, `res/mipmap-anydpi-v26/ic_launcher*.xml` | Adaptive icon |
| `AndroidManifest.xml` | Ikonka, `allowBackup=false` |
| `android/app/build.gradle.kts`, `android/.gitignore` | Debug/release kalit, imzolash |
| `.../ime/AiKeyboardService.kt` | Kalit `ApiKeyStore`dan |
| `README.md`, `CONTRIBUTING.md` | Android bo'limi |
| testlar: `ApiKeyStoreTest`, `SetupStepsTest`, `SharedStateTest` (+1) | JVM |

`...` = `android/app/src/main/java/com/ibrokhim/aikeyboard`. Buyruqlar `android/` papkasida.

---

### Task 1: Foydalanuvchi kaliti va debug/release ajratish

**Files:**
- Create: `.../data/ApiKeyStore.kt`, `.../ai/KeyCheck.kt`
- Modify: `.../ai/Gemini.kt` (`MissingKey` matni), `.../ime/AiKeyboardService.kt` (kalit manbai), `android/app/build.gradle.kts`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/data/ApiKeyStoreTest.kt`

**Interfaces:**
- Produces: `class ApiKeyStore(prefs: SharedPreferences) { var userKey: String?; fun effectiveKey(): String; companion { fun resolveKey(user: String?, build: String): String; fun get(context: Context): ApiKeyStore } }`; `object KeyCheck { suspend fun check(key: String): String? }` (null = ishlayapti).

- [ ] **Step 1: Failing test**

`android/app/src/test/java/com/ibrokhim/aikeyboard/data/ApiKeyStoreTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.data

import org.junit.Assert.assertEquals
import org.junit.Test

class ApiKeyStoreTest {
    @Test fun theUsersKeyWins() {
        assertEquals("user", ApiKeyStore.resolveKey(" user ", "build"))
    }

    @Test fun buildKeyIsTheFallbackAndReleaseHasNone() {
        assertEquals("build", ApiKeyStore.resolveKey(null, "build"))
        assertEquals("build", ApiKeyStore.resolveKey("   ", "build"))
        assertEquals("", ApiKeyStore.resolveKey(null, ""))
    }
}
```

Run: `./gradlew :app:testDebugUnitTest --tests '*ApiKeyStoreTest'`
Expected: FAIL — `Unresolved reference 'ApiKeyStore'`.

- [ ] **Step 2: Implementation**

`android/app/src/main/java/com/ibrokhim/aikeyboard/data/ApiKeyStore.kt`:
```kotlin
package com.ibrokhim.aikeyboard.data

import android.content.Context
import android.content.SharedPreferences
import com.ibrokhim.aikeyboard.BuildConfig

/**
 * The user's own Gemini key, kept in the app's private storage (backups are off in the manifest).
 * A public APK carries no key; debug builds fall back to the developer's key from local.properties.
 */
class ApiKeyStore(private val prefs: SharedPreferences) {
    var userKey: String?
        get() = prefs.getString(KEY, null)?.takeIf { it.isNotBlank() }
        set(value) {
            val editor = prefs.edit()
            if (value.isNullOrBlank()) editor.remove(KEY) else editor.putString(KEY, value.trim())
            editor.apply()
        }

    fun effectiveKey(): String = resolveKey(userKey, BuildConfig.GEMINI_API_KEY)

    companion object {
        private const val KEY = "geminiApiKey"

        fun resolveKey(user: String?, build: String): String = user?.trim()?.takeIf { it.isNotEmpty() } ?: build

        fun get(context: Context) = ApiKeyStore(context.applicationContext.getSharedPreferences("secrets", Context.MODE_PRIVATE))
    }
}
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/ai/KeyCheck.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ai

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/** One tiny request to see whether a Gemini key works. */
object KeyCheck {
    private val schema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") { putJsonObject("ok") { put("type", "boolean") } }
    }

    /** null when the key works, otherwise a short reason in Uzbek. */
    suspend fun check(key: String): String? = try {
        GeminiClient(OkHttpGeminiTransport(), { key }).generate("Reply with {\"ok\": true}.", listOf(Part.Text("ping")), schema)
        null
    } catch (e: CancellationException) {
        throw e
    } catch (e: GeminiException.Http) {
        if (e.code in listOf(400, 401, 403)) "Kalit noto'g'ri yoki faol emas" else e.message
    } catch (e: Exception) {
        e.message ?: "Tekshirib bo'lmadi"
    }
}
```

`Gemini.kt` dagi qatorni almashtiring:
```kotlin
    class MissingKey : GeminiException("Gemini API kaliti kiritilmagan — AI Keyboard ilovasini oching")
```

`AiKeyboardService.kt` da:
```kotlin
        val translator = Translator(GeminiClient(OkHttpGeminiTransport(), { BuildConfig.GEMINI_API_KEY }))
```
qatorini almashtiring:
```kotlin
        val apiKeys = ApiKeyStore.get(this)
        val translator = Translator(GeminiClient(OkHttpGeminiTransport(), { apiKeys.effectiveKey() }))
```
va importlarda `import com.ibrokhim.aikeyboard.BuildConfig` ni `import com.ibrokhim.aikeyboard.data.ApiKeyStore` ga almashtiring.

`android/app/build.gradle.kts` (to'liq; imzolash Task 5 da qo'shiladi):
```kotlin
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The developer's Gemini key lives in the gitignored local.properties (gemini.apiKey=...) and only
// reaches debug builds. Release APKs carry no key: users enter their own in the app.
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
        versionName = "0.1.0-beta"
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    buildTypes {
        debug {
            buildConfigField("String", "GEMINI_API_KEY", "\"${localProperties.getProperty("gemini.apiKey", "")}\"")
        }
        release {
            buildConfigField("String", "GEMINI_API_KEY", "\"\"")
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
    implementation("androidx.activity:activity-compose:1.12.4")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test:2.3.20")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
}
```

- [ ] **Step 3: Run — passes, build**

Run: `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleRelease`
Expected: `BUILD SUCCESSFUL` (release hozircha imzosiz — `app-release-unsigned.apk`), `ApiKeyStoreTest` 2 PASS. Release'da kalit yo'qligini tekshirish:
```bash
grep -o 'GEMINI_API_KEY = "[^"]*"' app/build/generated/source/buildConfig/release/com/ibrokhim/aikeyboard/BuildConfig.java
```
Expected: `GEMINI_API_KEY = ""`.

- [ ] **Step 4: Commit**

```bash
cd .. && git add android && git commit -m "Android: foydalanuvchi Gemini kaliti, release build'da kalit yo'q

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 2: Qadamlar holati va do'stni o'chirish

**Files:**
- Create: `.../app/SetupSteps.kt`
- Modify: `.../data/SharedState.kt` (`forgetFriend`), `android/app/src/test/java/com/ibrokhim/aikeyboard/data/SharedStateTest.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/app/SetupStepsTest.kt`

**Interfaces:**
- Consumes: `ApiKeyStore` (Task 1), `ChatReaderService.isEnabled` (M3).
- Produces: `data class SetupStatus(keyboardEnabled, keyboardSelected, readerEnabled, hasKey) { val steps: List<Boolean>; val current: Int?; val done: Boolean }`, `fun readSetupStatus(context: Context, keys: ApiKeyStore): SetupStatus`; `SharedState.forgetFriend(name: String): SharedState`.

- [ ] **Step 1: Failing tests**

`android/app/src/test/java/com/ibrokhim/aikeyboard/app/SetupStepsTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SetupStepsTest {
    @Test fun theFirstUnfinishedStepIsCurrent() {
        assertEquals(0, SetupStatus(false, false, false, false).current)
        assertEquals(1, SetupStatus(true, false, true, true).current)
        assertEquals(3, SetupStatus(true, true, true, false).current)
    }

    @Test fun allDone() {
        val status = SetupStatus(true, true, true, true)
        assertNull(status.current)
        assertTrue(status.done)
    }
}
```

`SharedStateTest.kt` oxiridagi `}` dan oldin qo'shing:
```kotlin
    @Test fun forgetFriendAlsoClearsTheActiveTarget() {
        val state = SharedState(activeFriend = "Emma", friends = listOf(Friend("Emma", "English", "", now), Friend("Minji", "Korean", "", now)))
        val forgotten = state.forgetFriend("Emma")
        assertEquals(listOf("Minji"), forgotten.friends.map { it.name })
        assertNull(forgotten.activeFriend)
        assertEquals("Emma", state.forgetFriend("Minji").activeFriend)
    }
```

Run: `./gradlew :app:testDebugUnitTest --tests '*SetupStepsTest' --tests '*SharedStateTest'`
Expected: FAIL — `Unresolved reference 'SetupStatus'`.

- [ ] **Step 2: Implementation**

`SharedState.kt` da `fun mergeDuplicateFriends()` dan oldin qo'shing:
```kotlin
    fun forgetFriend(name: String): SharedState =
        copy(friends = friends.filterNot { it.name == name }, activeFriend = activeFriend.takeUnless { it == name })

```

`android/app/src/main/java/com/ibrokhim/aikeyboard/app/SetupSteps.kt`:
```kotlin
package com.ibrokhim.aikeyboard.app

import android.content.Context
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import com.ibrokhim.aikeyboard.data.ApiKeyStore
import com.ibrokhim.aikeyboard.reader.ChatReaderService

/** The four setup steps, in order: enable the keyboard, select it, allow chat reading, add a Gemini key. */
data class SetupStatus(
    val keyboardEnabled: Boolean,
    val keyboardSelected: Boolean,
    val readerEnabled: Boolean,
    val hasKey: Boolean,
) {
    val steps: List<Boolean> get() = listOf(keyboardEnabled, keyboardSelected, readerEnabled, hasKey)

    /** Index of the first unfinished step, or null when everything is set up. */
    val current: Int? get() = steps.indexOfFirst { !it }.takeIf { it >= 0 }

    val done: Boolean get() = current == null
}

/** Reads what the app cannot store itself: the system's keyboard and accessibility settings. */
fun readSetupStatus(context: Context, keys: ApiKeyStore): SetupStatus {
    val imm = context.getSystemService(InputMethodManager::class.java)
    val enabled = imm.enabledInputMethodList.any { it.packageName == context.packageName }
    val selected = Settings.Secure.getString(context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
        ?.startsWith(context.packageName + "/") == true
    return SetupStatus(enabled, selected, ChatReaderService.isEnabled(context), keys.effectiveKey().isNotBlank())
}
```

- [ ] **Step 3: Run — passes**

Run: `./gradlew :app:testDebugUnitTest`
Expected: `BUILD SUCCESSFUL`; `SetupStepsTest` 2, `SharedStateTest` 11 PASS.

- [ ] **Step 4: Commit**

```bash
cd .. && git add android && git commit -m "Android: sozlash qadamlari holati va do'stni o'chirish

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 3: Ilova ikonkasi

**Files:**
- Create: `android/tools/icon-foreground.html`, `android/tools/render_icon.sh`, `android/app/src/main/res/drawable/ic_launcher_background.xml`, `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`, `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml`
- Generate: `android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Produces: `@mipmap/ic_launcher`, `@drawable/ic_launcher_foreground` (sozlash ekrani sarlavhasida ham ishlatiladi).

- [ ] **Step 1: Oldingi qatlam manbasi va renderer**

`android/tools/icon-foreground.html` — `tools/icon.svg` ning foni olib tashlangan, adaptive icon xavfsiz zonasiga (markazdagi ~60%) sig'dirilgan nusxasi:
```html
<!doctype html>
<html>
<body style="margin:0;background:transparent">
<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 1024 1024">
<defs>
  <linearGradient id="spark" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#3D7BFF"/><stop offset="1" stop-color="#8A4DFF"/>
  </linearGradient>
</defs>
<g transform="translate(512 512) scale(0.64) translate(-512 -560)">
  <g fill="#FFFFFF" opacity="0.26">
    <rect x="140" y="200" width="530" height="330" rx="120"/>
    <path d="M 230 500 L 190 640 L 360 520 Z"/>
  </g>
  <text x="405" y="432" text-anchor="middle" font-family="-apple-system, 'Helvetica Neue', Arial" font-weight="700" font-size="200" fill="#FFFFFF">Aa</text>
  <g fill="#FFFFFF">
    <rect x="354" y="480" width="530" height="330" rx="120"/>
    <path d="M 794 780 L 834 920 L 664 800 Z"/>
  </g>
  <path d="M 585 526 Q 604.52 628.48 707 648 Q 604.52 667.52 585 770 Q 565.48 667.52 463 648 Q 565.48 628.48 585 526 Z" fill="url(#spark)"/>
  <path d="M 772 524 Q 779.68 564.32 820 572 Q 779.68 579.68 772 620 Q 764.32 579.68 724 572 Q 764.32 564.32 772 524 Z" fill="url(#spark)"/>
  <path d="M 762 694 Q 766.48 717.52 790 722 Q 766.48 726.48 762 750 Q 757.52 726.48 734 722 Q 757.52 717.52 762 694 Z" fill="url(#spark)"/>
</g>
</svg>
</body>
</html>
```

`android/tools/render_icon.sh`:
```bash
#!/bin/bash
# Renders the adaptive-icon foreground (tools/icon-foreground.html) to a 432 px transparent PNG.
# Needs a headless Chrome: CHROME=/path/to/chrome tools/render_icon.sh   (run from android/)
set -euo pipefail
CHROME="${CHROME:-$(ls ~/.cache/hyperframes/chrome/chrome-headless-shell/*/chrome-headless-shell-mac-arm64/chrome-headless-shell 2>/dev/null | head -1)}"
[ -x "$CHROME" ] || { echo "set CHROME to a headless Chrome binary"; exit 1; }
OUT="app/src/main/res/drawable-nodpi/ic_launcher_foreground.png"
mkdir -p "$(dirname "$OUT")"
"$CHROME" --headless --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --window-size=432,432 --screenshot="$PWD/$OUT" "file://$PWD/tools/icon-foreground.html" >/dev/null 2>&1
echo "wrote $OUT"
```

Run: `chmod +x tools/render_icon.sh && tools/render_icon.sh && sips -g pixelWidth -g pixelHeight -g hasAlpha app/src/main/res/drawable-nodpi/ic_launcher_foreground.png`
Expected: `wrote …`, 432×432, `hasAlpha: yes`.

- [ ] **Step 2: Fon, adaptive icon, manifest**

`android/app/src/main/res/drawable/ic_launcher_background.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:pathData="M0,0h108v108h-108z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="linear"
                android:startX="0"
                android:startY="0"
                android:endX="108"
                android:endY="108">
                <item android:offset="0" android:color="#FF3D7BFF" />
                <item android:offset="1" android:color="#FF7B4BFF" />
            </gradient>
        </aapt:attr>
    </path>
</vector>
```

`android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` va `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml` (ikkalasi bir xil):
```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
```

`android/app/src/main/AndroidManifest.xml` — `<application` tegini quyidagiga almashtiring (qolgani o'zgarmaydi):
```xml
    <application
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="false"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">
```

- [ ] **Step 3: Tekshirish**

Run: `./gradlew :app:assembleDebug` va ikonkani ko'rish uchun kompozit:
```bash
ffmpeg -v error -y -f lavfi -i "gradients=s=432x432:c0=0x3D7BFF:c1=0x7B4BFF:x0=0:y0=0:x1=432:y1=432:d=1" -i app/src/main/res/drawable-nodpi/ic_launcher_foreground.png -filter_complex "[0][1]overlay,format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lte(hypot(X-216,Y-216),150),255,0)'" -frames:v 1 /tmp/claude-501/icon-preview.png
```
Expected: `BUILD SUCCESSFUL`; preview'da doira ichida pufakchalar, "Aa" va ✨ to'liq ko'rinadi (kesilmagan).

- [ ] **Step 4: Commit**

```bash
cd .. && git add android && git commit -m "Android: ilova ikonkasi (adaptive), zaxiralash o'chiq

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 4: Sozlash ekrani (Compose)

**Files:**
- Create: `.../app/AppTheme.kt`, `.../app/SetupScreen.kt`
- Replace: `.../app/MainActivity.kt`

**Interfaces:**
- Consumes: `ApiKeyStore`, `KeyCheck` (Task 1); `SetupStatus`, `readSetupStatus`, `forgetFriend` (Task 2); `SharedStore`, `Languages` (M2); `DemoChatActivity` (M3).
- Produces: `MainActivity : ComponentActivity`.

- [ ] **Step 1: Mavzu**

`android/app/src/main/java/com/ibrokhim/aikeyboard/app/AppTheme.kt`:
```kotlin
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
```

- [ ] **Step 2: Ekran**

`android/app/src/main/java/com/ibrokhim/aikeyboard/app/SetupScreen.kt`:
```kotlin
package com.ibrokhim.aikeyboard.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ibrokhim.aikeyboard.BuildConfig
import com.ibrokhim.aikeyboard.R
import com.ibrokhim.aikeyboard.ai.KeyCheck
import com.ibrokhim.aikeyboard.data.ApiKeyStore
import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.Languages
import com.ibrokhim.aikeyboard.data.SharedState
import com.ibrokhim.aikeyboard.data.SharedStore
import kotlinx.coroutines.launch

private val Done = Color(0xFF2EAD5B)

/** The app screen: setup steps, the Gemini key, a place to try the keyboard, and its settings (iOS `ContentView`). */
@Composable
fun SetupScreen(resumeTick: Int) {
    val context = LocalContext.current
    val store = remember { SharedStore.get(context) }
    val keys = remember { ApiKeyStore.get(context) }
    val shared by store.state.collectAsState()
    var keyVersion by remember { mutableIntStateOf(0) }
    val status = remember(resumeTick, keyVersion) { readSetupStatus(context, keys) }
    var disclosure by remember { mutableStateOf(false) }
    val now = System.currentTimeMillis()

    Scaffold { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            item { Header(status.done) }
            item { StepsSection(status, context) { disclosure = true } }
            item { KeySection(keys) { keyVersion++ } }
            item { TrySection(context) }
            item { LanguageSection(shared, now) { language -> store.update { it.copy(targetLanguage = language, activeFriend = null) } } }
            item { KeyboardSection(shared, store) }
            if (shared.friends.isNotEmpty()) item { FriendsSection(shared) { name -> store.update { it.forgetFriend(name) } } }
            shared.context?.let { analysis -> item { ContextSection(analysis, stale = shared.freshContext(now) == null) } }
            item { PrivacySection() }
        }
    }
    if (disclosure) {
        ReaderDisclosure(
            onDismiss = { disclosure = false },
            onAgree = {
                disclosure = false
                context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            },
        )
    }
}

@Composable
private fun Header(done: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(56.dp).clip(RoundedCornerShape(14.dp))
                .background(Brush.linearGradient(listOf(Color(0xFF3D7BFF), Color(0xFF7B4BFF)))),
        ) {
            Image(painterResource(R.drawable.ic_launcher_foreground), contentDescription = null, modifier = Modifier.fillMaxSize())
        }
        Spacer(Modifier.width(14.dp))
        Column {
            Text("AI Keyboard", fontSize = 24.sp, fontWeight = FontWeight.Bold)
            Text(
                if (done) "Tayyor — DM'da klaviaturadagi 📖 ni bosing" else "DM uchun AI klaviatura · beta",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun Section(title: String, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column {
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(8.dp))
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp), content = content)
        }
        if (footer != null) {
            Text(
                footer, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp, start = 4.dp, end = 4.dp),
            )
        }
    }
}

@Composable
private fun StepsSection(status: SetupStatus, context: Context, onReader: () -> Unit) {
    Section("Sozlash") {
        Step(
            1, status.keyboardEnabled, status.current == 0, "Klaviaturani yoqing",
            "Tizim sozlamalaridagi ekran klaviaturalari ro'yxatida AI Keyboard'ni yoqing.", "Ochish",
        ) { context.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)) }
        Step(
            2, status.keyboardSelected, status.current == 1, "AI Keyboard'ni tanlang",
            "Yozish paytida AI Keyboard chiqishi uchun uni joriy klaviatura qiling.", "Tanlash",
        ) { context.getSystemService(InputMethodManager::class.java).showInputMethodPicker() }
        Step(
            3, status.readerEnabled, status.current == 2, "Chatni o'qishga ruxsat bering",
            "📖 bosilganda yozayotgan chatingiz matnini o'qish uchun (Accessibility xizmati).", "Ruxsat berish",
            onReader,
        )
        Step(
            4, status.hasKey, status.current == 3, "Gemini kalitini kiriting",
            "Tarjima va javoblar Google Gemini orqali ishlaydi. Kalit bepul — pastdagi bo'limda.", null,
        ) {}
    }
}

@Composable
private fun Step(number: Int, done: Boolean, current: Boolean, title: String, body: String, action: String?, onAction: () -> Unit) {
    Row(verticalAlignment = Alignment.Top) {
        Box(
            Modifier.size(28.dp).clip(CircleShape).background(
                when {
                    done -> Done
                    current -> MaterialTheme.colorScheme.primary
                    else -> MaterialTheme.colorScheme.surfaceVariant
                },
            ),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                if (done) "✓" else "$number", fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                color = if (done || current) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (!done && action != null) {
                Spacer(Modifier.height(8.dp))
                if (current) Button(onClick = onAction) { Text(action) } else OutlinedButton(onClick = onAction) { Text(action) }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun KeySection(keys: ApiKeyStore, onChanged: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf(keys.userKey.orEmpty()) }
    var message by remember { mutableStateOf<String?>(null) }
    var checking by remember { mutableStateOf(false) }
    Section(
        "Gemini kaliti",
        footer = "Kalit faqat shu telefonda saqlanadi va faqat Google Gemini'ga yuboriladi. " +
            "Bepul kalit: aistudio.google.com/apikey",
    ) {
        OutlinedTextField(
            value = text,
            onValueChange = {
                text = it.trim()
                message = null
            },
            label = { Text("API kalit") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth(),
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = {
                keys.userKey = text
                onChanged()
                message = if (text.isBlank()) "Kalit o'chirildi" else "Saqlandi"
            }) { Text("Saqlash") }
            OutlinedButton(
                enabled = !checking && (text.isNotBlank() || keys.effectiveKey().isNotBlank()),
                onClick = {
                    checking = true
                    scope.launch {
                        message = KeyCheck.check(text.ifBlank { keys.effectiveKey() }) ?: "✓ Kalit ishlayapti"
                        checking = false
                    }
                },
            ) { Text(if (checking) "Tekshirilmoqda…" else "Tekshirish") }
            TextButton(onClick = {
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://aistudio.google.com/apikey")))
            }) { Text("Kalit olish") }
        }
        message?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
        if (keys.userKey == null && BuildConfig.GEMINI_API_KEY.isNotBlank()) {
            Text(
                "Debug build: local.properties'dagi kalit ishlatilyapti.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun TrySection(context: Context) {
    var text by remember { mutableStateOf("") }
    Section("Sinab ko'rish", footer = "Demo chatda to'qima Emma suhbati bor — 📖 va ✨ ni messengersiz sinash mumkin.") {
        Button(onClick = { context.startActivity(Intent(context, DemoChatActivity::class.java)) }) { Text("Demo chatni ochish") }
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            label = { Text("Shu yerga yozib ko'ring") },
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LanguageSection(shared: SharedState, now: Long, onSelect: (String) -> Unit) {
    val current = shared.language(now)
    Section(
        "✨ qaysi tilga yozadi",
        footer = "O'zi almashadi: chat o'qilgandan keyin — suhbat tiliga. Klaviaturada do'stingiz nomini bossangiz — uning tiliga.",
    ) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            (listOf(current) + Languages.common.filter { it != current }).forEach { language ->
                FilterChip(
                    selected = language == current,
                    onClick = { onSelect(language) },
                    label = { Text("${Languages.flag(language)} $language") },
                )
            }
        }
    }
}

@Composable
private fun KeyboardSection(shared: SharedState, store: SharedStore) {
    Section("Klaviatura") {
        SettingSwitch(
            "😀 tugmasi",
            "КИР/LAT o'rniga emoji paneli. Klaviatura lotin yozuvida qoladi — kirill kerak bo'lsa, o'chiring.",
            shared.emojiKey,
        ) { on -> store.update { it.copy(emojiKey = on) } }
        SettingSwitch(
            "Avtomatik o'qish",
            "Messengerda klaviatura ochilganda chat 📖 bosilmasdan o'qiladi va Gemini'ga yuboriladi. " +
                "Chat o'zgarmasa qayta yuborilmaydi.",
            shared.autoRead,
        ) { on -> store.update { it.copy(autoRead = on) } }
    }
}

@Composable
private fun SettingSwitch(title: String, body: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun FriendsSection(shared: SharedState, onForget: (String) -> Unit) {
    Section("Do'stlar", footer = "Har chat o'qilgandan keyin eslab qolinadi. Klaviaturada ularni bir bosishda tanlaysiz.") {
        shared.friends.forEach { friend ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("${Languages.flag(friend.language)} ${friend.name}", style = MaterialTheme.typography.titleSmall)
                    Text(
                        listOf(friend.language, friend.tone).filter { it.isNotBlank() }.joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                TextButton(onClick = { onForget(friend.name) }) { Text("O'chirish") }
            }
        }
    }
}

@Composable
private fun ContextSection(context: ChatAnalysis, stale: Boolean) {
    Section(
        "Oxirgi kontekst",
        footer = if (stale) "Eskirgan: klaviatura 15 daqiqadan eski kontekstni ko'rsatmaydi." else null,
    ) {
        Text(context.partner.ifEmpty { "Suhbat" }, style = MaterialTheme.typography.titleSmall)
        if (context.summaryUz.isNotEmpty()) Text(context.summaryUz, style = MaterialTheme.typography.bodyMedium)
        if (context.lastIncomingUz.isNotEmpty()) {
            Text(context.lastIncomingUz, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun PrivacySection() {
    Section("Maxfiylik") {
        Text(
            "• Chat faqat 📖 bosilganda yoki siz yoqqan avtomatik o'qishda, faqat messengerlarda o'qiladi.\n" +
                "• O'qilgan matn (ilova matnni bermasa — skrinshot) faqat Google Gemini'ga yuboriladi.\n" +
                "• Telefonda oxirgi 6 ta xabar va do'stlar ro'yxati saqlanadi; zaxira nusxaga tushmaydi.\n" +
                "• Klaviatura yozganingizni hech qayerga yubormaydi — faqat ✨ bosilganda qoralama.",
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
private fun ReaderDisclosure(onDismiss: () -> Unit, onAgree: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Chatni o'qish") },
        text = {
            Text(
                "AI Keyboard Accessibility xizmati orqali yozayotgan chatingiz matnini o'qiydi:\n\n" +
                    "• faqat klaviaturadagi 📖 bosilganda yoki siz yoqqan avtomatik o'qishda (messengerlarda);\n" +
                    "• matn (ilova matnni bermasa — ekran skrinshoti) tarjima va javoblar uchun Google Gemini'ga yuboriladi;\n" +
                    "• yozish maydonlari (parollar ham) o'qilmaydi, boshqa paytda xizmat hech narsa qilmaydi.\n\n" +
                    "Davom etsangiz, Accessibility sozlamalari ochiladi — «AI Keyboard — chatni o'qish»ni yoqing.",
            )
        },
        confirmButton = { Button(onClick = onAgree) { Text("Roziman") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Bekor qilish") } },
    )
}
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/app/MainActivity.kt`:
```kotlin
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
```

- [ ] **Step 3: Build**

Run: `./gradlew :app:testDebugUnitTest :app:assembleDebug`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Emulyatorda ko'rish**

`android-reinstall.sh` → bosh ekran skrinshoti: sarlavha (ikonka), 4 qadam ✓ (emulyatorda klaviatura, xizmat va debug kalit bor), kalit bo'limi, sinov, til chiplari, switch'lar, do'stlar (Emma), oxirgi kontekst, maxfiylik. "Tekshirish" → "✓ Kalit ishlayapti". Kalit maydoniga `bad-key` yozib "Tekshirish" → "Kalit noto'g'ri yoki faol emas" (saqlamasdan). "Ruxsat berish" tugmasi (xizmat o'chirilgan holda) → tushuntirish dialogi.

- [ ] **Step 5: Commit**

```bash
cd .. && git add android && git commit -m "Android: sozlash ekrani — qadamlar, Gemini kaliti, til, klaviatura, do'stlar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 5: Release imzosi, README/CONTRIBUTING va release APK

**Files:**
- Modify: `android/app/build.gradle.kts`, `android/.gitignore`, `README.md`, `CONTRIBUTING.md`
- Create (repodan tashqarida): `~/.android/ai-keyboard-release.jks`; gitignore: `android/keystore.properties`

**Interfaces:**
- Produces: `android/app/build/outputs/apk/release/app-release.apk` (imzolangan, kalitsiz).

- [ ] **Step 1: Kalit fayli (parol ekranga chiqmaydi)**

Run:
```bash
python3 - <<'PY'
import os, secrets, subprocess, pathlib
jks = pathlib.Path.home() / ".android/ai-keyboard-release.jks"
props = pathlib.Path("keystore.properties")
if jks.exists():
    raise SystemExit(f"{jks} already exists — reuse it, do not regenerate")
password = secrets.token_urlsafe(24)
subprocess.run(["keytool", "-genkeypair", "-keystore", str(jks), "-alias", "aikeyboard", "-keyalg", "RSA",
                "-keysize", "4096", "-validity", "36500", "-dname", "CN=AI Keyboard",
                "-storepass", password, "-keypass", password], check=True, capture_output=True)
props.write_text(f"storeFile={jks}\nstorePassword={password}\nkeyAlias=aikeyboard\nkeyPassword={password}\n")
os.chmod(props, 0o600)
print("keystore:", jks, "| properties:", props.resolve())
PY
```

`android/.gitignore`:
```
.gradle/
.kotlin/
build/
local.properties
keystore.properties
*.jks
.idea/
*.iml
captures/
```

- [ ] **Step 2: Imzolash build'da**

`android/app/build.gradle.kts` — `val localProperties = …` blokidan keyin qo'shing:
```kotlin

// Release signing: the keystore lives outside the repo, its passwords in the gitignored keystore.properties.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
```
`android {` ichida `buildFeatures` dan oldin qo'shing:
```kotlin
    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

```
`release {` bloki ichida `isMinifyEnabled = false` dan keyin qo'shing:
```kotlin
            signingConfig = signingConfigs.findByName("release")
```

Run:
```bash
./gradlew :app:testDebugUnitTest :app:assembleRelease
~/Library/Android/sdk/build-tools/36.0.0/apksigner verify --print-certs app/build/outputs/apk/release/app-release.apk | head -3
unzip -p app/build/outputs/apk/release/app-release.apk classes*.dex | grep -c "$(grep gemini.apiKey local.properties | cut -d= -f2 | cut -c1-12)" || true
```
Expected: `BUILD SUCCESSFUL`; `Signer #1 certificate DN: CN=AI Keyboard`; oxirgi buyruq `0` (APK ichida dev kalit yo'q).

- [ ] **Step 3: README — Android bo'limi**

`README.md` birinchi qatori va kirish paragrafini almashtiring:
```markdown
# AI Keyboard — DM uchun AI klaviatura

Chet ellik do'stlar bilan DM'da yozishish uchun iOS va Android klaviatura. Klaviatura ekrandagi suhbatni o'qiydi,
kelgan xabar tarjimasi va 3 ta tayyor javobni chiqaradi. Yoqmasa — o'zbekcha yozib ✨ ni bosasiz, AI suhbat
kontekstiga mos tarjima qilib beradi. iOS'da suhbat telefon orqasiga 2 marta urib (Back Tap) o'qiladi, Android'da —
klaviaturadagi 📖 tugmasi bilan yoki avtomatik.
```
va `## Hissa qo'shish` sarlavhasidan oldin qo'shing:
```markdown
## Android (beta)

`android/` — Kotlin, alohida Gradle loyiha. iOS bilan bir xil imkoniyatlar: tarjima + 3 javob, ✨, do'stlarni
eslab qolish, lotin/kirill, emoji paneli. Farqi — suhbatni qanday o'qishi:

- Klaviaturadagi **📖** bosilganda Accessibility xizmati yozayotgan ilovangizdagi chat **matnini** o'qiydi
  (skrinshotsiz — tezroq va arzonroq). Ilova matnni bermasa, skrinshot olinadi (Android 11+).
- **Avtomatik o'qish** (sozlama, standart o'chiq): messengerda klaviatura ochilishi bilan tarjima tayyor.
  Chat o'zgarmasa Gemini'ga qayta yuborilmaydi.
- Gemini kalitini har kim **o'zi kiritadi** (bepul: [aistudio.google.com/apikey](https://aistudio.google.com/apikey)) —
  APK ichida kalit yo'q.

### O'rnatish

1. [Releases](https://github.com/ibroxiim/ai-keyboard/releases) dan `AIKeyboard-*.apk` ni yuklab oching
   (brauzerga "noma'lum ilovalarni o'rnatish" ruxsatini bering).
2. AI Keyboard ilovasida 4 qadam: klaviaturani yoqish → tanlash → chatni o'qishga ruxsat → Gemini kaliti.
3. DM'da klaviaturadagi **📖 Chatni o'qish** ni bosing.

### Manbadan build

```bash
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties
echo "gemini.apiKey=SIZNING_KALITINGIZ" >> local.properties   # faqat debug build uchun, ixtiyoriy
./gradlew :app:testDebugUnitTest :app:assembleDebug
```

Android Studio bilan ham ochiladi (`android/` papkasini). JDK 17+, compileSdk 36.

| Papka | Nima |
|---|---|
| `android/.../ime/` | Klaviatura: tugmalar (Canvas), takliflar paneli (Compose), emoji, avtomatik o'qish |
| `android/.../reader/` | Accessibility xizmati: chat matnini `[TOP]/[L]/[R]` qatorlarga o'giradi |
| `android/.../ai/` | Gemini klienti (zaxira modelga parallel so'rov), promptlar, tahlil |
| `android/.../data/` | Holat (JSON + StateFlow), do'stlar, kalit |
| `android/.../app/` | Sozlash ekrani, demo chat |

```
`## Cheklovlar` bo'limidagi API kalit bandini almashtiring:
```markdown
- iOS: API kalit ilova ichida — faqat shaxsiy foydalanish uchun. Boshqalarga tarqatishdan oldin kalitni server
  (masalan Cloudflare Worker) orqasiga o'tkazish kerak. Android'da har foydalanuvchi o'z kalitini kiritadi.
- Android: Google Play hozircha yo'q — Play Accessibility API'dan foydalanishni cheklaydi; Play versiyasi uchun
  skrinshot (MediaProjection) varianti keyinroq.
```

- [ ] **Step 4: CONTRIBUTING — Android**

`CONTRIBUTING.md` da `## Sinash` sarlavhasidan oldin qo'shing:
```markdown
## Android

```bash
cd android
./gradlew :app:testDebugUnitTest      # JVM testlar (Gemini'ga murojaat qilmaydi)
./gradlew :app:assembleDebug          # app/build/outputs/apk/debug/app-debug.apk
LIVE_GEMINI=1 ./gradlew :app:testDebugUnitTest --tests '*GeminiLiveTest'   # haqiqiy Gemini (kalit local.properties'da)
```

Emulyatorda: `adb shell ime enable/set com.ibrokhim.aikeyboard/.ime.AiKeyboardService`, ilovadagi "Demo chat"da
📖 ni sinang. Debug build `AIKeys` logcat tegida tugma koordinatalarini yozadi — `android/tools/adb-type.py "matn"`
ular orqali matnni tugmalar bilan yozadi. Kod va testlarda faqat to'qima ismlar va suhbatlar.

```

- [ ] **Step 5: Release APK'ni emulyatorda sinash**

```bash
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB uninstall com.ibrokhim.aikeyboard     # debug va release imzolari har xil
$ADB install app/build/outputs/apk/release/app-release.apk
$ADB shell am start -n com.ibrokhim.aikeyboard/.app.MainActivity
```
Tekshiriladi: sozlash ekranida 4 qadam ham bajarilmagan (1-qadam faol). `ime enable/set` va Accessibility'ni `adb` bilan yoqib, ilovaga qaytish — 1–3 ✓, 4 — kalit yo'q. Demo chatda 📖 → panelda "Gemini API kaliti kiritilmagan — AI Keyboard ilovasini oching". Kalitni ilovada kiritib (qiymat `local.properties`dan `adb shell input text` orqali, ekranga chiqarmasdan) "Saqlash" → 4 ✓ → demo chatda 📖 → tarjima va javoblar.

- [ ] **Step 6: Commit**

```bash
cd .. && git add android README.md CONTRIBUTING.md && git commit -m "Android: release imzosi, README va CONTRIBUTING'da Android bo'limi

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android README.md CONTRIBUTING.md
```

---

### Task 6: Push va GitHub Release (foydalanuvchi tasdig'idan keyin)

Bu vazifa ommaviy — faqat foydalanuvchi "ha" deganidan keyin:

1. Push qilishdan oldin sirlarni tekshirish: `git log -p main..android | grep -iE "AIza|storePassword|gemini.apiKey="` bo'sh bo'lishi kerak.
2. `git push -u origin android` → `main`ga PR (himoya: PR kerak; egasi o'zi merge qila oladi).
3. Merge'dan keyin `v0.1.0-android-beta` tag va GitHub Release: `AIKeyboard-0.1.0-beta.apk` (release APK nusxasi), o'zbekcha izoh (nima bor, o'rnatish, Accessibility nimaga kerak, beta ekanligi).
