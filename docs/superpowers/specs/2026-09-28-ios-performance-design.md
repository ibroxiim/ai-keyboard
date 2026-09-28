# AI Keyboard — iOS optimizatsiyasi (dizayn)

Sana: 2026-09-28 · Holat: tasdiqlangan dizayn, implementatsiya rejasi keyingi qadam

## Maqsad

Foydalanuvchi iPhone'da (iPhone 14 Pro, iOS 27.0, ProMotion 120 Hz) uchta muammoni sezmoqda:

1. **Harflar bosilmay qoladi** — "bosdim deb o'ylayman, lekin ko'pincha chiqmaydi". Aniq joy yo'q: hamma
   tugmalarda, tasodifiy.
2. **Yozishda lag.**
3. **Telefon qiziydi va batareya tez tugaydi** — AI Keyboard ochiq turib yozilayotganda.

Back Tap / ✨ tezligi va tarmoq sarfi — ikkinchi darajali, rejaning oxirgi bosqichi.

Qarorlar:

| Savol | Qaror |
|---|---|
| Yondashuv | **Avval o'lchash, keyin tuzatish** (A). Kod o'qishda ko'rinib turgan aniq xatolar darhol tuzatiladi |
| Ustuvorlik | Harf yo'qolishi → qizish/CPU → kechikish → tarmoq |
| O'lchov qurilmasi | Mac'ga ulangan iPhone 14 Pro, Release build, Instruments (`xctrace`) + ilova ichidagi diagnostika |
| Taqqoslash asosi | Xuddi shu sharoitda Apple klaviaturasi |

Ko'rib chiqilib rad etilgan yondashuvlar: hamma gumonlarni o'lchovsiz birdan tuzatish (B — haqiqiy sabab boshqa
joyda bo'lsa bilmay qolamiz, yaxshilanishni isbotlab bo'lmaydi) va tugmalar maydonini darhol bitta chizma
qatlamga qayta yozish (C — katta xavfli o'zgarish; M3'da faqat o'lchov chizish qimmatligini ko'rsatsa).

## Hozirgi holat: kod o'qishda topilgan gumonlar

Yozish va qizish:

| # | Gumon | Joy |
|---|---|---|
| 1 | "Suhbat o'qilmoqda…" spinneri to'xtamay qolishi mumkin: `isAnalyzing` `Date()` bilan faqat qayta chizishda hisoblanadi, 60 s muddat o'tganda qayta chizishga sabab yo'q; tahlil tugamay qolsa (`analyzingSince` tozalanmasa) spinner klaviatura ochiq turgan butun vaqt 120 Hz'da aylanadi | `Shared/SharedStore.swift` `isAnalyzing`, `Keyboard/KeyboardView.swift` |
| 2 | Teginishlar UITouch obyektining identifikatori bilan saqlanadi; bitta teginishning oxiri kelmay qolsa eski yozuv qoladi va keyingi teginishlar unga ulanib yo'qolishi mumkin | `Keyboard/KeysUIView.swift` `active`, `touchesEnded` |
| 3 | Rejim almashganda (masalan 123 → harflar) `rebuild()` bosib turilgan harfni bekor qiladi | `KeysUIView.rebuild` → `cancelAllTouches` |
| 4 | Bo'sh joy bosib turilganda keyingi harf avval yoziladi — tartib almashadi | `KeysUIView.touchesBegan` (rollover faqat harflar uchun) |
| 5 | Tizim bekor qilgan teginish (`touchesCancelled`) harfsiz tashlanadi, hech qayerda qayd etilmaydi | `KeysUIView.touchesCancelled` |
| 6 | Har shift o'zgarishida 35 tugma qayta sozlanadi: shrift va SF Symbol rasmi har safar yangidan | `KeyCapView.configure` |
| 7 | Kirill tartibida yuqori qatorda 12 tugma (~26 pt), lotindagidan ~20% tor | `KeysUIView.cyrillic` |

Tarmoq va Back Tap:

| # | Gumon | Joy |
|---|---|---|
| 8 | Bitta skrinshot ikki parallel so'rovda ikki marta yuklanadi (~2 × 100 KB base64) | `Shared/Translator.swift` `analyze` |
| 9 | Skrinshotning ~40% i klaviaturaning o'zi | — |
| 10 | Skrinshot to'liq o'lchamda ochilib keyin kichraytiriladi | `Shared/ChatAnalysisService.swift` `ScreenshotImage.jpeg` |
| 11 | Zaxira model faqat 429/5xx dan keyin, ketma-ket; har urinishga 30 s — eng yomon holat 60 s | `Shared/Gemini.swift` `generate` |
| 12 | Har chaqiruv sovuq ulanish (intent har safar yangi jarayonda); HTTP/3 va oldindan ulanish yo'q | `Gemini.call` |

Hech qanday o'lchov yo'q — qaysi bosqich qancha vaqt olishi noma'lum.

## Muvaffaqiyat mezonlari

M2 o'lchovidan keyin raqamlar aniqlashtiriladi, lekin maqsad:

| Mezon | Maqsad | Qanday o'lchanadi |
|---|---|---|
| Harf yo'qolishi | **0** — tugma ustida boshlangan har teginish harf beradi yoki jurnalda aniq sabab bilan qayd etiladi | S1: test iborasi farqi + jurnal |
| Tugma javobi | Barmoq ko'tarilgan paytdan (`touch.timestamp`) `insertText` qaytguncha **p95 ≤ 16 ms** (120 Hz'da 2 kadr) | Jurnal |
| Bo'sh turganda CPU | **≈ 0%** — klaviatura ochiq, yozilmayapti, uzluksiz animatsiya yo'q | S2 |
| Yozishdagi CPU va harorat | 5 daqiqalik testda klaviatura jarayoni CPU'si Apple klaviaturasidan sezilarli oshmaydi, harorat holati undan yuqoriga chiqmaydi | S3 |
| Back Tap | Mobil internetda birinchi tarjima chiqquncha vaqt M2 asosiga nisbatan **≥ 30% tezroq**, yuklangan bayt **≥ 60% kam** | S5 |

## Bosqichlar

| Bosqich | Mazmun | Natija |
|---|---|---|
| **M1** | Diagnostika qatlami + ilovada "Diagnostika" ekrani + aniq xatolar (1–5) + `TouchTracker` va birinchi test target | O'lchash asbobi tayyor, aniq xatolar yopilgan |
| **M2** | iPhone 14 Pro'da o'lchov sessiyasi (S1–S5), AI Keyboard va Apple klaviaturasi taqqoslanadi | `docs/perf/` da raqamli hisobot va sabablar ro'yxati |
| **M3** | M2 ko'rsatgan sabablarni tuzatish (matritsa quyida) | Mezonlar qayta o'lchov bilan isbotlangan |
| **M4** | Tarmoq va Back Tap | Tezroq tarjima, kam trafik |

Har bosqichga alohida implementatsiya rejasi (`docs/superpowers/plans/`) va alohida PR.

## M1 — Diagnostika qatlami

### Tamoyil

Diagnostika o'lchovni buzmasligi kerak: taymer yo'q, doimiy so'rov yo'q, alohida oqim yo'q. Teginish faqat
xotiradagi massivga qo'shiladi; faylga klaviatura yopilganda bir marta yoziladi. Standart holatda **o'chiq** —
o'chiqligida narxi bitta `if`. M2'da bir marta diagnostika yoqiq va o'chiq holda S2/S3 solishtiriladi: qo'shimcha
CPU < 1% bo'lishi kerak.

### Qismlar (`Keyboard/Diagnostics/`)

| Qism | Vazifa | Usul |
|---|---|---|
| `TouchJournal` | `TouchTracker` natijalarini yig'adi: har teginish uchun zona, natija, kechikishlar | Xotiradagi massiv; oddiy chatlarda faqat hisoblagichlar (quyida) |
| `MainThreadMonitor` | Asosiy oqim 50 ms dan uzoq band bo'lgan paytlar soni va eng uzuni | Asosiy runloop'ga `CFRunLoopObserver`: `afterWaiting` → `beforeWaiting` oralig'i |
| `ThermalMonitor` | Sessiya boshidagi holat va har o'zgarish (nominal/fair/serious/critical) vaqti bilan | `ProcessInfo.thermalStateDidChangeNotification` |
| `ProcessStats` | Jarayon CPU vaqti (user + system) va xotira (`phys_footprint`) — sessiya boshida va oxirida; xotira ogohlantirishlari soni | `task_info`, `didReceiveMemoryWarning` |
| `Signposts` | `OSSignposter` intervallari: tugma (ko'tarilish → `insertText`), ✨, Back Tap bosqichlari | Doim yoqiq (Instruments yozmayotganda deyarli bepul) |

Vaqtlar bir xil soatda: `touch.timestamp` va `ProcessInfo.processInfo.systemUptime`.

### Sessiya va saqlash

Sessiya = klaviaturaning bir marta ko'rinishi (`viewWillAppear` → `viewDidDisappear`). Yopilganda xulosa App
Group'dagi `diagnostics.json` ga qo'shiladi, oxirgi 50 sessiya saqlanadi (Full Access yo'q bo'lsa — yozilmaydi).

```json
{
  "sessions": [{
    "start": "2026-09-28T10:00:00Z", "duration": 184.2, "testMode": false,
    "touches": 612, "typed": 588,
    "outcomes": { "typed": 540, "rolledOver": 44, "slid": 3, "committedOnRebuild": 1,
                  "recoveredMissingEnd": 0, "cancelledBySystem": 2, "function": 22 },
    "zones": { "edge":   { "touches": 140, "lost": 1 },
               "center": { "touches": 380, "lost": 0 },
               "bottom": { "touches": 92,  "lost": 1 } },
    "upToInsertMs": { "p50": 3.1, "p95": 9.8, "max": 41.0 },
    "deliveryMs":   { "p50": 1.2, "p95": 6.5, "max": 38.0 },
    "mainBusy": { "over50ms": 2, "maxMs": 120 },
    "cpu": { "seconds": 5.4, "percent": 2.9 },
    "memoryMB": { "start": 31.2, "end": 33.0, "warnings": 0 },
    "thermal": [{ "state": "nominal", "t": 0 }, { "state": "fair", "t": 150.3 }],
    "detail": null
  }]
}
```

`typed` — harf bergan teginishlar (`typed + rolledOver + slid + committedOnRebuild + recoveredMissingEnd`);
`lost` = `cancelledBySystem` (M2 ma'lumoti hal qilmaguncha shunday hisoblanadi). Zonalar: `edge` — yuqori uch
qatorning birinchi va oxirgi tugmasi, `bottom` — pastki qator, `center` — qolganlari. `upToInsertMs` — harfni
yozdirgan hodisa vaqtidan (odatda barmoq ko'tarilishi; `rolledOver` da keyingi teginish boshlanishi)
`insertText` qaytguncha; `deliveryMs` — o'sha hodisaning `touch.timestamp` idan bizning ishlovchimiz
boshlanguncha. `detail` — faqat test rejimida:
har teginish uchun `{t, key: [qator, ustun], kind, outcome, deliveryMs, upToInsertMs}`.

### Maxfiylik

- Harflar, matn va `textDocumentProxy` mazmuni hech qachon yozilmaydi.
- **Oddiy chatlarda** faqat hisoblagichlar va foizlar (yuqoridagi xulosa). Tugmalar ketma-ketligi saqlanmaydi —
  qator/ustun ketma-ketligidan matnni tiklash mumkin.
- **Test rejimida** (ilovaning o'z test maydoni) batafsil `detail` saqlanadi. Klaviatura test maydonini
  `textDocumentProxy.textContentType` dagi maxsus qiymatdan (`com.ibrokhim.dmtranslator.diagnostics`) taniydi.
  M1'da bu qiymat klaviaturaga yetib kelishi tekshiriladi; kelmasa — maydon xususiyatlarining noyob
  kombinatsiyasi (`returnKeyType` + `autocorrectionType`; `keyboardType` emas — ASCII maydonlarga iOS bu
  klaviaturani qo'ymaydi) belgi bo'ladi.

### Ilovadagi "Diagnostika" bo'limi

`ContentView` dagi yangi bo'lim (`diagnosticsSection`) → alohida ekran:

- **Diagnostika** tugmasi (`SharedState.diagnosticsEnabled`, klaviatura har ko'rinishda o'qiydi).
- **Test**: belgilangan o'zbekcha ibora (~200 belgi) va test maydoni. "Tugatish" bosilganda ilova yozilganni
  kutilgan matn bilan Levenshtein tekislash orqali solishtiradi (tushib qolgan / ortiqcha / almashgan harflar;
  `ʻ ’ '` bir xil hisoblanadi) va shu sessiyaning jurnali bilan yonma-yon ko'rsatadi. Matnda harf yo'q, jurnal
  esa yo'qotish ko'rmagan bo'lsa — teginish bizgacha yetib kelmagan (tizim darajasi).
- **Sessiyalar** ro'yxati va xulosalari.
- **Eksport** — `diagnostics.json` ni share sheet orqali. Iloji bo'lsa men faylni `xcrun devicectl device copy
  from` bilan App Group konteyneridan to'g'ridan-to'g'ri olaman.

## M1 — Aniq xatolar

### 1. To'xtamay qoladigan spinner

- `SharedState` ga sof funksiyalar: `isAnalyzing(at:)`, `recentError(at:)` va
  `nextDeadline(after now: Date) -> Date?` — `analyzingSince + 60 s`, `lastErrorDate + 120 s`,
  `contextDate + 15 daqiqa` dan `now` dan keyingi eng yaqini.
- `KeyboardModel` ko'rinishlar `now` asosida hisoblaydi (`freshContext(at: now)` kabi). Holat yuklanganda va
  `now` yangilanganda eng yaqin muddatga bitta `Task.sleep` qo'yiladi; uyg'onganda `now = Date()` va keyingi
  muddat. Klaviatura yopilganda vazifa bekor qilinadi.
- Ilova (`ContentView`) uchun `isAnalyzing` / `recentError` qulaylik xususiyatlari qoladi.

### 2–5. `TouchTracker`

Teginish mantig'i `KeysUIView` dan UIKit'siz sof turga ko'chadi: `Keyboard/TouchTracker.swift`.

```swift
struct TouchTracker {
    enum KeyKind { case character, space, newline, backspace, shift, other }
    enum Event {
        case began(id: ObjectIdentifier, key: Int, x: CGFloat, time: TimeInterval, alive: Set<ObjectIdentifier>)
        case moved(id: ObjectIdentifier, key: Int?, x: CGFloat)
        case ended(id: ObjectIdentifier, time: TimeInterval)
        case cancelled(id: ObjectIdentifier)
        case willRebuild
    }
    enum Action {
        case keyDown(key: Int), type(key: Int), space, newline, backspace, shift, release(key: Int)
        case startRepeat, stopRepeat, moveCursor(Int), showPopup(key: Int), hidePopup
    }
    enum Outcome { case typed, rolledOver, slid, committedOnRebuild, recoveredMissingEnd, cancelledBySystem, function }

    var keys: [KeyKind]            // rebuild'da yangilanadi
    mutating func handle(_ event: Event) -> (actions: [Action], outcomes: [(key: Int, Outcome)])
}
```

`KeysUIView` yupqa qatlamga aylanadi: UIKit teginishini `Event` ga o'giradi (`alive` = `event.allTouches`),
`Action` larni bajaradi (`model.type`, popup, taymer), `Outcome` larni `TouchJournal` ga beradi.

Qoidalar:

- **Eski yozuvlar (2):** `began` kelganda `alive` da yo'q yozuvlar tozalanadi; yozilmagan harfi bo'lsa — yoziladi
  (`recoveredMissingEnd`), chunki foydalanuvchi uni bosgan.
- **Rebuild (3):** `willRebuild` da bosib turilgan yozilmagan harflar avval yoziladi (`committedOnRebuild`), keyin
  hammasi tozalanadi.
- **Bo'sh joy rollover (4):** bo'sh joy bosib turilganda (kursor surish boshlanmagan) yangi teginish kelsa, avval
  bo'sh joy yoziladi va yozuv `committed` bo'ladi — ko'tarilganda qayta yozilmaydi.
- **Tizim bekor qilishi (5):** hozirgidek harfsiz, lekin `cancelledBySystem` qayd etiladi. Xatti-harakat M2
  ma'lumotidan keyin hal qilinadi.
- Qolganlari hozirgidek: harf ko'tarilganda yoziladi, yangi teginish ushlab turilgan harfni yozadi (`rolledOver`),
  surilgan barmoq popupni ko'chiradi (`slid`), shift bosilishda, ⌫ takrorlanadi, bo'sh joyni surish kursorni
  siljitadi.

### Test target

`project.yml` ga `AIKeyboardTests` (unit-test bundle, host ilovasiz; `TouchTracker.swift`, `SharedStore.swift`,
`Models.swift`, diagnostika tahlil funksiyalari manba sifatida qo'shiladi). Testlar:

- `TouchTracker`: oddiy bosish; rollover; bo'sh joy + harf tartibi; kursor surish paytida rollover yo'q; rebuild
  harfni yo'qotmaydi; oxiri kelmagan teginish tiklanadi; bekor qilish qayd etiladi; ⌫ takrori.
- `SharedState.nextDeadline` va `isAnalyzing(at:)`.
- Test iborasini solishtirish (Levenshtein tekislash) va jurnal xulosasi (p50/p95, zonalar).

Tekshiruv: `xcodebuild test` (Simulator), keyin Simulator'da yozib ko'rish. Haqiqiy natija — M2.

## M2 — O'lchov sessiyasi

**Sharoit:** Release build (men o'rnataman); quvvat > 50%, zaryadga ulanmagan, Low Power Mode o'chiq, bir xil
yorug'lik; telefon test oldidan sovuq (harorat holati nominal); Telegram'ning Saved Messages chati (haqiqiy
suhbat yo'q); test matnlari oldindan tayyorlanadi.

| # | Stsenariy | Hajm | O'lchanadi |
|---|---|---|---|
| S1 | Ilova test maydonida belgilangan ibora | 3 × oddiy + 1 × tez | Harf yo'qolishi va sababi, `upToInsert` / `delivery` p50/p95/max, asosiy oqim qotishlari |
| S2 | Klaviatura ochiq, yozilmaydi | 2 daqiqa | Bo'sh turgandagi CPU, energiya ta'siri |
| S3 | Telegram'da bir xil matn: AI Keyboard, keyin Apple klaviaturasi | 2 × 5 daqiqa, orada sovish | Klaviatura va Telegram jarayonlari CPU'si, harorat holati o'tishlari va vaqti, kadr qotishlari, xotira cho'qqisi |
| S4 | Klaviaturani 20 marta ochib-yopish | 1 marta | Xotira o'sishi, `KeyboardViewController` nusxalari (Memory Graph) |
| S5 | Back Tap: 10 × Wi-Fi, 10 × mobil internet, bir xil ekran; ✨ 10 marta | — | Rasm tayyorlash, yuklangan bayt, birinchi bayt, umumiy vaqt, birinchi tarjima klaviaturada chiqqan vaqt |

Asboblar: Time Profiler (klaviatura jarayoniga `xctrace record --attach`), Animation Hitches, Activity Monitor,
Allocations/Memory Graph, `os_signpost` (Points of Interest). Diagnostika fayli har stsenariydan keyin olinadi.
S2/S3 bir marta diagnostika o'chiq holda ham qilinadi (qo'shimcha narxni tekshirish).

Rollar: men build, Instruments va tahlil; foydalanuvchi telefonda yozadi va Back Tap bosadi (~30–40 daqiqa,
qadamlar men tomondan aytib boriladi).

Natija: `docs/perf/<M2 sanasi>-ios-baseline.md` — har mezon bo'yicha hozirgi raqam, topilgan sabablar va M3
uchun tartiblangan ro'yxat. Trace fayllari repoga qo'shilmaydi.

## M3 — Tuzatishlar matritsasi

Qoida: har tuzatish M2'dagi aniq raqamga tayanadi va o'sha stsenariy bilan qayta o'lchanadi; yaxshilanish
bo'lmasa — qaytariladi. Bir nechta sabab bo'lsa: harf yo'qolishi → qizish/CPU → kechikish.

| M2 ko'rsatsa | Tuzatish |
|---|---|
| Teginish bizgacha yetmaydi (matnda yo'q, jurnal toza) | `viewDidAppear` da klaviatura oynasining tizim imo-ishora tanib olgichlarida `delaysTouchesBegan = false`. Yordam bermasa — minimal test klaviatura bilan iOS 27 xatosi tasdiqlanadi, Feedback |
| Yetib keladi, lekin bekor qilinadi | Bekor qiluvchi tanib olgich aniqlanadi; SwiftUI bo'lsa `KeysUIView` hosting ierarxiyasidan chiqariladi: klaviatura ildizi UIKit, panel — alohida `UIHostingController`, tugmalar uning yonida |
| Yetib keladi, mantiq yo'qotadi | `TouchTracker` tuzatiladi + regressiya testi |
| Kechikish / asosiy oqim > 16 ms | Time Profiler ko'rsatgan joyga qarab: shiftda faqat o'zgargan yozuvlar va shift ikonkasi yangilanadi, shrift va SF Symbol rasmlari keshlanadi; tugmalar konfiguratsiyasi SwiftUI orqali emas, to'g'ridan-to'g'ri kuzatuv bilan uzatiladi; `SharedStore.load()` asosiy oqimdan chiqadi |
| Bo'sh turganda CPU > 0 | Uzluksiz animatsiya manbai topiladi va olib tashlanadi |
| Yozishdagi CPU Apple'dan ancha yuqori, chizish qimmat | Tugma soyalari va avtomatik shrift kichraytirish arzonlashtiriladi; yetmasa — **C**: tugmalar maydoni bitta chizma qatlam (faqat rejim/shift o'zgarganda qayta chiziladi) |
| CPU past, lekin tezroq qiziydi | GPU: klaviatura foni materiallari, SwiftUI ScrollView effektlari; panel balandligi o'zgarishida Telegram'ning qayta joylashuvi — o'zgarishlar kamaytiriladi |
| Taptic Engine sezilarli energiya | `prepare()` — sessiya boshida va 2 s tanaffusdan keyin, har tugmada emas |
| Ochib-yopishda xotira o'sadi | Retain cycle tuzatiladi; emoji ma'lumoti faqat kerak bo'lganda yuklanadi |
| "Harf yo'q, jurnal toza" holatlar yuqori qatorda to'plansa | Panelning bo'sh joylariga tushgan pastki 8–10 pt teginishlar tugmalarga uzatiladi |
| Kirill tartibida xato bosish ko'p (foydalanuvchi kirillda yozsa) | Yuqori qator 11 ustunga (`ъ` boshqa joyga) |

M3 hajmi M2 natijasiga bog'liq — uning rejasi M2 hisobotidan keyin yoziladi.

## M4 — Tarmoq va Back Tap

Har o'zgarish Diagnostika ekranidagi tajriba bayrog'i ortida (`SharedState.experiments`) va S5 bilan "oldin/keyin"
o'lchanadi. Sifat yoki tezlik yomonlashsa — qo'shilmaydi. Qarordan keyin bayroqlar olib tashlanadi, tanlangan
yo'l qoladi.

**Rasm**

1. **Kichik ochish:** `CGImageSourceCreateThumbnailAtIndex` (`ThumbnailMaxPixelSize`, `FromImageAlways`) bilan
   to'g'ridan-to'g'ri ~720 px enida — to'liq o'lchamli bitmap yaratilmaydi.
2. **Klaviatura qismini kesish:** klaviatura ko'rinishda va yopilishda `SharedState.keyboardFrame`
   (`{visible, heightPt, screenHeightPt}`) yozadi. Intent pastki `heightPt / screenHeightPt` qismni kesadi —
   **faqat** klaviatura ko'rinayotgan deb yozilgan **va** skrinshotda ✨ tugmasining urg'u rangi kutilgan joyda
   (panelning o'ng tomoni) topilgan bo'lsa. Aks holda kesilmaydi: eskirgan holat tufayli eng so'nggi xabarlar
   kesilib ketmasligi kerak. Status bar — klaviatura oynasining `safeAreaInsets.top` ishonchli bo'lsa.
3. **HEIC:** `image/heic` (apparat kodlovchi); kodlab bo'lmasa — JPEG.

**Bitta yuklash**

4. `streamGenerateContent?alt=sse`, bitta so'rov: sxemada `propertyOrdering` bilan `partner, language, tone,
   last_incoming_uz, summary_uz, transcript, suggestions`. `StreamingFields` — kelayotgan JSON matnidan yopilgan
   yuqori darajadagi satr maydonlarini (escape'larni hisobga olib) ajratadi; birinchi to'rttasi tayyor bo'lishi
   bilan `onQuickRead`. Oxirida to'liq JSON bitta turga dekodlanadi. Unit testlar: bo'lingan chunklar, escape,
   Unicode. Birinchi tarjima vaqti ikki so'rovli sxemadan > 10% sekin bo'lsa — ikki so'rov qoladi.

**Ulanish**

5. So'rovlarda `assumesHTTP3Capable = true`; umumiy `URLSession` (`waitsForConnectivity = false`).
6. **Oldindan ulanish** — `Gemini.warmUp()` (kalitsiz yengil so'rov o'sha host va sessiyaga): intent'da rasm
   tayyorlanishi bilan parallel; klaviaturada — AI ishlay oladigan bo'lsa (Full Access + kalit) va qoralama 3
   belgiga yetganda, ko'pi bilan 4 daqiqada bir marta. Batareya/tezlik murosasi S5'da o'lchanadi.

**Kechikish dumi**

7. **Zaxira modelga parallel so'rov** (Android bilan bir xil): asosiy model rasm uchun 5 s, ✨ uchun 3 s ichida
   javob bermasa yoki qayta uriniladigan xato (429/5xx/timeout/tarmoq/bo'sh) bersa, zaxira model parallel
   ishga tushadi; birinchi muvaffaqiyatli javob olinadi, qolgani bekor qilinadi. Umumiy chegara: ✨ 20 s,
   tahlil 30 s.
8. `maxOutputTokens`: quick 256, details 1024, rewrite 512 (M4'da aniqlashtiriladi). Tajriba: `mediaResolution`
   pastroq — chat matni aniq o'qilishi sharti bilan.
9. **Shartli:** S5 ilovaning sovuq ishga tushishi katta ulush ekanini ko'rsatsa — intent App Intents
   kengaytmasiga (yengilroq jarayon) ko'chiriladi.

Mezon: mobil internetda birinchi tarjima ≥ 30% tezroq, Back Tap boshiga yuklangan bayt ≥ 60% kam.

## Xavflar

| Xavf | Chora |
|---|---|
| Diagnostika o'lchovni buzadi | Taymer/oqimsiz dizayn; S2/S3 diagnostika o'chiq holda ham o'lchanadi |
| `textContentType` belgisi klaviaturaga yetmaydi | Maydon xususiyatlari kombinatsiyasi bilan zaxira belgi |
| iOS 27'da `delaysTouchesBegan` usuli ishlamaydi | Minimal test klaviatura bilan tasdiqlash, Feedback; muammo bizda emasligi hisobotda aniq yoziladi |
| Kesish eng so'nggi xabarlarni kesib yuboradi | Ikki shart (yozilgan holat + ✨ rangi skrinshotda); shubha bo'lsa kesilmaydi |
| Oqimli JSON tahlili nozik | Bayroq ortida, unit testlar; natija yomon bo'lsa ikki so'rovga qaytiladi |
| Oldindan ulanish batareyani oshiradi | Cheklangan (3 belgi, 4 daqiqa), S5'da o'lchanadi, foydasi bo'lmasa o'chiriladi |

## Maxfiylik

- Diagnostika harf va matnni yozmaydi; oddiy chatlarda faqat hisoblagichlar, batafsil jurnal faqat ilovaning
  test maydonida.
- `diagnostics.json` faqat App Group'da; tashqariga faqat foydalanuvchi eksport qilganda yoki Mac'ga ulangan
  telefondan men olganimda chiqadi.
- M2'da haqiqiy suhbatlar ishlatilmaydi (Saved Messages, tayyor matnlar).

## Sinov

- M1: `AIKeyboardTests` (TouchTracker, muddatlar, solishtirish, xulosa) + Simulator'da qo'lda.
- M2: o'lchov protokolining o'zi.
- M3: har tuzatish uchun M2 stsenariysi qayta; mantiq tuzatishlari uchun regressiya testi.
- M4: `StreamingFields`, kesish qarori, hedging mantig'i uchun unit testlar; S5 bilan oldin/keyin.

## Doiradan tashqari (keyinroq)

- Android'dagi mos o'zgarishlar (oqimli bitta so'rov, hedging allaqachon bor).
- Cloudflare Worker proksi (kalitni yashirish; tarmoq kechikishiga ta'siri alohida o'lchanadi).
- TestFlight/App Store va Xcode Organizer'dagi energiya/hang hisobotlari, MetricKit (to'lovli Apple Developer
  akkaunti kerak).
- iPad joylashuvi.
