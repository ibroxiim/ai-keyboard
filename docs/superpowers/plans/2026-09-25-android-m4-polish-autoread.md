# Android M4 — emoji, popup, tebranish, tafsilotlar va avtomatik o'qish: implementatsiya rejasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS bilan tenglikni yopish: emoji paneli (1297 ta, toifalar, "ko'p ishlatilgan"), bosilgan harf pufakchasi, tizimga bo'ysunuvchi tebranish va ovoz, tarjima bosilganda to'liq suhbat (`ContextDetails`), messengerda klaviatura ochilganda avtomatik o'qish (sozlama, standart o'chiq), ortiqcha globus olib tashlanadi.

**Architecture:** Toza qismlar test bilan: `EmojiData` (iOS ro'yxatidan generator bilan), `EmojiRecents`, `AutoRead`, `KeyboardController` (emoji holati), `KeyboardAi` (tafsilotlar va avtomatik o'qish). Ko'rinish: `EmojiPanel` va `ContextDetails` (Compose) tugmalar o'rnida `FrameLayout`da ko'rsatiladi (tugmalar `INVISIBLE` qoladi — balandlik o'zgarmaydi); pufakcha `KeysView`da chiziladi, konteynerlar `clipChildren=false`. Sozlamalar (😀 tugmasi, avtomatik o'qish) M5 gacha `MainActivity`dagi ikki switch'da. Spec: `docs/superpowers/specs/2026-09-25-android-version-design.md` (4-bosqich).

**Tech Stack:** M1–M3 bilan bir xil (Compose BOM 2026.06.01).

## Global Constraints

- M1–M3 cheklovlari amal qiladi.
- Avtomatik o'qish: faqat `autoRead == true`, package messengerlar ro'yxatida (`com.instagram.android`, `org.telegram.messenger`, `com.whatsapp`, `com.facebook.orca`, `com.snapchat.android`, `com.discord`, `jp.naver.line.android`, `com.kakao.talk`, `com.ibrokhim.aikeyboard`), maydon matnli va parol/email/URL emas; faqat matn (skrinshot yo'q); chat qatorlari xeshi `lastReadHash` bilan bir xil va kontekst hali yangi bo'lsa — Gemini'ga so'rov ketmaydi. Klaviatura ko'rinishidan 300 ms keyin o'qiladi.
- Emoji: 8 toifa, jami 1297 (iOS `Keyboard/EmojiData.swift`), "ko'p ishlatilgan" max 32.
- Tebranish `HapticFeedbackConstants.KEYBOARD_TAP` (tizim sozlamasi), ovoz `AudioManager.playSoundEffect` (tizimning "Touch sounds" sozlamasi).
- Globus tugmasi yo'q (`supportsSwitchingToNextInputMethod="false"`): Android navigatsiya panelida o'zining klaviatura almashtirgichini ko'rsatadi.

## Fayllar

| Fayl | Vazifasi |
|---|---|
| `android/tools/port_emoji.py` | `Keyboard/EmojiData.swift` → `EmojiData.kt` |
| `.../ime/EmojiData.kt` (generatsiya), `.../ime/EmojiRecents.kt` | Emoji ro'yxati va oxirgilari |
| `.../ime/KeyboardController.kt` | `showsEmoji`, `closeEmoji()`, `insertEmoji()` |
| `.../ime/ui/EmojiPanel.kt` | Compose emoji paneli |
| `.../ime/KeysView.kt` | Pufakcha, tebranish, ovoz |
| `.../ime/EditorRules.kt` | `isChatField()` |
| `.../ime/AutoRead.kt` | Avtomatik o'qish qoidalari (sof) |
| `.../ime/KeyboardAi.kt` | `detailsOpen`, `openDetails/closeDetails`, `autoRead`, `ChatSource.read(…, allowScreenshot)` |
| `.../reader/AccessibilityChatSource.kt` | `allowScreenshot` |
| `.../ime/ui/ContextDetails.kt`, `.../ime/ui/SuggestionBar.kt` | Tafsilotlar paneli, tarjimani bosish |
| `.../ime/AiKeyboardService.kt` | Pastki soha rejimlari, emoji/tafsilotlar, avtomatik o'qish, globussiz |
| `android/app/src/main/res/xml/method.xml`, `.../app/MainActivity.kt` | Globus o'chiq; vaqtinchalik sozlama switch'lari |
| testlar: `EmojiDataTest`, `EmojiRecentsTest`, `AutoReadTest`, `KeyboardControllerTest`, `KeyboardAiTest` | JVM |

`...` = `android/app/src/main/java/com/ibrokhim/aikeyboard`. Buyruqlar `android/` papkasida.

---

### Task 1: Emoji ro'yxati (generator) va `EmojiRecents`

**Files:**
- Create: `android/tools/port_emoji.py`, `.../ime/EmojiRecents.kt`
- Generate: `.../ime/EmojiData.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/EmojiDataTest.kt`, `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/EmojiRecentsTest.kt`

**Interfaces:**
- Produces: `data class EmojiCategory(title: String, icon: String, emojis: List<String>)`, `EmojiData.categories: List<EmojiCategory>`, `class EmojiRecents(load: () -> List<String>, save: (List<String>) -> Unit) { val all; fun add(emoji); LIMIT = 32 }`.

- [ ] **Step 1: Failing tests**

`android/app/src/test/java/com/ibrokhim/aikeyboard/ime/EmojiDataTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EmojiDataTest {
    @Test fun sameListAsIos() {
        assertEquals(8, EmojiData.categories.size)
        assertEquals(1297, EmojiData.categories.sumOf { it.emojis.size })
        assertEquals("Smayllar va odamlar", EmojiData.categories.first().title)
        assertEquals("😀", EmojiData.categories.first().emojis.first())
    }

    @Test fun everyCategoryHasAnIconAndNoBlanks() {
        EmojiData.categories.forEach { category ->
            assertTrue(category.icon.isNotBlank())
            assertTrue(category.emojis.none { it.isBlank() })
        }
    }
}
```

`android/app/src/test/java/com/ibrokhim/aikeyboard/ime/EmojiRecentsTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import org.junit.Assert.assertEquals
import org.junit.Test

class EmojiRecentsTest {
    private var stored = emptyList<String>()
    private val recents = EmojiRecents({ stored }, { stored = it })

    @Test fun newestFirstWithoutDuplicates() {
        recents.add("😀")
        recents.add("🔥")
        recents.add("😀")
        assertEquals(listOf("😀", "🔥"), recents.all)
    }

    @Test fun keepsThirtyTwo() {
        (1..40).forEach { recents.add("e$it") }
        assertEquals(EmojiRecents.LIMIT, recents.all.size)
        assertEquals("e40", recents.all.first())
    }
}
```

- [ ] **Step 2: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*EmojiDataTest' --tests '*EmojiRecentsTest'`
Expected: FAIL — `Unresolved reference 'EmojiData'`.

- [ ] **Step 3: Generator va implementatsiya**

`android/tools/port_emoji.py`:
```python
#!/usr/bin/env python3
"""Ports the iOS emoji list (Keyboard/EmojiData.swift) to the Android keyboard.

Run from android/:  python3 tools/port_emoji.py   — rerun whenever the Swift list changes.
"""
import pathlib, re

root = pathlib.Path(__file__).resolve().parents[2]
swift = (root / "Keyboard/EmojiData.swift").read_text()
out = root / "android/app/src/main/java/com/ibrokhim/aikeyboard/ime/EmojiData.kt"

# SF Symbol names on iOS → a representative emoji for the Android category tab.
ICONS = {
    "face.smiling": "😀", "pawprint": "🐻", "fork.knife": "🍔", "soccerball": "⚽",
    "car": "🚗", "lightbulb": "💡", "heart": "❤️", "flag": "🏳️",
}

categories = re.findall(
    r'EmojiCategory\(title: "([^"]+)", symbol: "([^"]+)", emojis: split\("""\n(.*?)\n\s*"""\)\)', swift, re.S)
assert categories, "no categories found in EmojiData.swift"

blocks = []
for title, symbol, body in categories:
    lines = [" ".join(line.split()) for line in body.strip().splitlines() if line.strip()]
    assert not any("$" in line or '"""' in line for line in lines)
    joined = "\n".join("            " + line for line in lines)
    blocks.append(f'        EmojiCategory(\n            "{title}", "{ICONS[symbol]}",\n            split(\n                """\n{joined}\n                """,\n            ),\n        ),')

out.write_text(
    "// Generated by android/tools/port_emoji.py from Keyboard/EmojiData.swift — edit the Swift list and rerun.\n"
    "package com.ibrokhim.aikeyboard.ime\n\n"
    "data class EmojiCategory(val title: String, val icon: String, val emojis: List<String>)\n\n"
    "/** The iOS keyboard's curated emoji list, in the system keyboard's category order. */\n"
    "object EmojiData {\n"
    "    val categories: List<EmojiCategory> = listOf(\n"
    + "\n".join(blocks) + "\n"
    "    )\n\n"
    "    private fun split(text: String): List<String> = text.split(Regex(\"\\\\s+\")).filter { it.isNotEmpty() }\n"
    "}\n"
)
total = sum(len(body.split()) for _, _, body in categories)
print(f"wrote {out.relative_to(root)}: {len(categories)} categories, {total} emoji")
```

Run: `python3 tools/port_emoji.py`
Expected: `wrote android/app/src/main/java/com/ibrokhim/aikeyboard/ime/EmojiData.kt: 8 categories, 1297 emoji`

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/EmojiRecents.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

/** Recently used emoji, most recent first. Storage is injected so the rule stays testable. */
class EmojiRecents(private val load: () -> List<String>, private val save: (List<String>) -> Unit) {
    val all: List<String> get() = load()

    fun add(emoji: String) {
        save((listOf(emoji) + load().filter { it != emoji }).take(LIMIT))
    }

    companion object {
        const val LIMIT = 32
    }
}
```

- [ ] **Step 4: Run — passes**

Run: `./gradlew :app:testDebugUnitTest --tests '*EmojiDataTest' --tests '*EmojiRecentsTest'`
Expected: `BUILD SUCCESSFUL`, 4 test PASS.

- [ ] **Step 5: Commit**

```bash
cd .. && git add android && git commit -m "Android: emoji ro'yxati (iOS'dan generator) va oxirgilari

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 2: Emoji tugmasi va emoji paneli

**Files:**
- Modify: `.../ime/KeyboardController.kt`, `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/KeyboardControllerTest.kt`
- Create: `.../ime/ui/EmojiPanel.kt`

**Interfaces:**
- Consumes: `EmojiData`, `EmojiCategory` (Task 1); `KeyboardTheme` (M1).
- Produces: `KeyboardController.showsEmoji: Boolean`, `closeEmoji()`, `insertEmoji(emoji: String)`; `@Composable fun EmojiPanel(recents: List<String>, theme: KeyboardTheme, bottomInset: Dp, onEmoji: (String) -> Unit, onAbc: () -> Unit, onBackspace: () -> Unit)`.

- [ ] **Step 1: Failing test**

`KeyboardControllerTest.kt` oxiridagi `}` dan oldin qo'shing:
```kotlin
    @Test fun emojiKeyOpensThePanelAndAbcClosesIt() {
        controller.press(Key.Emoji)
        assertEquals(true, controller.showsEmoji)
        controller.closeEmoji()
        assertEquals(false, controller.showsEmoji)
    }

    @Test fun emojiGoesInAsIs() {
        controller.autoCapitalize()
        controller.insertEmoji("😀")
        controller.press(Key.Text("x"))
        assertEquals("😀x", target.text.toString())
    }
```

Run: `./gradlew :app:testDebugUnitTest --tests '*KeyboardControllerTest'`
Expected: FAIL — `Unresolved reference 'showsEmoji'`.

- [ ] **Step 2: Controller**

`KeyboardController.kt` da:

1. `var emojiKey = false` qatoridan keyin qo'shing:
```kotlin

    /** The emoji panel replaces the keys: the 😀 key opens it, its ABC button closes it. */
    var showsEmoji = false
        private set
```
2. `press()` dagi `Key.Emoji -> Unit // the emoji panel arrives in milestone 4` qatorini almashtiring:
```kotlin
            Key.Emoji -> {
                showsEmoji = true
                onChange()
            }
```
3. `fun moveCursor` dan oldin qo'shing:
```kotlin
    fun closeEmoji() {
        if (showsEmoji) {
            showsEmoji = false
            onChange()
        }
    }

    /** Emoji go in as they are; the panel stays open for the next one. */
    fun insertEmoji(emoji: String) {
        target.commit(emoji)
        autoCapitalize()
    }

```

Run: `./gradlew :app:testDebugUnitTest --tests '*KeyboardControllerTest'`
Expected: PASS (13 test).

- [ ] **Step 3: Emoji paneli**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/ui/EmojiPanel.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime.ui

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyHorizontalGrid
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ibrokhim.aikeyboard.R
import com.ibrokhim.aikeyboard.ime.EmojiCategory
import com.ibrokhim.aikeyboard.ime.EmojiData
import com.ibrokhim.aikeyboard.ime.KeyboardTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The keyboard's own emoji panel, laid out like the system one: a horizontally scrolling 5-row grid,
 * the category name on top, ABC · categories · ⌫ at the bottom (iOS `EmojiPanelView`).
 */
@Composable
fun EmojiPanel(
    recents: List<String>,
    theme: KeyboardTheme,
    bottomInset: Dp,
    onEmoji: (String) -> Unit,
    onAbc: () -> Unit,
    onBackspace: () -> Unit,
) {
    val ink = Color(theme.label)
    val muted = ink.copy(alpha = 0.55f)
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val sections = remember(recents) {
        val recent = if (recents.isEmpty()) emptyList() else listOf(EmojiCategory("Ko'p ishlatilgan", "🕘", recents))
        recent + EmojiData.categories
    }
    val starts = remember(sections) { sections.runningFold(0) { start, section -> start + section.emojis.size }.dropLast(1) }
    val all = remember(sections) { sections.flatMap { it.emojis } }
    val grid = rememberLazyGridState()
    val current by remember(starts) {
        derivedStateOf { starts.indexOfLast { it <= grid.firstVisibleItemIndex }.coerceAtLeast(0) }
    }

    Column(Modifier.fillMaxSize().background(Color(theme.background)).padding(bottom = bottomInset)) {
        Text(
            sections[current].title.uppercase(), color = muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(start = 12.dp, top = 4.dp).height(16.dp),
        )
        LazyHorizontalGrid(
            rows = GridCells.Fixed(5),
            state = grid,
            modifier = Modifier.fillMaxWidth().weight(1f),
            contentPadding = PaddingValues(horizontal = 4.dp),
        ) {
            items(all.size) { index ->
                val emoji = all[index]
                Box(
                    Modifier.width(44.dp).fillMaxHeight().clickable {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        onEmoji(emoji)
                    },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(emoji, fontSize = 26.sp)
                }
            }
        }
        Row(Modifier.fillMaxWidth().height(40.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1.4f).fillMaxHeight().clickable(onClick = onAbc), contentAlignment = Alignment.Center) {
                Text("ABC", color = ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            }
            sections.forEachIndexed { index, section ->
                Box(
                    Modifier.weight(1f).fillMaxHeight().clickable { scope.launch { grid.scrollToItem(starts[index]) } },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(section.icon, fontSize = 18.sp, modifier = Modifier.alpha(if (index == current) 1f else 0.4f))
                }
            }
            Box(
                Modifier.weight(1.4f).fillMaxHeight().pointerInput(onBackspace) {
                    detectTapGestures(onPress = {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        onBackspace()
                        val repeat = scope.launch {
                            delay(400)
                            while (true) {
                                onBackspace()
                                delay(60)
                            }
                        }
                        tryAwaitRelease()
                        repeat.cancel()
                    })
                },
                contentAlignment = Alignment.Center,
            ) {
                Icon(painterResource(R.drawable.key_backspace), contentDescription = "O'chirish", tint = ink, modifier = Modifier.size(22.dp))
            }
        }
    }
}
```

- [ ] **Step 4: Build**

Run: `./gradlew :app:testDebugUnitTest :app:assembleDebug`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
cd .. && git add android && git commit -m "Android: emoji tugmasi va emoji paneli

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 3: Harf pufakchasi, tebranish va ovoz (`KeysView`)

**Files:**
- Modify: `.../ime/KeysView.kt`

**Interfaces:**
- Consumes: `Key`, `KeyboardTheme` (M1).
- Produces: `KeysView` o'z chegarasidan yuqoriga chizadi — ota konteynerlar `clipChildren = false` bo'lishi kerak (Task 5).

- [ ] **Step 1: Importlar va maydonlar**

`KeysView.kt` importlariga qo'shing:
```kotlin
import android.media.AudioManager
import android.view.HapticFeedbackConstants
```
`private val text = Paint(...)` qatoridan keyin qo'shing:
```kotlin
    private val balloonText = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    /** The letter balloon rises this far above the key and is this much wider on each side (iOS style). */
    private val balloonRise = dp(54f)
    private val balloonGrow = dp(10f)
```

- [ ] **Step 2: Pufakcha**

`onDraw` oxiriga (`caps.forEachIndexed { ... }` blokidan keyin) qo'shing:
```kotlin
        // Balloons last, so they cover their neighbours and, on the top row, the bar above.
        for (pointer in pointers) {
            val cap = caps.getOrNull(pointer.index) ?: continue
            if (cap.key is Key.Text) drawBalloon(canvas, cap)
        }
```
`drawLabel` funksiyasidan keyin qo'shing:
```kotlin
    private fun drawBalloon(canvas: Canvas, cap: Cap) {
        val frame = cap.frame
        val rect = RectF(
            (frame.left - balloonGrow).coerceAtLeast(0f),
            frame.top - balloonRise,
            (frame.right + balloonGrow).coerceAtMost(width.toFloat()),
            frame.bottom,
        )
        fill.color = theme.key
        fill.setShadowLayer(dp(4f), 0f, dp(1f), 0x40000000)
        canvas.drawRoundRect(rect, radius * 1.5f, radius * 1.5f, fill)
        fill.clearShadowLayer()
        balloonText.textSize = dp(32f)
        balloonText.color = theme.label
        val centerY = frame.top - balloonRise / 2 + dp(4f)
        canvas.drawText(label(cap.key), rect.centerX(), centerY - (balloonText.descent() + balloonText.ascent()) / 2, balloonText)
    }

    /** Follows the system: "Haptic feedback" for the tap, "Touch sounds" for the click. */
    private fun feedback(key: Key) {
        performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        val effect = when (key) {
            Key.Space -> AudioManager.FX_KEYPRESS_SPACEBAR
            Key.Backspace -> AudioManager.FX_KEYPRESS_DELETE
            Key.Enter -> AudioManager.FX_KEYPRESS_RETURN
            else -> AudioManager.FX_KEYPRESS_STANDARD
        }
        audio.playSoundEffect(effect, -1f)
    }
```

- [ ] **Step 3: Har bosishda feedback**

`onDown` funksiyasini almashtiring:
```kotlin
    /** Letters type on touch-down so fast two-thumb typing (rollover) never drops a key. */
    private fun onDown(pointer: Pointer) {
        val key = caps[pointer.index].key
        feedback(key)
        when (key) {
            is Key.Text, Key.Shift -> controller.press(key)
            Key.Backspace -> {
                controller.press(key)
                startRepeat()
            }
            else -> Unit // space, enter, layer, alphabet and emoji act on release
        }
    }
```

- [ ] **Step 4: Build**

Run: `./gradlew :app:testDebugUnitTest :app:assembleDebug`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
cd .. && git add android && git commit -m "Android: harf pufakchasi, tebranish va klaviatura ovozi

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 4: Tafsilotlar paneli va avtomatik o'qish

**Files:**
- Modify: `.../ime/EditorRules.kt`, `.../reader/AccessibilityChatSource.kt` (to'liq), `.../ime/ui/SuggestionBar.kt`
- Create: `.../ime/AutoRead.kt`, `.../ime/ui/ContextDetails.kt`
- Replace: `.../ime/KeyboardAi.kt`, `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/KeyboardAiTest.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/ime/AutoReadTest.kt`

**Interfaces:**
- Consumes: `SharedState`, `ChatAnalysis` (M2); `ChatLines.hash` (M3); `KeyboardTheme` (M1).
- Produces: `EditorRules.isChatField(inputType): Boolean`; `AutoRead.MESSENGERS`, `AutoRead.eligible(packageName: String?, inputType: Int, enabled: Boolean)`, `AutoRead.isNew(hash: String, state: SharedState, now: Long)`; `ChatSource.read(packageName: String, allowScreenshot: Boolean = true)`; `AiUiState.detailsOpen`; `KeyboardAi.openDetails()`, `closeDetails()`, `autoRead(packageName: String?, inputType: Int)`, `KeyboardAi.AUTO_READ_DELAY_MS = 300`; `@Composable fun ContextDetails(context: ChatAnalysis, theme: KeyboardTheme, bottomInset: Dp, onClose: () -> Unit)`.

- [ ] **Step 1: Failing tests**

`android/app/src/test/java/com/ibrokhim/aikeyboard/ime/AutoReadTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import android.text.InputType
import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.SharedState
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoReadTest {
    private val text = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES

    @Test fun onlyMessengersWithTheSettingOn() {
        assertTrue(AutoRead.eligible("org.telegram.messenger", text, enabled = true))
        assertFalse(AutoRead.eligible("org.telegram.messenger", text, enabled = false))
        assertFalse(AutoRead.eligible("com.android.chrome", text, enabled = true))
        assertFalse(AutoRead.eligible(null, text, enabled = true))
    }

    @Test fun neverInPasswordEmailUrlOrNumberFields() {
        val pkg = "com.whatsapp"
        assertFalse(AutoRead.eligible(pkg, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD, true))
        assertFalse(AutoRead.eligible(pkg, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS, true))
        assertFalse(AutoRead.eligible(pkg, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI, true))
        assertFalse(AutoRead.eligible(pkg, InputType.TYPE_CLASS_NUMBER, true))
    }

    @Test fun unchangedChatWithAFreshContextIsSkipped() {
        val now = 10_000_000L
        val fresh = SharedState(context = ChatAnalysis(partner = "Emma"), contextDate = now, lastReadHash = "h")
        assertFalse(AutoRead.isNew("h", fresh, now))
        assertTrue(AutoRead.isNew("other", fresh, now))
        assertTrue(AutoRead.isNew("h", fresh.copy(contextDate = now - 16 * 60_000), now))
    }
}
```

`android/app/src/test/java/com/ibrokhim/aikeyboard/ime/KeyboardAiTest.kt` (to'liq almashtiring):
```kotlin
package com.ibrokhim.aikeyboard.ime

import android.text.InputType
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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
        val asked = mutableListOf<Pair<String, Boolean>>()
        override var available = true
        override suspend fun read(packageName: String, allowScreenshot: Boolean): ChatInput? {
            asked.add(packageName to allowScreenshot)
            return input
        }
    }

    private class Llm : LlmClient {
        var calls = 0
        override suspend fun generate(system: String, parts: List<Part>, schema: JsonObject): String {
            calls++
            return when {
                system.contains("- partner:") ->
                    """{"partner":"Emma","language":"English","tone":"casual","last_incoming_uz":"Bo'shmisan?"}"""
                system.contains("- suggestions:") ->
                    """{"summary_uz":"x","transcript":[{"from":"them","text":"u free?"}],"suggestions":[{"text":"yes!","uz":"ha!"}]}"""
                else -> """{"variants":[{"text":"we're getting plov on saturday","uz":"Shanba kuni osh yeymiz"}]}"""
            }
        }
    }

    private val field = Field()
    private val source = Source(ChatInput.Transcript(listOf("[TOP] Emma", "[L] u free?", "[R] maybe")))
    private val llm = Llm()
    private var setupOpened = 0
    private val textField = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES

    private fun TestScope.ai(): Pair<KeyboardAi, SharedStore> {
        val store = SharedStore(File(folder.root, "state.json"))
        val translator = Translator(llm)
        val analysis = ChatAnalysisService(store, translator) { 1_000 }
        return KeyboardAi(store, translator, analysis, field, source, this, { 1_000 }) { setupOpened++ } to store
    }

    @Test fun readChatAnalysesTheChatOfTheFocusedApp() = runTest {
        val (ai, store) = ai()
        ai.readChat("com.example.chat")
        advanceUntilIdle()
        assertEquals(listOf("com.example.chat" to true), source.asked)
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

    @Test fun detailsOpenOnlyWithAFreshContextAndCloseWithIt() = runTest {
        val (ai, store) = ai()
        ai.openDetails()
        assertFalse(ai.ui.value.detailsOpen)
        store.update { it.copy(context = ChatAnalysis(partner = "Emma"), contextDate = 1_000) }
        ai.openDetails()
        assertTrue(ai.ui.value.detailsOpen)
        ai.dismissContext()
        assertNull(store.value.context)
        assertFalse(ai.ui.value.detailsOpen)
    }

    @Test fun autoReadAnalysesAnEligibleChatOnceUntilItChanges() = runTest {
        val (ai, store) = ai()
        store.update { it.copy(autoRead = true) }
        ai.autoRead("com.whatsapp", textField)
        advanceUntilIdle()
        assertEquals(listOf("com.whatsapp" to false), source.asked) // text only, never a screenshot
        assertEquals("Emma", store.value.context?.partner)
        assertNotNull(store.value.lastReadHash)
        assertEquals(2, llm.calls)

        ai.autoRead("com.whatsapp", textField)
        advanceUntilIdle()
        assertEquals(2, llm.calls) // same chat, context still fresh: no new request

        source.input = ChatInput.Transcript(listOf("[TOP] Emma", "[L] u free?", "[R] maybe", "[L] ??"))
        ai.autoRead("com.whatsapp", textField)
        advanceUntilIdle()
        assertEquals(4, llm.calls)
    }

    @Test fun autoReadStaysQuietWhenOffOrOutsideMessengers() = runTest {
        val (ai, store) = ai()
        ai.autoRead("com.whatsapp", textField)
        store.update { it.copy(autoRead = true) }
        ai.autoRead("com.android.chrome", textField)
        advanceUntilIdle()
        assertEquals(emptyList<Pair<String, Boolean>>(), source.asked)
        assertEquals(0, llm.calls)
    }
}
```

- [ ] **Step 2: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*AutoReadTest' --tests '*KeyboardAiTest'`
Expected: FAIL — `Unresolved reference 'AutoRead'`.

- [ ] **Step 3: `EditorRules.isChatField` va `AutoRead`**

`EditorRules.kt` da `fun autoCapitalize(...)` dan oldin qo'shing:
```kotlin
    /** A plain text field — not a password, email address or URL. */
    fun isChatField(inputType: Int): Boolean =
        (inputType and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT &&
            (inputType and InputType.TYPE_MASK_VARIATION) !in noCapsVariations

```

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/AutoRead.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import com.ibrokhim.aikeyboard.data.SharedState

/** When the keyboard may read a chat on its own — an opt-in setting, only in messengers, never twice. */
object AutoRead {
    val MESSENGERS = setOf(
        "com.instagram.android",
        "org.telegram.messenger",
        "com.whatsapp",
        "com.facebook.orca",
        "com.snapchat.android",
        "com.discord",
        "jp.naver.line.android",
        "com.kakao.talk",
        "com.ibrokhim.aikeyboard", // the in-app demo chat
    )

    fun eligible(packageName: String?, inputType: Int, enabled: Boolean): Boolean =
        enabled && packageName in MESSENGERS && EditorRules.isChatField(inputType)

    /** An unchanged chat whose analysis is still on screen is not sent to Gemini again. */
    fun isNew(hash: String, state: SharedState, now: Long): Boolean =
        !(hash == state.lastReadHash && state.freshContext(now) != null)
}
```

- [ ] **Step 4: `KeyboardAi` (to'liq almashtirish) va manba**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/KeyboardAi.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime

import com.ibrokhim.aikeyboard.ai.ChatAnalysisService
import com.ibrokhim.aikeyboard.ai.ChatInput
import com.ibrokhim.aikeyboard.ai.Translator
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.data.Suggestion
import com.ibrokhim.aikeyboard.reader.ChatLines
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

    /**
     * The chat in [packageName]'s window, or null if nothing readable is on screen. A screenshot is the
     * fallback for apps without readable text — only when [allowScreenshot] (never for auto-read).
     */
    suspend fun read(packageName: String, allowScreenshot: Boolean = true): ChatInput?
}

/** Keyboard-local AI state; the shared part (context, friends, target) lives in `SharedStore`. */
data class AiUiState(
    val variants: List<Suggestion> = emptyList(),
    val rewriting: Boolean = false,
    val notice: String? = null,
    val pickerOpen: Boolean = false,
    /** The full conversation replaces the keys (tap on the translation). */
    val detailsOpen: Boolean = false,
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
        state.update { it.copy(variants = emptyList(), pickerOpen = false, detailsOpen = false) }
        readJob?.cancel()
        readJob = scope.launch {
            val input = chatSource.read(packageName, allowScreenshot = true)
            if (input == null) {
                flash(Notices.UNREADABLE)
                return@launch
            }
            analyse(input)
        }
    }

    /**
     * Keyboard opened in a messenger with auto-read on: read the chat's text (no screenshot) and analyse it,
     * unless it is the same chat whose analysis is still on screen.
     */
    fun autoRead(packageName: String?, inputType: Int) {
        val shared = store.value
        if (!AutoRead.eligible(packageName, inputType, shared.autoRead)) return
        if (packageName == null || !chatSource.available || shared.isAnalyzing(clock())) return
        readJob?.cancel()
        readJob = scope.launch {
            delay(AUTO_READ_DELAY_MS) // let the app settle behind the keyboard's slide-in
            val input = chatSource.read(packageName, allowScreenshot = false) as? ChatInput.Transcript ?: return@launch
            val hash = ChatLines.hash(input.lines)
            if (!AutoRead.isNew(hash, store.value, clock())) return@launch
            store.update { it.copy(lastReadHash = hash) }
            analyse(input)
        }
    }

    private suspend fun analyse(input: ChatInput) {
        try {
            analysis.run(input)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // ChatAnalysisService already put the error into the store; the bar shows it.
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
        state.update { it.copy(variants = emptyList(), detailsOpen = false) }
    }

    fun openDetails() {
        if (store.value.freshContext(clock()) != null) state.update { it.copy(detailsOpen = true) }
    }

    fun closeDetails() = state.update { it.copy(detailsOpen = false) }

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
        const val AUTO_READ_DELAY_MS = 300L
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

/** Text first (fast, cheap, exact); a screenshot only when allowed and the app shows no readable bubbles. */
class AccessibilityChatSource : ChatSource {
    override val available: Boolean
        get() = ChatReaderService.instance != null

    override suspend fun read(packageName: String, allowScreenshot: Boolean): ChatInput? {
        val service = ChatReaderService.instance ?: return null
        val lines = withContext(Dispatchers.Default) { service.readLines(packageName) }
        if (lines != null && ChatLines.hasMessages(lines)) return ChatInput.Transcript(lines)
        if (!allowScreenshot) return null
        val jpeg = service.screenshotJpeg() ?: return null
        return ChatInput.Screenshot(jpeg)
    }
}
```

- [ ] **Step 5: Run — passes**

Run: `./gradlew :app:testDebugUnitTest`
Expected: `BUILD SUCCESSFUL`; `AutoReadTest` 3, `KeyboardAiTest` 9 PASS, qolganlari PASS.

- [ ] **Step 6: `ContextDetails` va tarjimani bosish**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ime/ui/ContextDetails.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ime.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.ime.KeyboardTheme

/** The whole analysed conversation in place of the keys (iOS `ContextDetails`). */
@Composable
fun ContextDetails(context: ChatAnalysis, theme: KeyboardTheme, bottomInset: Dp, onClose: () -> Unit) {
    val ink = Color(theme.label)
    val muted = ink.copy(alpha = 0.6f)
    val accent = Color(theme.accent)
    Column(Modifier.fillMaxSize().background(Color(theme.background)).padding(bottom = bottomInset)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                context.partner.ifEmpty { "Suhbat" }, color = ink, fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f),
            )
            Text(
                "Klaviatura", color = accent, fontSize = 14.sp, fontWeight = FontWeight.Medium,
                modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onClose).padding(6.dp),
            )
        }
        Column(
            Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 12.dp).padding(bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (context.summaryUz.isNotEmpty()) Text(context.summaryUz, color = ink, fontSize = 13.sp)
            if (context.lastIncoming.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(context.lastIncoming, color = ink, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                    Text(context.lastIncomingUz, color = muted, fontSize = 13.sp)
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(muted.copy(alpha = 0.3f)))
            context.transcript.forEach { line ->
                val mine = line.from == "me"
                Box(Modifier.fillMaxWidth(), contentAlignment = if (mine) Alignment.CenterEnd else Alignment.CenterStart) {
                    Text(
                        line.text, color = ink, fontSize = 12.5.sp,
                        modifier = Modifier
                            .widthIn(max = 300.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (mine) accent.copy(alpha = 0.25f) else Color(theme.key))
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                    )
                }
            }
        }
    }
}
```

`SuggestionBar.kt` da `Status.Translation` tarmog'idagi `Text(...)` ning `modifier = Modifier.weight(1f),` qismini almashtiring:
```kotlin
                maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).clickable { ai.openDetails() },
```

- [ ] **Step 7: Build**

Run: `./gradlew :app:testDebugUnitTest :app:assembleDebug`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 8: Commit**

```bash
cd .. && git add android && git commit -m "Android: suhbat tafsilotlari va avtomatik o'qish (sozlama, faqat messengerlarda)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 5: Servisga ulash, sozlama switch'lari, globussiz va emulyatorda tekshirish

**Files:**
- Replace: `.../ime/AiKeyboardService.kt`, `.../app/MainActivity.kt`
- Modify: `android/app/src/main/res/xml/method.xml`

**Interfaces:**
- Consumes: hammasi.
- Produces: `MainActivity` switch'lari `SharedState.emojiKey` va `SharedState.autoRead` ni yozadi (M5 gacha).

- [ ] **Step 1: `method.xml` — globus o'chiq**

`android/app/src/main/res/xml/method.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- No globe key: Android shows its own keyboard switcher in the navigation bar. -->
<input-method xmlns:android="http://schemas.android.com/apk/res/android"
    android:supportsSwitchingToNextInputMethod="false">
    <subtype
        android:label="@string/subtype_uz"
        android:imeSubtypeLocale="uz_UZ"
        android:languageTag="uz-Latn-UZ"
        android:imeSubtypeMode="keyboard" />
</input-method>
```

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
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalDensity
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
import com.ibrokhim.aikeyboard.ime.ui.ContextDetails
import com.ibrokhim.aikeyboard.ime.ui.EmojiPanel
import com.ibrokhim.aikeyboard.ime.ui.SuggestionBar
import com.ibrokhim.aikeyboard.ime.ui.barModel
import com.ibrokhim.aikeyboard.reader.AccessibilityChatSource
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

class AiKeyboardService : InputMethodService(), LifecycleOwner, SavedStateRegistryOwner {
    // Compose in an input method needs the owners an Activity would normally provide.
    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateController = SavedStateRegistryController.create(this)
    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val savedStateRegistry: SavedStateRegistry get() = savedStateController.savedStateRegistry

    /** What sits where the keys are. */
    private enum class LowerArea { KEYS, EMOJI, DETAILS }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val prefs by lazy { getSharedPreferences("keyboard", MODE_PRIVATE) }
    private lateinit var controller: KeyboardController
    private lateinit var store: SharedStore
    private lateinit var ai: KeyboardAi
    private lateinit var recents: EmojiRecents
    private var keysView: KeysView? = null
    private var panelView: ComposeView? = null
    private var editorInfo: EditorInfo? = null
    private var savedAlphabet = Alphabet.LATIN

    // Compose state read by the bar and the panels.
    private val barTheme = mutableStateOf<KeyboardTheme?>(null)
    private val lowerArea = mutableStateOf(LowerArea.KEYS)
    private val navigationInset = mutableIntStateOf(0)
    private val recentEmoji = mutableStateOf<List<String>>(emptyList())

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
            updateLowerArea()
        }
        recents = EmojiRecents(
            load = { prefs.getString("emojiRecents", "").orEmpty().split('\n').filter { it.isNotEmpty() } },
            save = { prefs.edit().putString("emojiRecents", it.joinToString("\n")).apply() },
        )
        recentEmoji.value = recents.all

        store = SharedStore.get(this)
        val translator = Translator(GeminiClient(OkHttpGeminiTransport(), { BuildConfig.GEMINI_API_KEY }))
        ai = KeyboardAi(
            store, translator, ChatAnalysisService(store, translator), target, AccessibilityChatSource(), scope,
            openReaderSetup = ::openReaderSettings,
        )
        barTheme.value = KeyboardTheme.from(this)

        scope.launch {
            combine(store.state, ai.ui) { shared, _ -> shared.emojiKey }.collect { emojiKey ->
                if (controller.emojiKey != emojiKey) {
                    controller.emojiKey = emojiKey
                    if (!emojiKey) controller.closeEmoji()
                    keysView?.invalidate()
                }
                updateLowerArea()
            }
        }
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
        val panel = ComposeView(this).apply {
            visibility = View.GONE
            setContent {
                val shared by store.state.collectAsState()
                val current = barTheme.value ?: return@setContent
                val inset = with(LocalDensity.current) { navigationInset.intValue.toDp() }
                when (lowerArea.value) {
                    LowerArea.KEYS -> Unit
                    LowerArea.EMOJI -> EmojiPanel(
                        recents = recentEmoji.value,
                        theme = current,
                        bottomInset = inset,
                        onEmoji = { emoji ->
                            controller.insertEmoji(emoji)
                            recents.add(emoji)
                        },
                        onAbc = { controller.closeEmoji() },
                        onBackspace = { controller.press(Key.Backspace) },
                    )
                    LowerArea.DETAILS -> shared.freshContext(System.currentTimeMillis())?.let { context ->
                        ContextDetails(context, current, inset) { ai.closeDetails() }
                    }
                }
            }
        }.also { panelView = it }
        // The keys stay laid out (INVISIBLE) under a panel, so the keyboard keeps its height.
        val lower = FrameLayout(this).apply {
            clipChildren = false
            clipToPadding = false
            addView(keys, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(panel, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            // Letter balloons on the top row rise over the bar.
            clipChildren = false
            clipToPadding = false
            addView(bar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(lower, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            if (Build.VERSION.SDK_INT >= 30) {
                setOnApplyWindowInsetsListener { _, insets ->
                    val bottom = insets.getInsets(WindowInsets.Type.navigationBars()).bottom
                    keys.setNavigationInset(bottom)
                    navigationInset.intValue = bottom
                    insets
                }
            }
        }
    }

    private fun updateLowerArea() {
        val details = ai.ui.value.detailsOpen && store.value.freshContext(System.currentTimeMillis()) != null
        val area = when {
            details -> LowerArea.DETAILS
            controller.showsEmoji -> LowerArea.EMOJI
            else -> LowerArea.KEYS
        }
        if (area == LowerArea.EMOJI && lowerArea.value != LowerArea.EMOJI) recentEmoji.value = recents.all
        lowerArea.value = area
        keysView?.visibility = if (area == LowerArea.KEYS) View.VISIBLE else View.INVISIBLE
        panelView?.visibility = if (area == LowerArea.KEYS) View.GONE else View.VISIBLE
    }

    /** The keyboard never takes over the whole screen in landscape. */
    override fun onEvaluateFullscreenMode() = false

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        editorInfo = info
        val current = KeyboardTheme.from(this)
        barTheme.value = current
        keysView?.apply {
            this.theme = current
            enterAction = EditorRules.enterAction(info.imeOptions)
        }
        controller.closeEmoji()
        ai.closeDetails()
        controller.setLayer(Layer.LETTERS)
        controller.autoCapitalize()
        keysView?.invalidate()
        if (!restarting) ai.autoRead(info.packageName, info.inputType)
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

- [ ] **Step 3: Sozlama switch'lari (M5 gacha)**

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
import android.widget.Switch
import android.widget.TextView
import com.ibrokhim.aikeyboard.data.SharedStore

/** Stand-in until milestone 5: a field to type into, the demo chat and the two keyboard settings. */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val store = SharedStore.get(this)
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
        root.addView(Switch(this).apply {
            text = "😀 tugmasi (КИР/LAT o'rniga)"
            isChecked = store.value.emojiKey
            setOnCheckedChangeListener { _, on -> store.update { it.copy(emojiKey = on) } }
        })
        root.addView(Switch(this).apply {
            text = "Messengerda klaviatura ochilganda chatni avtomatik o'qish"
            isChecked = store.value.autoRead
            setOnCheckedChangeListener { _, on -> store.update { it.copy(autoRead = on) } }
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
Expected: `BUILD SUCCESSFUL`, barcha testlar PASS.

- [ ] **Step 5: Emulyatorda tekshirish**

`android-reinstall.sh` (scratchpad) → Accessibility xizmatini yoqish (M3 dagidek) → bosh ekranda "😀 tugmasi" va "avtomatik o'qish" switch'larini yoqish → "Demo chatni ochish" → maydonni bosish. Tekshiriladi (har biri skrinshot bilan):
1. Avtomatik o'qish: maydon bosilgach, 📖 bosilmasdan tarjima va javoblar chiqadi. Klaviaturani yopib, maydonni qayta bosish — `state.json` dagi `contextDate` o'zgarmaydi (qayta so'rov yo'q).
2. Tarjimani bosish → `ContextDetails` (Emma, xulosa, transkript) → "Klaviatura" → tugmalar qaytadi.
3. 😀 → emoji paneli → 😂 bosish → maydonda 😂 → ABC → tugmalar; qayta 😀 → "KO'P ISHLATILGAN" toifasida 😂.
4. Pufakcha: `adb shell input swipe <q> <q> 900` fonda, 400 ms dan keyin skrinshot — Q pufakchasi tugma ustida (yuqori qatorda panel ustiga chiqqan).
5. Pastki qatorda globus yo'q.

- [ ] **Step 6: Commit**

```bash
cd .. && git add android && git commit -m "Android: emoji paneli, tafsilotlar va avtomatik o'qish klaviaturaga ulandi, globus olib tashlandi

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

## Bajarish paytidagi o'zgarishlar (emulyator tekshiruvidan)

- **`LowerFrame`**: oddiy `FrameLayout` WRAP_CONTENT bo'lgani uchun MATCH_PARENT panel (tafsilotlar)
  klaviaturani butun ekranga cho'zib yubordi. `LowerFrame` balandlikni faqat tugmalardan oladi va panellarga
  aynan shu balandlikni beradi.
- **Pastki inset = max(navigationBars, tappableElement)**: klaviatura oynasi ichida tizim o'zining ⌄ (yashirish)
  va almashtirish tugmalarini 48 dp (144 px) chiziqda chizadi, `navigationBars` esa atigi 72 px. Emoji
  panelidagi ABC ⌄ ning bosish sohasiga tushib, klaviaturani yopardi (`HIDE_SOFT_INPUT_BY_BACK_KEY`).
- **Demo chat belgisi**: ilova paketi avtomatik o'qish ro'yxatidan olindi — aks holda `MainActivity`dagi
  sinov maydonida sozlamalar ekrani matni Gemini'ga ketardi. Demo chat maydoni
  `privateImeOptions = AutoRead.DEMO_CHAT_OPTION` bilan belgilanadi (`AutoReadTest` +1).
- Emulyator: avtomatik o'qish (~3–4 s), o'zgarmagan chatda qayta so'rov yo'q (jarayon qayta ishga tushganda
  ham), ✕ dan keyin qayta o'qiydi; sozlamalar ekranida o'qimaydi; tafsilotlar ↔ "Klaviatura"; emoji →
  maydon, "KO'P ISHLATILGAN"; q/g pufakchalari; globus yo'q. Testlar: 102.

## Keyingi reja

M5: to'liq sozlash ekrani (qadamlar ✓, Accessibility tushuntirishi, til, klaviatura, do'stlar, oxirgi kontekst), foydalanuvchi o'z Gemini kalitini kiritishi, ilova ikonkasi, README'ga Android bo'limi, imzolangan APK (GitHub Releases).
