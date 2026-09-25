# Android M2 — ma'lumot va AI qatlami: implementatsiya rejasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Holat (`SharedState`/`SharedStore`), do'stlar mantig'i, Gemini klienti (zaxira modelga parallel "hedging" bilan), promptlar, `Translator` va `ChatAnalysisService` — iOS mantig'ining Kotlin tengi, JVM testlari va haqiqiy Gemini bilan bitta smoke test.

**Architecture:** Hammasi Android UI'ga bog'liq emas: `data/` (modellar, holat, JSON fayl + `StateFlow`), `ai/` (`LlmClient` interfeysi, `GeminiClient` + `GeminiTransport`, `Prompts`, `Translator`, `ChatAnalysisService`). Transport interfeys orqali almashtiriladi — testlarda soxta, ilovada OkHttp. M3 bularni klaviatura va Accessibility xizmatiga ulaydi. Spec: `docs/superpowers/specs/2026-09-25-android-version-design.md` (2-bosqich).

**Tech Stack:** Kotlin 2.3.20, kotlinx-serialization-json 1.11.0, kotlinx-coroutines 1.11.0 (+ coroutines-test), OkHttp 4.12.0 (5.x compileSdk 37 talab qiladi), JUnit 4.13.2, kotlin-test.

## Global Constraints

- M1 cheklovlari amal qiladi (package, SDK, JDK/Gradle, commit qoidalari, `git commit -- <paths>`, branch `android`, push yo'q).
- Modellar: `gemini-3.5-flash-lite` asosiy, `gemini-3.5-flash` zaxira. Asosiy 5 s da javob bermasa — zaxiraga parallel so'rov, birinchi muvaffaqiyatli javob olinadi. 429/5xx, timeout, tarmoq xatosi va bo'sh javob — zaxiraga o'tadi; 4xx (429 dan tashqari) — o'tmaydi. Har urinishga 30 s (dastlab 20 s edi; jonli o'lchovda kichik so'rovlar ham 15 s gacha oldi).
- `thinkingLevel: minimal`, `responseMimeType: application/json`, JSON sxemalar va prompt matnlari iOS'dan (`Shared/Translator.swift`) aynan.
- Kontekst umri 15 daqiqa, tahlil timeout'i 60 s, xato ko'rinishi 120 s, do'stlar ro'yxati max 8 (iOS `SharedStore`).
- API kalit: `android/local.properties` → `gemini.apiKey` → `BuildConfig.GEMINI_API_KEY`. Kalit hech qachon commit qilinmaydi, chiqishga (log, terminal) yozilmaydi. `GeminiClient` kalitni `() -> String` orqali oladi — M5 da foydalanuvchi kiritgan kalitga almashtirish uchun (ommaviy APK ichiga kalit qo'yilmaydi).
- Test va kodda faqat to'qima ismlar/matnlar (Emma, Minji va h.k.).

## Fayllar

| Fayl | Vazifasi |
|---|---|
| `android/build.gradle.kts`, `android/app/build.gradle.kts` | serialization plugini, bog'liqliklar, `GEMINI_API_KEY` |
| `.../data/Models.kt` | `Suggestion`, `ChatLine`, `ChatAnalysis`, `QuickRead`, `ChatDetails` |
| `.../data/Friend.kt` | `Friend` + `isSamePerson`, `key`, `bestName` |
| `.../data/Languages.kt` | Tillar ro'yxati va bayroqlar |
| `.../data/SharedState.kt` | Holat va uning qoidalari (`freshContext`, `remember`, ...) |
| `.../data/SharedStore.kt` | JSON fayl + `StateFlow`, singleton |
| `.../ai/Llm.kt` | `Part`, `LlmClient` |
| `.../ai/Gemini.kt` | `GeminiException`, `GeminiTransport`, `GeminiClient` (hedging) |
| `.../ai/OkHttpGeminiTransport.kt` | Haqiqiy HTTP transport |
| `.../ai/Prompts.kt` | Promptlar va JSON sxemalar |
| `.../ai/Translator.kt` | `ChatInput`, `analyze` (parallel quick + details), `rewrite` |
| `.../ai/ChatAnalysisService.kt` | Chat → Gemini → `SharedStore` |
| `android/app/src/test/.../data/*Test.kt`, `.../ai/*Test.kt` | JVM testlar |

`...` = `android/app/src/main/java/com/ibrokhim/aikeyboard`; testlar `android/app/src/test/java/com/ibrokhim/aikeyboard`.

Barcha buyruqlar `android/` papkasida, `JAVA_HOME` M1 dagidek.

---

### Task 1: Bog'liqliklar, modellar, do'stlar va tillar

**Files:**
- Modify: `android/build.gradle.kts`, `android/app/build.gradle.kts`, `android/local.properties` (commit qilinmaydi)
- Create: `.../data/Models.kt`, `.../data/Friend.kt`, `.../data/Languages.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/data/FriendTest.kt`, `android/app/src/test/java/com/ibrokhim/aikeyboard/data/ModelsTest.kt`

**Interfaces:**
- Produces: `@Serializable data class Suggestion(text, uz)`, `ChatLine(from, text)`, `ChatAnalysis(partner, language, tone, lastIncomingUz, summaryUz, transcript, suggestions)` + `val lastIncoming` + `ChatAnalysis.of(quick: QuickRead?, details: ChatDetails?)`, `QuickRead(partner, language, tone, lastIncomingUz)`, `ChatDetails(summaryUz, transcript, suggestions)`; `Friend(name, language, tone, lastSeen: Long)` + `Friend.isSamePerson(a, b)`, `Friend.key(name)`, `Friend.bestName(names)`; `Languages.common`, `Languages.flag(language)`; `BuildConfig.GEMINI_API_KEY: String`.

- [ ] **Step 1: Gradle**

`android/build.gradle.kts`:
```kotlin
plugins {
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.3.20" apply false
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

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test:2.3.20")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
}
```

- [ ] **Step 2: Kalitni `local.properties`ga ko'chirish (ekranga chiqarmasdan)**

Run:
```bash
python3 - <<'PY'
import re, pathlib
key = re.search(r'"([^"]{20,})"', pathlib.Path("../Shared/Secrets.swift").read_text()).group(1)
p = pathlib.Path("local.properties")
lines = [l for l in p.read_text().splitlines() if not l.startswith("gemini.apiKey=")]
p.write_text("\n".join(lines + ["gemini.apiKey=" + key]) + "\n")
print("gemini.apiKey written, length", len(key))
PY
git check-ignore -q local.properties && echo "local.properties is ignored"
```
Expected: `gemini.apiKey written, length <n>` va `local.properties is ignored`.

- [ ] **Step 3: Failing tests**

`android/app/src/test/java/com/ibrokhim/aikeyboard/data/FriendTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FriendTest {
    @Test fun truncatedAndDecoratedNamesAreTheSamePerson() {
        assertTrue(Friend.isSamePerson("Christi...", "Christina"))
        assertTrue(Friend.isSamePerson("christina 🌸", "Christina"))
        assertTrue(Friend.isSamePerson("christina.lee", "Christina"))
        assertTrue(Friend.isSamePerson("Émma", "emma"))
    }

    @Test fun oneMisreadLetterIsToleratedFromSixLetters() {
        assertTrue(Friend.isSamePerson("Christima", "Christina"))
        assertTrue(Friend.isSamePerson("Gabriet", "Gabriel"))
        assertFalse(Friend.isSamePerson("Maria", "Marta"))
    }

    @Test fun shortOrEmptyNamesDoNotMatch() {
        assertFalse(Friend.isSamePerson("Ali", "Alisher"))
        assertFalse(Friend.isSamePerson("", "Emma"))
        assertFalse(Friend.isSamePerson("🌸", "🌸"))
    }

    @Test fun nonLatinNamesKeepTheirLetters() {
        assertEquals("민지", Friend.key("민지 🌷"))
        assertTrue(Friend.isSamePerson("Minji", "minji_"))
    }

    @Test fun bestNameKeepsTheMostCompleteSpelling() {
        assertEquals("Christina", Friend.bestName(listOf("Christi…", "Christina", "Christ")))
    }
}
```

`android/app/src/test/java/com/ibrokhim/aikeyboard/data/ModelsTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.data

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class ModelsTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test fun analysisReadsTheSnakeCaseJsonTheModelReturns() {
        val details = json.decodeFromString(
            ChatDetails.serializer(),
            """{"summary_uz":"Emma uchrashuv taklif qilyapti.","transcript":[{"from":"me","text":"hi"},""" +
                """{"from":"them","text":"u free?"},{"from":"them","text":"we could grab food"}],""" +
                """"suggestions":[{"text":"yes!","uz":"ha!"}]}""",
        )
        val quick = QuickRead("Emma...", "English", "casual", "Bo'shmisan?")
        val analysis = ChatAnalysis.of(quick, details)
        assertEquals("Emma", analysis.partner)
        assertEquals("u free? we could grab food", analysis.lastIncoming)
        assertEquals("yes!", analysis.suggestions.single().text)
    }

    @Test fun missingHalvesLeaveEmptyFields() {
        val analysis = ChatAnalysis.of(null, null)
        assertEquals("", analysis.partner)
        assertEquals(emptyList<Suggestion>(), analysis.suggestions)
    }

    @Test fun flags() {
        assertEquals("🇰🇷", Languages.flag("Korean"))
        assertEquals("🌐", Languages.flag("Klingon"))
    }
}
```

- [ ] **Step 4: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*FriendTest' --tests '*ModelsTest'`
Expected: FAIL — `Unresolved reference 'Friend'`.

- [ ] **Step 5: Implementation**

`android/app/src/main/java/com/ibrokhim/aikeyboard/data/Models.kt`:
```kotlin
package com.ibrokhim.aikeyboard.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Suggestion(
    val text: String,
    /** What `text` means in Uzbek, so the user knows exactly what they send. */
    val uz: String,
)

@Serializable
data class ChatLine(
    /** "me" or "them". */
    val from: String,
    val text: String,
)

/** What the model read from a DM. Built from two parallel calls; either half may be missing. */
@Serializable
data class ChatAnalysis(
    val partner: String = "",
    val language: String = "",
    val tone: String = "",
    @SerialName("last_incoming_uz") val lastIncomingUz: String = "",
    @SerialName("summary_uz") val summaryUz: String = "",
    val transcript: List<ChatLine> = emptyList(),
    val suggestions: List<Suggestion> = emptyList(),
) {
    /** The trailing run of messages from "them" — the thing the user is replying to. */
    val lastIncoming: String
        get() = transcript.takeLastWhile { it.from == "them" }.joinToString(" ") { it.text }

    companion object {
        fun of(quick: QuickRead?, details: ChatDetails?) = ChatAnalysis(
            // Instagram truncates long names in the chat header ("Christi...") and the model copies that.
            partner = quick?.partner.orEmpty().trim(' ', '.', '…'),
            language = quick?.language.orEmpty(),
            tone = quick?.tone.orEmpty(),
            lastIncomingUz = quick?.lastIncomingUz.orEmpty(),
            summaryUz = details?.summaryUz.orEmpty(),
            transcript = details?.transcript.orEmpty(),
            suggestions = details?.suggestions.orEmpty(),
        )
    }
}

/** Small, fast half: who, which language, what the last message means. Shown first. */
@Serializable
data class QuickRead(
    val partner: String,
    val language: String,
    val tone: String,
    @SerialName("last_incoming_uz") val lastIncomingUz: String,
)

/** Slower half: reply suggestions and the transcript ✨ uses as context. */
@Serializable
data class ChatDetails(
    @SerialName("summary_uz") val summaryUz: String,
    val transcript: List<ChatLine>,
    val suggestions: List<Suggestion>,
)
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/data/Friend.kt`:
```kotlin
package com.ibrokhim.aikeyboard.data

import java.text.Normalizer
import kotlinx.serialization.Serializable

@Serializable
data class Friend(
    val name: String,
    val language: String,
    val tone: String,
    /** Epoch milliseconds. */
    val lastSeen: Long,
) {
    companion object {
        /**
         * The model reads the name off each screen, so the same person comes back as "Christi..."
         * (truncated), "Christima" (misread), "christina 🌸" or "christina.lee". Compare letters and
         * digits only; a name that is the start of the other is the same person, and from 6 letters on
         * one misread, missing or extra letter is tolerated (not below: Maria ≠ Marta).
         */
        fun isSamePerson(a: String, b: String): Boolean {
            val x = key(a)
            val y = key(b)
            if (x.isEmpty() || y.isEmpty()) return false
            if (x == y) return true
            val (short, long) = if (x.length < y.length) x to y else y to x
            if (short.length < 4) return false
            if (long.startsWith(short)) return true
            return short.length >= 6 && prefixEditDistance(short, long) <= 1
        }

        /** Edit distance between `short` and the closest-length prefix of `long` (truncation is free). */
        private fun prefixEditDistance(short: String, long: String): Int {
            var row = IntArray(long.length + 1) { it }
            for (i in 1..short.length) {
                val next = IntArray(long.length + 1)
                next[0] = i
                for (j in 1..long.length) {
                    val cost = if (short[i - 1] == long[j - 1]) 0 else 1
                    next[j] = minOf(row[j] + 1, next[j - 1] + 1, row[j - 1] + cost)
                }
                row = next
            }
            val n = short.length
            return (maxOf(0, n - 1)..minOf(long.length, n + 1)).minOf { row[it] }
        }

        /** Lowercase letters and digits with accents stripped; Hangul and other scripts are kept. */
        fun key(name: String): String {
            val decomposed = Normalizer.normalize(name.lowercase(), Normalizer.Form.NFD)
            return Normalizer.normalize(decomposed.filter { it.isLetterOrDigit() }, Normalizer.Form.NFC)
        }

        /** Of several spellings, keep the most complete one. */
        fun bestName(names: List<String>): String =
            names.map { it.trim(' ', '.', '…') }.maxByOrNull { key(it).length }.orEmpty()
    }
}
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/data/Languages.kt`:
```kotlin
package com.ibrokhim.aikeyboard.data

object Languages {
    val common = listOf(
        "English", "Korean", "Russian", "Turkish", "Japanese", "Chinese",
        "Arabic", "German", "Spanish", "French",
    )

    fun flag(language: String): String = when (language.lowercase()) {
        "english" -> "🇬🇧"
        "korean" -> "🇰🇷"
        "russian" -> "🇷🇺"
        "turkish" -> "🇹🇷"
        "japanese" -> "🇯🇵"
        "chinese" -> "🇨🇳"
        "arabic" -> "🇸🇦"
        "german" -> "🇩🇪"
        "spanish" -> "🇪🇸"
        "french" -> "🇫🇷"
        "italian" -> "🇮🇹"
        "portuguese" -> "🇵🇹"
        "hindi" -> "🇮🇳"
        "indonesian" -> "🇮🇩"
        "kazakh" -> "🇰🇿"
        "uzbek" -> "🇺🇿"
        else -> "🌐"
    }
}
```

- [ ] **Step 6: Run — passes**

Run: `./gradlew :app:testDebugUnitTest --tests '*FriendTest' --tests '*ModelsTest'`
Expected: `BUILD SUCCESSFUL`, 8 test PASS.

- [ ] **Step 7: Commit**

```bash
cd .. && git add android && git commit -m "Android: modellar, do'stlar mantig'i va tillar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 2: `SharedState` va `SharedStore`

**Files:**
- Create: `.../data/SharedState.kt`, `.../data/SharedStore.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/data/SharedStateTest.kt`, `android/app/src/test/java/com/ibrokhim/aikeyboard/data/SharedStoreTest.kt`

**Interfaces:**
- Consumes: `ChatAnalysis`, `Friend` (Task 1).
- Produces:
  ```kotlin
  data class SharedState(context: ChatAnalysis?, contextDate: Long?, analyzingSince: Long?, lastError: String?,
      lastErrorDate: Long?, targetLanguage: String?, activeFriend: String?, friends: List<Friend>,
      emojiKey: Boolean, autoRead: Boolean, lastReadHash: String?) {
      fun freshContext(now: Long): ChatAnalysis?
      fun isAnalyzing(now: Long): Boolean
      fun recentError(now: Long): String?
      fun language(now: Long): String
      fun activeFriendProfile(now: Long): Friend?
      fun remember(analysis: ChatAnalysis, now: Long): SharedState
      fun mergeDuplicateFriends(): SharedState
  }
  class SharedStore(file: File) {
      val state: StateFlow<SharedState>; val value: SharedState
      fun update(change: (SharedState) -> SharedState): SharedState
      companion object { val json: Json; fun get(context: Context): SharedStore }
  }
  ```

- [ ] **Step 1: Failing tests**

`android/app/src/test/java/com/ibrokhim/aikeyboard/data/SharedStateTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class SharedStateTest {
    private val now = 1_000_000_000L
    private val emma = ChatAnalysis(partner = "Emma", language = "English", tone = "casual")

    @Test fun contextExpiresAfterFifteenMinutes() {
        val state = SharedState(context = emma, contextDate = now)
        assertEquals(emma, state.freshContext(now + 14 * 60_000))
        assertNull(state.freshContext(now + 15 * 60_000))
    }

    @Test fun languageFollowsFreshContextThenTargetThenEnglish() {
        assertEquals("English", SharedState().language(now))
        assertEquals("Korean", SharedState(targetLanguage = "Korean").language(now))
        val korean = ChatAnalysis(partner = "Minji", language = "Korean")
        assertEquals("Korean", SharedState(context = korean, contextDate = now, targetLanguage = "Turkish").language(now))
    }

    @Test fun rememberPutsTheFriendFirstAndMakesThemTheTarget() {
        val older = Friend("Minji", "Korean", "friendly", now - 1)
        val state = SharedState(friends = listOf(older)).remember(emma, now)
        assertEquals(listOf("Emma", "Minji"), state.friends.map { it.name })
        assertEquals("Emma", state.activeFriend)
        assertEquals("English", state.targetLanguage)
    }

    @Test fun rememberMergesAMisreadNameIntoTheKnownFriend() {
        val known = Friend("Christina", "English", "casual", now - 1)
        val misread = ChatAnalysis(partner = "Christima", language = "English", tone = "slang")
        val state = SharedState(friends = listOf(known)).remember(misread, now)
        assertEquals(1, state.friends.size)
        assertEquals("Christima", state.friends[0].name) // same length: first (newest) spelling wins
        assertEquals("slang", state.friends[0].tone)
    }

    @Test fun rememberKeepsAtMostEightFriends() {
        val many = (1..8).map { Friend("Friend number $it", "English", "", now - it) }
        val state = SharedState(friends = many).remember(emma, now)
        assertEquals(8, state.friends.size)
        assertEquals("Emma", state.friends.first().name)
    }

    @Test fun failedQuickHalfChangesNothing() {
        val state = SharedState(targetLanguage = "Korean")
        assertSame(state, state.remember(ChatAnalysis(), now))
    }

    @Test fun unknownPartnerClearsTheActiveFriend() {
        val state = SharedState(activeFriend = "Emma").remember(ChatAnalysis(language = "Turkish"), now)
        assertNull(state.activeFriend)
        assertEquals("Turkish", state.targetLanguage)
    }

    @Test fun activeFriendProfileOnlyWithoutFreshContext() {
        val friend = Friend("Emma", "English", "casual", now)
        val state = SharedState(activeFriend = "Emma", friends = listOf(friend))
        assertEquals(friend, state.activeFriendProfile(now))
        assertNull(state.copy(context = emma, contextDate = now).activeFriendProfile(now))
    }

    @Test fun mergeDuplicateFriendsKeepsNewestToneAndFullestName() {
        val state = SharedState(
            activeFriend = "Gabriet",
            friends = listOf(Friend("Gabriet", "English", "new", now), Friend("Gabriel M", "English", "old", now - 1)),
        ).mergeDuplicateFriends()
        assertEquals(listOf("Gabriel M"), state.friends.map { it.name })
        assertEquals("new", state.friends[0].tone)
        assertEquals("Gabriel M", state.activeFriend)
    }

    @Test fun errorsAndAnalysisExpire() {
        val state = SharedState(analyzingSince = now, lastError = "x", lastErrorDate = now)
        assertEquals(true, state.isAnalyzing(now + 59_000))
        assertEquals(false, state.isAnalyzing(now + 60_000))
        assertEquals("x", state.recentError(now + 119_000))
        assertNull(state.recentError(now + 120_000))
    }
}
```

`android/app/src/test/java/com/ibrokhim/aikeyboard/data/SharedStoreTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.data

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SharedStoreTest {
    @get:Rule val folder = TemporaryFolder()

    private fun file() = File(folder.root, "state.json")

    @Test fun updatesArePersistedAndPublished() {
        val store = SharedStore(file())
        store.update { it.copy(targetLanguage = "Korean", friends = listOf(Friend("Minji", "Korean", "friendly", 1))) }
        assertEquals("Korean", store.state.value.targetLanguage)
        val reopened = SharedStore(file())
        assertEquals("Korean", reopened.value.targetLanguage)
        assertEquals("Minji", reopened.value.friends.single().name)
    }

    @Test fun contextRoundTripsWithSnakeCaseKeys() {
        val store = SharedStore(file())
        val analysis = ChatAnalysis(partner = "Emma", lastIncomingUz = "Salom", summaryUz = "Xulosa")
        store.update { it.copy(context = analysis, contextDate = 5) }
        val text = file().readText()
        assertEquals(true, text.contains("\"last_incoming_uz\":\"Salom\""))
        assertEquals(analysis, SharedStore(file()).value.context)
    }

    @Test fun corruptFileStartsFresh() {
        file().writeText("{not json")
        assertEquals(SharedState(), SharedStore(file()).value)
    }

    @Test fun unchangedStateIsNotWritten() {
        val store = SharedStore(file())
        store.update { it }
        assertFalse(file().exists())
    }
}
```

- [ ] **Step 2: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*SharedStateTest' --tests '*SharedStoreTest'`
Expected: FAIL — `Unresolved reference 'SharedState'`.

- [ ] **Step 3: Implementation**

`android/app/src/main/java/com/ibrokhim/aikeyboard/data/SharedState.kt`:
```kotlin
package com.ibrokhim.aikeyboard.data

import kotlinx.serialization.Serializable

/** Everything the keyboard, the chat reader and the app share. Times are epoch milliseconds. */
@Serializable
data class SharedState(
    val context: ChatAnalysis? = null,
    val contextDate: Long? = null,
    val analyzingSince: Long? = null,
    val lastError: String? = null,
    val lastErrorDate: Long? = null,
    /** ✨ target when there is no fresh context. Follows the last analysed chat and the keyboard's chips. */
    val targetLanguage: String? = null,
    /** Friend picked in the keyboard (or the last analysed one) — gives ✨ their tone without a chat read. */
    val activeFriend: String? = null,
    /** People seen in chats, most recent first. */
    val friends: List<Friend> = emptyList(),
    /** App setting: the bottom-row КИР/LAT key becomes an emoji key. */
    val emojiKey: Boolean = false,
    /** App setting: read the chat when the keyboard opens in a messenger. */
    val autoRead: Boolean = false,
    /** Hash of the last auto-read chat lines, so an unchanged chat is not sent again. */
    val lastReadHash: String? = null,
) {
    /** Suggestions from an old chat read are worse than none — the chat has moved on. */
    fun freshContext(now: Long): ChatAnalysis? {
        val context = context ?: return null
        val at = contextDate ?: return null
        return if (now - at < CONTEXT_LIFETIME_MS) context else null
    }

    fun isAnalyzing(now: Long): Boolean = analyzingSince?.let { now - it < ANALYSIS_TIMEOUT_MS } ?: false

    fun recentError(now: Long): String? {
        val at = lastErrorDate ?: return null
        return if (now - at < ERROR_LIFETIME_MS) lastError else null
    }

    fun language(now: Long): String =
        freshContext(now)?.language?.takeIf { it.isNotEmpty() } ?: targetLanguage ?: "English"

    /** The friend whose tone ✨ uses when there is no fresh context. */
    fun activeFriendProfile(now: Long): Friend? {
        if (freshContext(now) != null) return null
        val name = activeFriend ?: return null
        return friends.firstOrNull { it.name == name }
    }

    /** The analysed partner becomes the newest friend and the ✨ target. */
    fun remember(analysis: ChatAnalysis, now: Long): SharedState {
        // Empty when the quick half failed — keep what we knew.
        if (analysis.language.isEmpty()) return this
        if (analysis.partner.isEmpty()) return copy(targetLanguage = analysis.language, activeFriend = null)
        val same = friends.filter { Friend.isSamePerson(it.name, analysis.partner) }
        val name = Friend.bestName(listOf(analysis.partner) + same.map { it.name })
        val others = friends.filterNot { Friend.isSamePerson(it.name, analysis.partner) }
        val list = (listOf(Friend(name, analysis.language, analysis.tone, now)) + others).take(MAX_FRIENDS)
        return copy(targetLanguage = analysis.language, friends = list, activeFriend = name)
    }

    /**
     * Merges entries `Friend.isSamePerson` considers one person. The list is most-recent-first, so the
     * first entry keeps its language and tone; the name becomes the most complete one.
     */
    fun mergeDuplicateFriends(): SharedState {
        val merged = mutableListOf<Friend>()
        for (friend in friends) {
            val index = merged.indexOfFirst { Friend.isSamePerson(it.name, friend.name) }
            if (index >= 0) {
                merged[index] = merged[index].copy(name = Friend.bestName(listOf(merged[index].name, friend.name)))
            } else {
                merged.add(friend)
            }
        }
        if (merged == friends) return this
        val active = activeFriend?.let { name -> merged.firstOrNull { Friend.isSamePerson(it.name, name) }?.name }
        return copy(friends = merged, activeFriend = active ?: activeFriend)
    }

    companion object {
        const val CONTEXT_LIFETIME_MS = 15 * 60 * 1000L
        const val ANALYSIS_TIMEOUT_MS = 60 * 1000L
        const val ERROR_LIFETIME_MS = 120 * 1000L
        const val MAX_FRIENDS = 8
    }
}
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/data/SharedStore.kt`:
```kotlin
package com.ibrokhim.aikeyboard.data

import android.content.Context
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.Json

/**
 * One JSON file in app storage, mirrored in a StateFlow. The keyboard, the chat reader and the app run
 * in one process, so collectors see every update at once (iOS needed an App Group and Darwin notifications).
 */
class SharedStore(private val file: File) {
    private val lock = Any()
    private val flow = MutableStateFlow(read())

    val state: StateFlow<SharedState> = flow
    val value: SharedState get() = flow.value

    fun update(change: (SharedState) -> SharedState): SharedState = synchronized(lock) {
        val next = change(flow.value)
        if (next != flow.value) {
            write(next)
            flow.value = next
        }
        next
    }

    private fun read(): SharedState = try {
        if (file.exists()) json.decodeFromString(SharedState.serializer(), file.readText()) else SharedState()
    } catch (e: Exception) {
        SharedState() // a corrupt file must not keep the keyboard from starting
    }

    private fun write(state: SharedState) {
        val dir = file.absoluteFile.parentFile
        dir?.mkdirs()
        val tmp = File(dir, file.name + ".tmp")
        tmp.writeText(json.encodeToString(SharedState.serializer(), state))
        if (!tmp.renameTo(file)) {
            file.delete()
            tmp.renameTo(file)
        }
    }

    companion object {
        val json = Json {
            ignoreUnknownKeys = true
            explicitNulls = false
        }

        @Volatile private var instance: SharedStore? = null

        fun get(context: Context): SharedStore = instance ?: synchronized(this) {
            instance ?: SharedStore(File(context.applicationContext.filesDir, "state.json")).also { instance = it }
        }
    }
}
```

- [ ] **Step 4: Run — passes**

Run: `./gradlew :app:testDebugUnitTest --tests '*SharedStateTest' --tests '*SharedStoreTest'`
Expected: `BUILD SUCCESSFUL`, 14 test PASS.

- [ ] **Step 5: Commit**

```bash
cd .. && git add android && git commit -m "Android: SharedState va SharedStore (JSON + StateFlow)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 3: Gemini klienti (hedging, timeout, zaxira)

**Files:**
- Create: `.../ai/Llm.kt`, `.../ai/Gemini.kt`, `.../ai/OkHttpGeminiTransport.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/ai/GeminiClientTest.kt`

**Interfaces:**
- Produces:
  ```kotlin
  sealed interface Part { data class Text(val text: String); class Jpeg(val bytes: ByteArray) }
  interface LlmClient { suspend fun generate(system: String, parts: List<Part>, schema: JsonObject): String }
  sealed class GeminiException : Exception { MissingKey; Http(code, detail); Empty; Timeout; Network(cause) }
  data class HttpResponse(val code: Int, val body: String)
  interface GeminiTransport { suspend fun post(model: String, apiKey: String, body: String): HttpResponse }
  class GeminiClient(transport, apiKey: () -> String, models = GeminiClient.MODELS, hedgeAfterMs = 5_000, attemptTimeoutMs = 30_000) : LlmClient
  class OkHttpGeminiTransport(client: OkHttpClient = OkHttpGeminiTransport.defaultClient) : GeminiTransport
  ```

- [ ] **Step 1: Failing test**

`android/app/src/test/java/com/ibrokhim/aikeyboard/ai/GeminiClientTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ai

import kotlin.test.assertFailsWith
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

class GeminiClientTest {
    private class FakeTransport(private val answer: suspend (model: String) -> HttpResponse) : GeminiTransport {
        val calls = mutableListOf<String>()
        var lastBody = ""
        override suspend fun post(model: String, apiKey: String, body: String): HttpResponse {
            calls.add(model)
            lastBody = body
            return answer(model)
        }
    }

    private fun ok(text: String) =
        HttpResponse(200, """{"candidates":[{"content":{"parts":[{"text":${JsonPrimitive(text)}}]}}]}""")

    private fun error(code: Int, message: String) = HttpResponse(code, """{"error":{"message":"$message"}}""")

    private val lite = GeminiClient.MODELS[0]
    private val flash = GeminiClient.MODELS[1]
    private val schema = JsonObject(emptyMap())

    private fun client(transport: GeminiTransport, key: String = "k") = GeminiClient(transport, { key })

    @Test fun primaryAnswers() = runTest {
        val transport = FakeTransport { ok("{\"a\":1}") }
        assertEquals("{\"a\":1}", client(transport).generate("sys", listOf(Part.Text("hi")), schema))
        assertEquals(listOf(lite), transport.calls)
    }

    @Test fun overloadedPrimaryFallsBackAtOnce() = runTest {
        val transport = FakeTransport { model -> if (model == lite) error(503, "overloaded") else ok("fallback") }
        assertEquals("fallback", client(transport).generate("sys", emptyList(), schema))
        assertEquals(listOf(lite, flash), transport.calls)
        assertEquals(0L, testScheduler.currentTime)
    }

    @Test fun slowPrimaryIsHedgedAfterFiveSeconds() = runTest {
        val transport = FakeTransport { model ->
            if (model == lite) {
                delay(30_000)
                ok("slow")
            } else {
                ok("fast")
            }
        }
        assertEquals("fast", client(transport).generate("sys", emptyList(), schema))
        assertEquals(5_000L, testScheduler.currentTime)
    }

    @Test fun clientErrorIsNotRetried() = runTest {
        val transport = FakeTransport { error(400, "API key not valid") }
        val e = assertFailsWith<GeminiException.Http> { client(transport).generate("sys", emptyList(), schema) }
        assertEquals(400, e.code)
        assertEquals(listOf(lite), transport.calls)
    }

    @Test fun bothFailing() = runTest {
        val transport = FakeTransport { error(503, "overloaded") }
        assertFailsWith<GeminiException.Http> { client(transport).generate("sys", emptyList(), schema) }
    }

    @Test fun hangingModelsTimeOut() = runTest {
        val transport = FakeTransport { awaitCancellation() }
        assertFailsWith<GeminiException.Timeout> { client(transport).generate("sys", emptyList(), schema) }
        assertEquals(35_000L, testScheduler.currentTime) // hedge at 5 s, fallback's own 30 s
    }

    @Test fun missingKeyFailsWithoutACall() = runTest {
        val transport = FakeTransport { ok("x") }
        assertFailsWith<GeminiException.MissingKey> { client(transport, key = "").generate("sys", emptyList(), schema) }
        assertEquals(emptyList<String>(), transport.calls)
    }

    @Test fun emptyCandidatesFallBack() = runTest {
        val transport = FakeTransport { model -> if (model == lite) HttpResponse(200, "{\"candidates\":[]}") else ok("x") }
        assertEquals("x", client(transport).generate("sys", emptyList(), schema))
    }

    @Test fun requestBodyCarriesPromptImageAndConfig() = runTest {
        val transport = FakeTransport { ok("{}") }
        client(transport).generate("system text", listOf(Part.Text("Known friends: Emma"), Part.Jpeg(byteArrayOf(1, 2, 3))), schema)
        val body = Json.parseToJsonElement(transport.lastBody).jsonObject
        val system = body["systemInstruction"]!!.jsonObject["parts"]!!.jsonArray[0].jsonObject["text"]!!.jsonPrimitive.content
        assertEquals("system text", system)
        val parts = body["contents"]!!.jsonArray[0].jsonObject["parts"]!!.jsonArray
        assertEquals("Known friends: Emma", parts[0].jsonObject["text"]!!.jsonPrimitive.content)
        assertEquals("AQID", parts[1].jsonObject["inlineData"]!!.jsonObject["data"]!!.jsonPrimitive.content)
        val config = body["generationConfig"]!!.jsonObject
        assertEquals("application/json", config["responseMimeType"]!!.jsonPrimitive.content)
        assertEquals("minimal", config["thinkingConfig"]!!.jsonObject["thinkingLevel"]!!.jsonPrimitive.content)
    }
}
```

- [ ] **Step 2: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*GeminiClientTest'`
Expected: FAIL — `Unresolved reference 'GeminiTransport'`.

- [ ] **Step 3: Implementation**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ai/Llm.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ai

import kotlinx.serialization.json.JsonObject

sealed interface Part {
    data class Text(val text: String) : Part
    class Jpeg(val bytes: ByteArray) : Part
}

/** Turns a system prompt, the user's parts and a JSON schema into the model's JSON text. */
interface LlmClient {
    suspend fun generate(system: String, parts: List<Part>, schema: JsonObject): String
}

/** Like runCatching, but cancellation still propagates. */
internal inline fun <T> runCatchingNonCancel(block: () -> T): Result<T> = try {
    Result.success(block())
} catch (e: kotlinx.coroutines.CancellationException) {
    throw e
} catch (e: Exception) {
    Result.failure(e)
}
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/ai/Gemini.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ai

import java.io.IOException
import java.util.Base64
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

sealed class GeminiException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class MissingKey : GeminiException("Gemini API kaliti yo'q")
    class Http(val code: Int, detail: String) : GeminiException("Gemini $code: $detail")
    class Empty : GeminiException("Gemini bo'sh javob qaytardi")
    class Timeout : GeminiException("Gemini javob bermadi")
    class Network(cause: IOException) : GeminiException("Internet bilan muammo", cause)

    /** Worth asking the other model: overload, server trouble, silence, a dropped connection. */
    val retriable: Boolean
        get() = when (this) {
            is Http -> code == 429 || code >= 500
            is Empty, is Timeout, is Network -> true
            is MissingKey -> false
        }
}

data class HttpResponse(val code: Int, val body: String)

interface GeminiTransport {
    /** POSTs `body` to the model's generateContent endpoint; throws IOException on network failure. */
    suspend fun post(model: String, apiKey: String, body: String): HttpResponse
}

/**
 * Gemini with a hedge: the lite model answers in ~2 s but now and then takes 20–50 s, so if it has not
 * answered after [hedgeAfterMs] the bigger model is asked in parallel and the first answer wins.
 * A failure worth retrying falls back at once. (The iOS client waits out a 30 s timeout instead.)
 */
class GeminiClient(
    private val transport: GeminiTransport,
    private val apiKey: () -> String,
    private val models: List<String> = MODELS,
    private val hedgeAfterMs: Long = 5_000,
    private val attemptTimeoutMs: Long = 30_000,
) : LlmClient {

    override suspend fun generate(system: String, parts: List<Part>, schema: JsonObject): String {
        val key = apiKey()
        if (key.isBlank()) throw GeminiException.MissingKey()
        val body = requestBody(system, parts, schema)
        return coroutineScope {
            val primary = async { attempt(models[0], key, body) }
            val early = withTimeoutOrNull(hedgeAfterMs) { primary.await() }
            val error = early?.exceptionOrNull()
            when {
                early == null -> race(primary, async { attempt(models[1], key, body) })
                error == null -> early.getOrThrow()
                error is GeminiException && error.retriable -> attempt(models[1], key, body).getOrThrow()
                else -> throw error
            }
        }
    }

    private suspend fun attempt(model: String, key: String, body: String): Result<String> {
        val response = try {
            withTimeoutOrNull(attemptTimeoutMs) { transport.post(model, key, body) }
                ?: return Result.failure(GeminiException.Timeout())
        } catch (e: IOException) {
            return Result.failure(GeminiException.Network(e))
        }
        return try {
            Result.success(parseResponse(response))
        } catch (e: GeminiException) {
            Result.failure(e)
        }
    }

    private suspend fun race(a: Deferred<Result<String>>, b: Deferred<Result<String>>): String {
        val (first, other) = select<Pair<Result<String>, Deferred<Result<String>>>> {
            a.onAwait { it to b }
            b.onAwait { it to a }
        }
        if (first.isSuccess) {
            other.cancel()
            return first.getOrThrow()
        }
        return other.await().getOrThrow()
    }

    internal fun requestBody(system: String, parts: List<Part>, schema: JsonObject): String = buildJsonObject {
        putJsonObject("systemInstruction") {
            putJsonArray("parts") { addJsonObject { put("text", system) } }
        }
        putJsonArray("contents") {
            addJsonObject {
                put("role", "user")
                putJsonArray("parts") {
                    for (part in parts) {
                        when (part) {
                            is Part.Text -> addJsonObject { put("text", part.text) }
                            is Part.Jpeg -> addJsonObject {
                                putJsonObject("inlineData") {
                                    put("mimeType", "image/jpeg")
                                    put("data", Base64.getEncoder().encodeToString(part.bytes))
                                }
                            }
                        }
                    }
                }
            }
        }
        putJsonObject("generationConfig") {
            put("responseMimeType", "application/json")
            put("responseSchema", schema)
            putJsonObject("thinkingConfig") { put("thinkingLevel", "minimal") }
        }
    }.toString()

    internal fun parseResponse(response: HttpResponse): String {
        val root = try {
            Json.parseToJsonElement(response.body) as? JsonObject
        } catch (e: Exception) {
            null
        }
        if (response.code != 200) {
            val message = ((root?.get("error") as? JsonObject)?.get("message") as? JsonPrimitive)?.contentOrNull
            throw GeminiException.Http(response.code, message ?: "HTTP ${response.code}")
        }
        val candidate = (root?.get("candidates") as? JsonArray)?.firstOrNull() as? JsonObject
        val parts = ((candidate?.get("content") as? JsonObject)?.get("parts") as? JsonArray).orEmpty()
        val text = parts.firstNotNullOfOrNull { ((it as? JsonObject)?.get("text") as? JsonPrimitive)?.contentOrNull }
        return text ?: throw GeminiException.Empty()
    }

    companion object {
        val MODELS = listOf("gemini-3.5-flash-lite", "gemini-3.5-flash")
    }
}
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/ai/OkHttpGeminiTransport.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ai

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

class OkHttpGeminiTransport(private val client: OkHttpClient = defaultClient) : GeminiTransport {
    override suspend fun post(model: String, apiKey: String, body: String): HttpResponse {
        val request = Request.Builder()
            .url("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent")
            .header("x-goog-api-key", apiKey)
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()
        val call = client.newCall(request)
        return suspendCancellableCoroutine { continuation ->
            // The hedge cancels the losing request; drop its socket too.
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    val result = response.use { HttpResponse(it.code, it.body?.string().orEmpty()) }
                    if (continuation.isActive) continuation.resume(result)
                }
            })
        }
    }

    companion object {
        /**
         * OkHttp's default 10 s read timeout would cut off a slow-but-fine answer before GeminiClient's own
         * hedge and 20 s attempt timeout decide; those own the timing, OkHttp only guards against hangs.
         */
        val defaultClient: OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()
    }
}
```

- [ ] **Step 4: Run — passes**

Run: `./gradlew :app:testDebugUnitTest --tests '*GeminiClientTest'`
Expected: `BUILD SUCCESSFUL`, 9 test PASS.

- [ ] **Step 5: Commit**

```bash
cd .. && git add android && git commit -m "Android: Gemini klienti — zaxira modelga parallel so'rov va timeout

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 4: Promptlar va `Translator`

**Files:**
- Create: `.../ai/Prompts.kt`, `.../ai/Translator.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/ai/TranslatorTest.kt`

**Interfaces:**
- Consumes: `LlmClient`, `Part`, `runCatchingNonCancel` (Task 3); `ChatAnalysis`, `QuickRead`, `ChatDetails`, `Suggestion`, `Friend`, `SharedStore.json` (Tasks 1–2).
- Produces:
  ```kotlin
  object Prompts { val screenshotBasics: String; val transcriptBasics: String; fun quick(basics: String): String;
      fun details(basics: String): String; val rewriteSystem: String;
      fun rewriteInput(draft, context: ChatAnalysis?, friend: Friend?, language: String): String;
      val quickSchema: JsonObject; val detailsSchema: JsonObject; val rewriteSchema: JsonObject }
  sealed interface ChatInput { data class Transcript(val lines: List<String>); class Screenshot(val jpeg: ByteArray) }
  data class AnalyzeResult(val analysis: ChatAnalysis, val partialError: Throwable?)
  class Translator(llm: LlmClient) {
      suspend fun analyze(input: ChatInput, knownFriends: List<String>, onQuickRead: (QuickRead) -> Unit): AnalyzeResult
      suspend fun rewrite(draft: String, context: ChatAnalysis?, friend: Friend?, language: String): List<Suggestion>
  }
  ```

- [ ] **Step 1: Failing test**

`android/app/src/test/java/com/ibrokhim/aikeyboard/ai/TranslatorTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.ChatLine
import com.ibrokhim.aikeyboard.data.Friend
import kotlin.test.assertFailsWith
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TranslatorTest {
    private class FakeLlm(private val answer: (system: String) -> String) : LlmClient {
        val calls = mutableListOf<Pair<String, List<Part>>>()
        override suspend fun generate(system: String, parts: List<Part>, schema: JsonObject): String {
            calls.add(system to parts)
            return answer(system)
        }
    }

    private val quick = """{"partner":"Emma","language":"English","tone":"casual","last_incoming_uz":"Bo'shmisan?"}"""
    private val details = """{"summary_uz":"Uchrashuv.","transcript":[{"from":"them","text":"u free?"}],""" +
        """"suggestions":[{"text":"yes!","uz":"ha!"}]}"""

    private fun isQuick(system: String) = system.contains("- partner:")

    private val transcript = ChatInput.Transcript(listOf("[TOP] Emma", "[L] u free?", "[R] maybe"))

    @Test fun analyzeMergesBothHalvesAndShowsTheQuickOneFirst() = runTest {
        val llm = FakeLlm { if (isQuick(it)) quick else details }
        val seen = mutableListOf<String>()
        val result = Translator(llm).analyze(transcript, listOf("Emma")) { seen.add(it.partner) }
        assertEquals(listOf("Emma"), seen)
        assertEquals("Emma", result.analysis.partner)
        assertEquals("yes!", result.analysis.suggestions.single().text)
        assertNull(result.partialError)
    }

    @Test fun transcriptUsesTheTextPromptAndKnownFriendsGoFirst() = runTest {
        val llm = FakeLlm { if (isQuick(it)) quick else details }
        Translator(llm).analyze(transcript, listOf("Emma", "Minji")) {}
        val (system, parts) = llm.calls.first { isQuick(it.first) }
        assertTrue(system.contains("[R]"))
        assertEquals(Part.Text("Known friends: Emma, Minji"), parts[0])
        assertEquals(Part.Text("[TOP] Emma\n[L] u free?\n[R] maybe"), parts[1])
    }

    @Test fun screenshotUsesTheImagePrompt() = runTest {
        val llm = FakeLlm { if (isQuick(it)) quick else details }
        Translator(llm).analyze(ChatInput.Screenshot(byteArrayOf(1)), emptyList()) {}
        val (system, parts) = llm.calls.first()
        assertTrue(system.contains("screenshot"))
        assertTrue(parts.single() is Part.Jpeg)
    }

    @Test fun failedDetailsHalfIsPartial() = runTest {
        val llm = FakeLlm { if (isQuick(it)) quick else throw GeminiException.Timeout() }
        val result = Translator(llm).analyze(transcript, emptyList()) {}
        assertEquals("Emma", result.analysis.partner)
        assertEquals(0, result.analysis.suggestions.size)
        assertNotNull(result.partialError)
    }

    @Test fun bothHalvesFailing() = runTest {
        val llm = FakeLlm { throw GeminiException.Timeout() }
        assertFailsWith<GeminiException.Timeout> { Translator(llm).analyze(transcript, emptyList()) {} }
    }

    @Test fun rewriteReturnsTheVariants() = runTest {
        val llm = FakeLlm { """{"variants":[{"text":"we're getting plov on saturday","uz":"Shanba kuni osh yeymiz"}]}""" }
        val variants = Translator(llm).rewrite("shanba kuni plov yeymiz", null, null, "English")
        assertEquals("we're getting plov on saturday", variants.single().text)
    }

    @Test fun rewriteInputCarriesTheConversation() {
        val context = ChatAnalysis(
            partner = "Emma", tone = "casual",
            transcript = listOf(ChatLine("them", "u free?"), ChatLine("me", "yes")),
        )
        val input = Prompts.rewriteInput("salom", context, null, "English")
        assertEquals(
            "Target language: English\nConversation tone: casual\nPartner: Emma\nRecent messages:\n" +
                "them: u free?\nme: yes\n\nDraft:\nsalom",
            input,
        )
        val friendOnly = Prompts.rewriteInput("salom", null, Friend("Minji", "Korean", "friendly", 0), "Korean")
        assertTrue(friendOnly.contains("Partner: Minji\nConversation tone: friendly\nNo recent messages available."))
    }
}
```

- [ ] **Step 2: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*TranslatorTest'`
Expected: FAIL — `Unresolved reference 'ChatInput'`.

- [ ] **Step 3: Implementation**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ai/Prompts.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.Friend
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/** Prompt texts and schemas from the iOS `Translator.swift`, plus a variant for chat text read on screen. */
object Prompts {
    val screenshotBasics = """
        You help an Uzbek speaker chat with foreign friends in social media DMs.
        You receive a phone screenshot of a DM conversation (Instagram, Telegram, WhatsApp, etc.).
        Messages on the RIGHT side (usually colored bubbles) are from the user ("me"); messages on the LEFT are from the other person ("them").
        Ignore the status bar, keyboard, app UI, and any system banners (e.g. a "Shortcuts" notification).
        Uzbek must use Latin script with ' for oʻ/gʻ.

        Return JSON:
    """.trimIndent()

    /** Android reads the chat's text instead of a screenshot; the lines carry their on-screen position. */
    val transcriptBasics = """
        You help an Uzbek speaker chat with foreign friends in social media DMs.
        You receive the visible text of a DM conversation screen (Instagram, Telegram, WhatsApp, etc.), one line per text element, top to bottom.
        Each line starts with a tag: [TOP] = the screen header (usually the other person's name or handle), [R] = right side, sent by the user ("me"), [L] = left side, sent by the other person ("them").
        The lines also contain timestamps, "Seen"/"Active now" statuses, reactions, buttons and other UI labels: ignore them.
        Uzbek must use Latin script with ' for oʻ/gʻ.

        Return JSON:
    """.trimIndent()

    private val quickFields = """
        - partner: the other person's visible name or handle, or "" if not visible. If it is cut off with "..." return only the visible part, without the dots. If "Known friends" are listed and this is clearly one of them (the same name, even if cut off or slightly misread), return that known name exactly as written.
        - language: the language the other person writes in, in English (e.g. "English", "Korean").
        - tone: 2-5 words describing the conversation register (e.g. "casual, slang, emojis").
        - last_incoming_uz: natural, conversational Uzbek meaning of the latest message(s) from "them". Translate intent, not words. If there is slang or an idiom, add a short explanation in parentheses.
    """.trimIndent()

    private val detailsFields = """
        - summary_uz: 1 short sentence in Uzbek explaining what is going on right now.
        - transcript: the last up to 6 messages in order, verbatim, each {from: "me"|"them", text}.
        - suggestions: exactly 3 replies the user could send next, written in the conversation language, matching the tone (length, casing, emoji use). Make them meaningfully different (e.g. positive / asks a question / polite decline or alternative). Each {text, uz} where uz is the Uzbek meaning.
    """.trimIndent()

    fun quick(basics: String) = basics + "\n" + quickFields

    fun details(basics: String) = basics + "\n" + detailsFields

    val rewriteSystem = """
        You turn an Uzbek speaker's draft into a DM reply they can send.
        The draft may be in Uzbek (Latin or Cyrillic), Russian, broken English, or a mix, and may contain typos.
        Write exactly 3 variants in the target language that sound like a native speaker texting a friend:
        1. closest to the draft's meaning,
        2. more natural / warmer,
        3. shorter.
        Keep the user's intent and facts. Never add plans, offers, promises, names or details that are not in the draft (for example do not add "on me" = offering to pay).
        Do not add greetings or sign-offs unless the draft has them.
        If conversation context is given, the reply must fit it (answer what was asked, keep references consistent) and match its tone: length, casing, slang, emoji use.
        For each variant also give uz: a faithful translation of that variant into natural Uzbek (Latin script), including anything it implies, so the user knows exactly what they are sending.
    """.trimIndent()

    fun rewriteInput(draft: String, context: ChatAnalysis?, friend: Friend?, language: String): String {
        val lines = mutableListOf("Target language: $language")
        when {
            context != null -> {
                lines.add("Conversation tone: ${context.tone}")
                if (context.partner.isNotEmpty()) lines.add("Partner: ${context.partner}")
                lines.add("Recent messages:")
                context.transcript.forEach { lines.add("${it.from}: ${it.text}") }
            }
            friend != null -> {
                lines.add("Partner: ${friend.name}")
                lines.add("Conversation tone: ${friend.tone}")
                lines.add("No recent messages available.")
            }
            else -> lines.add("No conversation context. Write a friendly, casual DM.")
        }
        lines.addAll(listOf("", "Draft:", draft))
        return lines.joinToString("\n")
    }

    private val suggestionSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("text") { put("type", "string") }
            putJsonObject("uz") { put("type", "string") }
        }
        putJsonArray("required") { add("text"); add("uz") }
    }

    val quickSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            for (field in listOf("partner", "language", "tone", "last_incoming_uz")) {
                putJsonObject(field) { put("type", "string") }
            }
        }
        putJsonArray("required") { add("partner"); add("language"); add("tone"); add("last_incoming_uz") }
    }

    val detailsSchema: JsonObject = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("summary_uz") { put("type", "string") }
            putJsonObject("transcript") {
                put("type", "array")
                putJsonObject("items") {
                    put("type", "object")
                    putJsonObject("properties") {
                        putJsonObject("from") {
                            put("type", "string")
                            putJsonArray("enum") { add("me"); add("them") }
                        }
                        putJsonObject("text") { put("type", "string") }
                    }
                    putJsonArray("required") { add("from"); add("text") }
                }
            }
            putJsonObject("suggestions") {
                put("type", "array")
                put("items", suggestionSchema)
            }
        }
        putJsonArray("required") { add("summary_uz"); add("transcript"); add("suggestions") }
    }

    val rewriteSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("variants") {
                put("type", "array")
                put("items", suggestionSchema)
            }
        }
        putJsonArray("required") { add("variants") }
    }
}
```

`android/app/src/main/java/com/ibrokhim/aikeyboard/ai/Translator.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.ChatDetails
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.QuickRead
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.data.Suggestion
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.Serializable

sealed interface ChatInput {
    /** Tagged lines read by the accessibility service: "[TOP] Emma", "[L] u free?", "[R] maybe". */
    data class Transcript(val lines: List<String>) : ChatInput

    /** Fallback for apps that draw text the accessibility tree cannot see. */
    class Screenshot(val jpeg: ByteArray) : ChatInput
}

data class AnalyzeResult(val analysis: ChatAnalysis, val partialError: Throwable?)

class Translator(private val llm: LlmClient) {
    /**
     * Two parallel calls on the same chat: the short one (translation) is handed to [onQuickRead] as soon
     * as it lands, the longer one (suggestions + transcript) completes the result. Throws only if both fail.
     * [knownFriends] lets the model map a cut-off or misread name onto a friend it already knows.
     */
    suspend fun analyze(
        input: ChatInput,
        knownFriends: List<String>,
        onQuickRead: (QuickRead) -> Unit,
    ): AnalyzeResult = coroutineScope {
        val (basics, content) = when (input) {
            is ChatInput.Transcript -> Prompts.transcriptBasics to listOf(Part.Text(input.lines.joinToString("\n")))
            is ChatInput.Screenshot -> Prompts.screenshotBasics to listOf(Part.Jpeg(input.jpeg))
        }
        val details = async {
            runCatchingNonCancel {
                val text = llm.generate(Prompts.details(basics), content, Prompts.detailsSchema)
                SharedStore.json.decodeFromString(ChatDetails.serializer(), text)
            }
        }
        val quickParts = if (knownFriends.isEmpty()) {
            content
        } else {
            listOf(Part.Text("Known friends: " + knownFriends.joinToString(", "))) + content
        }
        val quick = runCatchingNonCancel {
            val text = llm.generate(Prompts.quick(basics), quickParts, Prompts.quickSchema)
            SharedStore.json.decodeFromString(QuickRead.serializer(), text)
        }
        quick.getOrNull()?.let(onQuickRead)
        val detailsResult = details.await()
        val quickError = quick.exceptionOrNull()
        val detailsError = detailsResult.exceptionOrNull()
        if (quickError != null && detailsError != null) throw quickError
        AnalyzeResult(ChatAnalysis.of(quick.getOrNull(), detailsResult.getOrNull()), quickError ?: detailsError)
    }

    suspend fun rewrite(draft: String, context: ChatAnalysis?, friend: Friend?, language: String): List<Suggestion> {
        val input = Prompts.rewriteInput(draft, context, friend, language)
        val text = llm.generate(Prompts.rewriteSystem, listOf(Part.Text(input)), Prompts.rewriteSchema)
        return SharedStore.json.decodeFromString(RewriteResult.serializer(), text).variants
    }

    @Serializable
    private data class RewriteResult(val variants: List<Suggestion>)
}
```

- [ ] **Step 4: Run — passes**

Run: `./gradlew :app:testDebugUnitTest --tests '*TranslatorTest'`
Expected: `BUILD SUCCESSFUL`, 7 test PASS.

- [ ] **Step 5: Commit**

```bash
cd .. && git add android && git commit -m "Android: promptlar va Translator (matn va skrinshot yo'llari)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

### Task 5: `ChatAnalysisService` va haqiqiy Gemini bilan smoke test

**Files:**
- Create: `.../ai/ChatAnalysisService.kt`
- Test: `android/app/src/test/java/com/ibrokhim/aikeyboard/ai/ChatAnalysisServiceTest.kt`, `android/app/src/test/java/com/ibrokhim/aikeyboard/ai/GeminiLiveTest.kt`

**Interfaces:**
- Consumes: `SharedStore`, `SharedState.remember` (Task 2); `Translator`, `ChatInput`, `AnalyzeResult` (Task 4); `GeminiClient`, `OkHttpGeminiTransport` (Task 3).
- Produces: `class ChatAnalysisService(store: SharedStore, translator: Translator, clock: () -> Long = System::currentTimeMillis) { suspend fun run(input: ChatInput): ChatAnalysis }`.

- [ ] **Step 1: Failing test**

`android/app/src/test/java/com/ibrokhim/aikeyboard/ai/ChatAnalysisServiceTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.SharedStore
import java.io.File
import kotlin.test.assertFailsWith
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ChatAnalysisServiceTest {
    @get:Rule val folder = TemporaryFolder()

    private val quick = """{"partner":"Emma","language":"English","tone":"casual","last_incoming_uz":"Bo'shmisan?"}"""
    private val details = """{"summary_uz":"Uchrashuv.","transcript":[{"from":"them","text":"u free?"}],""" +
        """"suggestions":[{"text":"yes!","uz":"ha!"}]}"""

    private class Llm(private val answer: (String) -> String) : LlmClient {
        override suspend fun generate(system: String, parts: List<Part>, schema: JsonObject) = answer(system)
    }

    private fun store() = SharedStore(File(folder.root, "state.json"))
    private val input = ChatInput.Transcript(listOf("[TOP] Emma", "[L] u free?"))

    @Test fun successFillsContextAndRemembersTheFriend() = runTest {
        val store = store()
        val quickSnapshots = mutableListOf<ChatAnalysis?>()
        val llm = Llm { system ->
            if (system.contains("- partner:")) quick else details.also { quickSnapshots.add(store.value.context) }
        }
        store.update { it.copy(context = ChatAnalysis(partner = "Old chat"), contextDate = 1) }
        val analysis = ChatAnalysisService(store, Translator(llm)) { 1_000 }.run(input)

        assertEquals("Emma", analysis.partner)
        val state = store.value
        assertEquals(analysis, state.context)
        assertEquals(1_000L, state.contextDate)
        assertNull(state.analyzingSince)
        assertNull(state.lastError)
        assertEquals(listOf("Emma"), state.friends.map { it.name })
        assertEquals("Emma", state.activeFriend)
        assertEquals("English", state.targetLanguage)
        // The translation was on screen (without suggestions yet) before the details call finished.
        assertEquals(listOf("Emma"), quickSnapshots.map { it?.partner })
        assertEquals(0, quickSnapshots.single()?.suggestions?.size)
    }

    @Test fun partialFailureKeepsTheTranslationAndRecordsTheError() = runTest {
        val store = store()
        val llm = Llm { if (it.contains("- partner:")) quick else throw GeminiException.Timeout() }
        ChatAnalysisService(store, Translator(llm)) { 2_000 }.run(input)
        assertEquals("Emma", store.value.context?.partner)
        assertEquals("Gemini javob bermadi", store.value.lastError)
    }

    @Test fun totalFailureClearsTheSpinnerAndRecordsTheError() = runTest {
        val store = store()
        val llm = Llm { throw GeminiException.Http(503, "overloaded") }
        assertFailsWith<GeminiException.Http> { ChatAnalysisService(store, Translator(llm)) { 3_000 }.run(input) }
        assertNull(store.value.analyzingSince)
        assertEquals("Gemini 503: overloaded", store.value.lastError)
        assertEquals(3_000L, store.value.lastErrorDate)
    }
}
```

- [ ] **Step 2: Run — fails**

Run: `./gradlew :app:testDebugUnitTest --tests '*ChatAnalysisServiceTest'`
Expected: FAIL — `Unresolved reference 'ChatAnalysisService'`.

- [ ] **Step 3: Implementation**

`android/app/src/main/java/com/ibrokhim/aikeyboard/ai/ChatAnalysisService.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.SharedStore
import kotlinx.coroutines.CancellationException

/** Chat → Gemini → shared state. The keyboard follows `store.state` and shows each step. */
class ChatAnalysisService(
    private val store: SharedStore,
    private val translator: Translator,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    suspend fun run(input: ChatInput): ChatAnalysis {
        // A new read means a new chat — the previous chat's suggestions must not linger.
        store.update { it.copy(analyzingSince = clock(), context = null, contextDate = null) }
        try {
            val known = store.value.friends.map { it.name }
            val result = translator.analyze(input, known) { quick ->
                // The keyboard shows the translation now; suggestions follow when the second call lands.
                store.update { it.copy(context = ChatAnalysis.of(quick, null), contextDate = clock()) }
            }
            val now = clock()
            store.update {
                it.copy(
                    context = result.analysis,
                    contextDate = now,
                    analyzingSince = null,
                    lastError = result.partialError?.message,
                    lastErrorDate = result.partialError?.let { now },
                ).remember(result.analysis, now)
            }
            return result.analysis
        } catch (e: CancellationException) {
            store.update { it.copy(analyzingSince = null) }
            throw e
        } catch (e: Exception) {
            store.update { it.copy(analyzingSince = null, lastError = e.message, lastErrorDate = clock()) }
            throw e
        }
    }
}
```

- [ ] **Step 4: Run — passes**

Run: `./gradlew :app:testDebugUnitTest`
Expected: `BUILD SUCCESSFUL`, barcha testlar (27 + 8 + 14 + 9 + 7 + 3 = 68) PASS.

- [ ] **Step 5: Haqiqiy Gemini bilan smoke test**

`android/app/src/test/java/com/ibrokhim/aikeyboard/ai/GeminiLiveTest.kt`:
```kotlin
package com.ibrokhim.aikeyboard.ai

import java.io.File
import java.util.Properties
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Calls the real Gemini API with a made-up chat. Skipped unless android/local.properties has gemini.apiKey
 * and the LIVE_GEMINI environment variable is set — normal test runs never touch the network.
 */
class GeminiLiveTest {
    private val key: String = Properties().run {
        val file = File("../local.properties")
        if (file.exists()) file.inputStream().use { load(it) }
        getProperty("gemini.apiKey", "")
    }

    @Test fun transcriptReadingWorksEndToEnd() = runBlocking {
        assumeTrue(key.isNotBlank() && System.getenv("LIVE_GEMINI") != null)
        // Generous timeout: this checks the prompt and parsing, not today's API latency (often 5–25 s).
        val translator = Translator(GeminiClient(OkHttpGeminiTransport(), { key }, attemptTimeoutMs = 45_000))
        val lines = listOf(
            "[TOP] Emma",
            "[TOP] Active now",
            "[L] omg ur samarkand pics are unreal 😭😭",
            "[R] thank you! it was so beautiful",
            "[L] btw i'm landing in tashkent on friday w my sister ✈️",
            "[L] u free this weekend? we could grab food, ur call on the spot 🍜",
            "[L] 13:02",
        )
        val started = System.currentTimeMillis()
        val result = translator.analyze(ChatInput.Transcript(lines), emptyList()) {
            println("quick after ${System.currentTimeMillis() - started} ms: ${it.lastIncomingUz}")
        }
        println("full after ${System.currentTimeMillis() - started} ms: ${result.analysis.suggestions.map { it.text }}")
        result.partialError?.let { println("partial error: ${it::class.simpleName}: ${it.message} / ${it.cause}") }
        assertEquals("Emma", result.analysis.partner)
        assertEquals("English", result.analysis.language)
        assertEquals(3, result.analysis.suggestions.size)
        assertTrue(result.analysis.transcript.none { it.text == "13:02" || it.text == "Active now" })
    }
}
```

Run: `LIVE_GEMINI=1 ./gradlew :app:testDebugUnitTest --tests '*GeminiLiveTest' -i | grep -E "quick after|full after|PASSED|FAILED|SKIPPED"`
Expected: `quick after …`, `full after …` qatorlari va test PASS (Emma, English, 3 javob, vaqt va "Active now" transkriptda yo'q). Oddiy `./gradlew test` da bu test SKIPPED.

- [ ] **Step 6: Commit**

```bash
cd .. && git add android && git commit -m "Android: ChatAnalysisService va Gemini smoke testi

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- android
```

---

## Keyingi rejalar

M3 (Accessibility bilan chatni o'qish, takliflar paneli, javob chiplari, ✨, maqsad chipi), M4 (emoji, popup, tebranish, tafsilotlar, avtomatik o'qish), M5 (sozlash ekrani, foydalanuvchi API kaliti, README, APK).

## Eslatma: iOS'dan farqlar

- iOS'da `screenshotBasics` va maydonlar ro'yxati orasida yangi qator yo'q ("Return JSON:- partner: …"); Androidda `\n` qo'shildi.
- Gemini: iOS timeout'da zaxiraga o'tmaydi va 30 s kutadi; Androidda 5 s hedging va har qanday qayta urinishga arziydigan xatoda zaxira.
- `language(now)`: tez yarim yiqilganda (til bo'sh) `targetLanguage`ga tushadi — iOS bo'sh qatorni qaytarardi.
