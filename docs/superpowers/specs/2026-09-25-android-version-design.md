# AI Keyboard — Android versiyasi (dizayn)

Sana: 2026-09-25 · Holat: tasdiqlangan dizayn, implementatsiya rejasi keyingi qadam

## Maqsad

iOS'dagi AI Keyboard'ni Androidga olib o'tish: chet ellik do'st bilan DM'da yozishganda klaviatura suhbatni
o'qiydi, kelgan xabar tarjimasi va 3 ta tayyor javobni ko'rsatadi, o'zbekcha qoralamani ✨ bilan do'stning tiliga
suhbatga mos qilib qayta yozadi.

Qarorlar:

| Savol | Qaror |
|---|---|
| Tarqatish | Avval GitHub Releases'da APK (beta), Google Play keyinroq |
| Sinov qurilmasi | Hozircha faqat Mac'dagi `Pixel_9_Pro` emulyatori |
| Hajm | iOS bilan to'liq tenglik + Androidga xos "avtomatik o'qish" |
| Chatni o'qish | Accessibility xizmati: matn o'qiladi, bo'lmasa skrinshot (yondashuv A) |
| Ko'rinish | Android'ga mos Material You uslubi, ✨ va chiplarda brend rangi (`#3D7BFF → #7B4BFF`) |
| Texnologiya | Kotlin, tugmalar — o'z `View` (Canvas), qolgan UI — Jetpack Compose |

Ko'rib chiqilib rad etilgan yondashuvlar: MediaProjection skrinshoti (Android 14+ har seansda ruxsat dialogi va
status bar belgisi — noqulay; Play build uchun keyinroq qo'shiladi) va ilovani standart assistent qilish
(foydalanuvchi Gemini/Google Assistant'dan voz kechishi kerak).

## Arxitektura

Repoda yangi `android/` papkasi — Gradle loyiha, bitta `app` moduli, package `com.ibrokhim.aikeyboard`,
minSdk 26 (Android 8), targetSdk 36. iOS kodi joyida qoladi.

| Paket | Tarkibi | iOS'dagi o'xshashi |
|---|---|---|
| `ime/` | `AiKeyboardService : InputMethodService`, `KeysView` (Canvas tugmalar, multi-touch), `KeyboardController` (holat, matn kiritish mantig'i) | `KeyboardViewController`, `KeysUIView`, `KeyboardModel` |
| `ime/ui/` | Compose: `SuggestionBar`, `EmojiPanel`, `ContextDetails`, `TargetPicker` | `KeyboardView.swift`, `EmojiPanelView` |
| `reader/` | `ChatReaderService : AccessibilityService`, `ChatSnapshot`, oyna tugunlaridan qator yasash | Back Tap + Shortcut + skrinshot |
| `ai/` | `Gemini` (HTTP klient), `Translator` (promptlar), `ChatAnalysisService` | `Gemini.swift`, `Translator.swift`, `ChatAnalysisService.swift` |
| `data/` | `SharedStore` (JSON fayl + `StateFlow`), `Friend`, `Languages`, `EmojiRecents` | `SharedStore.swift`, `Models.swift` |
| `app/` | `MainActivity` (Compose): sozlash, sinov, sozlamalar, do'stlar, oxirgi kontekst | `ContentView.swift` |

Klaviatura, Accessibility xizmati va ilova **bitta jarayonda** ishlaydi. App Group va Darwin notification o'rniga
`SharedStore.state: StateFlow<SharedState>` — yozilganda klaviatura darhol yangilanadi; holat JSON faylga ham
yoziladi (jarayon o'ldirilsa tiklanadi). Androidda "Full Access" yo'q: `INTERNET` ruxsati manifestda.

API kalit: gitignore qilingan `android/local.properties` → `BuildConfig.GEMINI_API_KEY` (iOS'dagi
`Shared/Secrets.swift` tengi). Kalit hech qachon commit qilinmaydi.

### Holat (`SharedState`)

iOS `SharedState` bilan bir xil maydonlar, platformaga keraksizlari tashlangan:

- `context: ChatAnalysis?`, `contextDate`, `analyzingSince`, `lastError`, `lastErrorDate`
- `targetLanguage`, `activeFriend`, `friends: List<Friend>` (`name`, `language`, `tone`, `lastSeen`)
- `emojiKey: Boolean` (КИР/LAT o'rniga 😀), `autoRead: Boolean` (standart `false`)
- `lastReadHash: String?` — avtomatik o'qishda bir xil chatni qayta yubormaslik uchun

`keyboardFullAccessDate` va `shortcutRunDate` kerak emas. Do'st mantig'i (`isSamePerson`, prefiks va 6+ harfda 1 ta
farq, `mergeDuplicateFriends`, `remember`) iOS'dan aynan ko'chiriladi. 15 daqiqadan eski kontekst ko'rsatilmaydi.

## Chatni o'qish

### Qo'lda: 📖 tugmasi

Kontekst yo'q paytda takliflar panelining holat qatorida "📖 Chatni o'qish" turadi.

1. `KeyboardController` joriy maydonning package'ini (`EditorInfo.packageName`) biladi va
   `ChatReaderService.read(packageName)` ni chaqiradi (xizmat ulanganda o'zini singletonga yozadi).
2. Xizmat `windows` ichidan shu package'ning ilova oynasini oladi (klaviaturaning o'z oynasi emas).
3. Tugunlar daraxti aylanib chiqiladi: ko'rinadigan, bo'sh bo'lmagan, **tahrirlanmaydigan** matnlar yig'iladi
   (sizning qoralamangiz olinmaydi), `boundsInScreen` bo'yicha yuqoridan pastga tartiblanadi va belgilanadi:
   - `[TOP]` — oynaning yuqori 15% qismi (sarlavha, suhbatdosh ismi)
   - `[L]` — markazi oyna o'rtasidan chapda (u), `[R]` — o'ngda (men)
4. Pastdan oxirgi 40 qator olinadi. Vaqt, "Seen", tugma nomlarini kod filtrlamaydi — prompt modeldan ularni
   e'tiborsiz qoldirishni so'raydi (har messenger boshqacha tuzilgan, qo'lda filtr tez sinadi).
5. **Zaxira:** `[L]`/`[R]` qatorlari 2 tadan kam bo'lsa (ilova matnni rasm qilib chizadi) — Android 11+ da
   `takeScreenshot()` → 720px JPEG → iOS'dagi skrinshot promptlari. Android 10 va eskisida: "Bu ilovadan o'qib
   bo'lmadi" xabari.
6. `ChatAnalysisService.run(snapshot)` — iOS'dagidek: kontekst tozalanadi, `analyzingSince` qo'yiladi, quick va
   details **parallel**, "Known friends" bilan; quick kelishi bilan tarjima ko'rinadi, keyin javoblar;
   `remember()` do'stni eslaydi va maqsad tilni almashtiradi.

Qator yasash (3–4-qadamlar) Android API'siga bog'liq bo'lmagan sof funksiya: `buildLines(nodes: List<TextNode>,
window: Rect): List<TaggedLine>` — shu sababli JVM testida soxta tugunlar bilan tekshiriladi.

### Matnli promptlar

iOS promptlari (`screenshotBasics`, `quickSystem`, `detailsSystem`, `rewriteSystem`, JSON sxemalar) Kotlinga aynan
ko'chiriladi. Matn yo'li uchun `screenshotBasics` o'rniga `transcriptBasics`: "Sizga DM ekranining ko'rinadigan
matni qatorma-qator beriladi; `[R]` — foydalanuvchi, `[L]` — suhbatdosh, `[TOP]` — sarlavha. Vaqt, holat va UI
yozuvlarini e'tiborsiz qoldiring." Qolgan JSON maydonlar va qoidalar bir xil — `ChatAnalysis` modeli o'zgarmaydi.

### Avtomatik o'qish (sozlama, standart o'chiq)

`AiKeyboardService.onStartInputView` da, `autoRead` yoqilgan va package messengerlar ro'yxatida bo'lsa
(`com.instagram.android`, `org.telegram.messenger`, `com.whatsapp`, `com.facebook.orca`, `com.snapchat.android`,
`com.discord`, `jp.naver.line.android`, `com.kakao.talk`, ilovaning o'z demo chati): chat o'qiladi, qatorlar
xeshi `lastReadHash` bilan solishtiriladi — o'zgarmagan bo'lsa va kontekst hali yangi bo'lsa, Gemini'ga so'rov
ketmaydi. Parol, email, URL maydonlarida ishlamaydi.

### Accessibility xizmati sozlamasi

`canRetrieveWindowContent=true`, `canRequestFilterKeyEvents=false`, `canTakeScreenshot=true`,
`flagRetrieveInteractiveWindows`. Hodisalarni kuzatmaydi (`onAccessibilityEvent` bo'sh) — faqat so'ralganda o'qiydi.
Yoqishdan oldin ilovada ochiq tushuntirish ekrani: nima o'qiladi, qachon, qayerga yuboriladi (Gemini), nima
saqlanadi.

## Klaviatura

### Tugmalar — `KeysView`

- Qatlamlar: lotin (`q…p` / `a…l` / `z…m`, pastki qatorda `oʻ` `gʻ`), kirill (`й…ъ` / `ф…э` / `я…ю`, `ғ` `ҳ`),
  raqamlar, belgilar (2 sahifa) — iOS `KeysUIView` jadvallari aynan.
- Pastki qator: `123` · `КИР/LAT` (yoki `emojiKey` bo'lsa 😀) · ikki qo'shimcha harf · probel · Enter
  (`EditorInfo.imeOptions` bo'yicha belgisi: yuborish/keyingi/bajarildi).
- Shift: bir bosish — bitta katta harf, ikki bosish (0.3s) — Caps Lock; avtomatik katta harf
  (`autocapitalize` mantig'i iOS'dan); ikki probel (0.35s) → ". ".
- Backspace bosib turilsa takrorlanadi; probel ustida surish kursorni yurgizadi.
- Multi-touch: har barmoq alohida kuzatiladi, harf barmoq ko'tarilganda emas, bosilganda yoziladi (rollover).
- Popup: bosilgan harf ustida pufakcha. Butun klaviatura (panel + tugmalar) ustida shaffof overlay `View`
  pufakchalarni chizadi, shuning uchun yuqori qator pufakchasi takliflar paneli ustiga chiqa oladi.
- Tebranish va ovoz tizim sozlamasiga bo'ysunadi: `performHapticFeedback(KEYBOARD_TAP)`,
  `AudioManager.playSoundEffect(FX_KEYPRESS_*)`.
- Globus faqat `shouldOfferSwitchingToNextInputMethod()` true bo'lsa.

### Takliflar paneli va boshqa Compose qismlari

IME ichida `ComposeView` — `ViewTreeLifecycleOwner`/`SavedStateRegistryOwner` servis tomonidan beriladi.

- Holat qatori: "📖 Chatni o'qish" / "Suhbat o'qilmoqda…" / tarjima qatori (✕ — kontekstni yopish, bosilsa
  `ContextDetails`) / "✨ → 🇬🇧 English · Emma" maqsad chipi (bosilsa `TargetPicker`: do'stlar va tillar).
  O'ngda ✨ tugmasi.
- Chip qatori: 3 ta javob (`text` + kichik `uz`), ✨ dan keyin 3 ta variant, kontekst yo'q bo'lsa do'st/til
  chiplari. Bo'sh bo'lsa panel yig'iladi — klaviatura balandligi animatsiya bilan o'zgaradi.
- `ContextDetails`: tugmalar o'rnida to'liq transkript va `summary_uz`.
- `EmojiPanel`: iOS `EmojiData` (1297 ta, kategoriyalar) Kotlinga ko'chiriladi, "oxirgi ishlatilganlar".
- Qisqa xabarlar (xato, maslahat) 4 soniya.
- Tanlangan javob/variant maydondagi butun qoralamani almashtiradi (`replaceAllText` iOS mantig'i:
  `getTextBeforeCursor`/`AfterCursor` bo'yicha o'chirib, keyin `commitText`).

### Ko'rinish

Material You: tizim yorug'/tungi rejimiga ergashadi, tugmalar tekisroq, burchak radiusi Gboard'ga yaqin. Brend
rangi faqat ✨ tugmasi, faol chiplar va 📖 da. Dinamik rang (wallpaper) ishlatilmaydi — brend rangi barqaror.

## AI qatlami

- Modellar: `gemini-3.5-flash-lite` asosiy, `gemini-3.5-flash` zaxira (iOS bilan bir xil).
- **Hedging:** asosiy so'rov 5 soniyada javob bermasa, zaxira modelga parallel so'rov ketadi; birinchi muvaffaqiyatli
  javob olinadi, ikkinchisi bekor qilinadi. 429/500/503, timeout va tarmoq xatolari ham darhol zaxiraga o'tadi
  (iOS'da timeout zaxiraga o'tmaydi — o'sha xatoni takrorlamaslik uchun).
- Har urinishga 30 soniya timeout (jonli o'lchovda kichik so'rovlar ham 15 s gacha oldi); ikkalasi ham yiqilsa — xato xabari va "Qayta urinish" chipi.
- `thinkingLevel: minimal`, `responseMimeType: application/json`, JSON sxemalar iOS'dan.
- HTTP: OkHttp; JSON: kotlinx.serialization; parallellik: coroutines.

## Ilova ekrani (`MainActivity`)

1. **Sozlash** (✓ holati avtomatik aniqlanadi): klaviaturani yoqish (`ACTION_INPUT_METHOD_SETTINGS`,
   `enabledInputMethodList`), tanlash (`showInputMethodPicker`, `DEFAULT_INPUT_METHOD`), "Chat o'qish" xizmati
   (tushuntirish ekrani → `ACTION_ACCESSIBILITY_SETTINGS`, yoqilgan xizmatlar ro'yxati).
2. **Sinov:** ilova ichidagi demo chat (to'qima "Emma" suhbati, inglizcha slang) va matn maydoni — messenger
   o'rnatmasdan 📖 → tarjima → javob → ✨ oqimini sinash uchun; emulyatordagi sinov va demo videolar ham shunda.
3. **Til:** maqsad til tanlash (iOS `Languages` ro'yxati).
4. **Klaviatura:** 😀 tugmasi, avtomatik o'qish.
5. **Do'stlar:** ro'yxat, o'chirish.
6. **Oxirgi kontekst:** xulosa, transkript, eskirganlik belgisi.

## Xatolar

| Holat | Nima ko'rinadi |
|---|---|
| Accessibility o'chiq, 📖 bosildi | Qisqa xabar + ilovadagi sozlash qadamiga havola |
| Oyna topilmadi / qator yo'q / Android < 11 | "Bu ilovadan o'qib bo'lmadi" |
| Tarmoq yo'q, Gemini yiqildi | Xato matni + "Qayta urinish" chipi |
| Gemini yarim javob (quick bor, details yo'q) | Tarjima ko'rinadi, javoblar o'rnida xato chipi (iOS `partialError`) |
| Jarayon o'ldirildi | Holat JSON'dan tiklanadi |

## Maxfiylik

- Chat faqat 📖 bosilganda yoki foydalanuvchi o'zi yoqqan avtomatik o'qishda, faqat ro'yxatdagi messengerlarda
  o'qiladi.
- Diskda faqat oxirgi ≤6 xabar va do'stlar ro'yxati saqlanadi (iOS bilan bir xil); skrinshot diskka yozilmaydi.
- Klaviatura yozilgan matnni hech qayerga yubormaydi — faqat ✨ bosilganda maydondagi qoralama va kontekst.
- Haqiqiy DM ismlari va matnlari kod, izoh, test va commit'larga yozilmaydi (demo va testlarda faqat to'qima).

## Sinov

- **JVM unit testlar:** `isSamePerson`/dublikat birlashtirish, `SharedState` JSON, `buildLines` (soxta tugunlar:
  chap/o'ng/sarlavha, tahrirlanadigan maydon chiqarib tashlanishi), `autocapitalize` va ikki probel, Gemini javobini
  `ChatAnalysis`ga o'girish, hedging (soxta klient bilan: sekin asosiy → zaxira g'olib).
- **Emulyator (qo'lda, Claude `adb` bilan):** `Pixel_9_Pro` — o'rnatish, `ime enable/set`, xizmatni yoqish, demo
  chatda 📖 → tarjima → javob tanlash → ✨ → variant; har bosqichda skrinshot.

## Bosqichlar

1. Skelet: Gradle loyiha, `AiKeyboardService`, `KeysView` (barcha qatlamlar), oddiy yozish ishlaydi.
2. Ma'lumot va AI: `SharedStore`, modellar, `Gemini` (hedging), `Translator`, `ChatAnalysisService` + unit testlar.
3. Chatni o'qish (matn + skrinshot), takliflar paneli, javob chiplari, ✨, maqsad chipi.
4. Emoji paneli, kirill, popup'lar, tebranish/ovoz, `ContextDetails`, avtomatik o'qish.
5. `MainActivity` (sozlash, sinov, sozlamalar), README'ga Android bo'limi, imzolangan APK (GitHub Releases).

## Doiradan tashqari (keyinroq)

- Google Play build: MediaProjection skrinshoti bilan alohida flavor, Play Accessibility deklaratsiyasi.
- CI (GitHub Actions), Play listing, iOS bilan kod bo'lishish (KMP).
