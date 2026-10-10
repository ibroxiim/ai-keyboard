# AI Keyboard — iPhone: o'zbekcha ovozdan matn (dizayn)

Sana: 2026-10-10 · Holat: tasdiqlangan dizayn, implementatsiya rejasi keyingi qadam

## Maqsad

O'zbek tilida gapirib matn kiritish: klaviaturadagi 🎤 bosiladi, foydalanuvchi o'zbekcha gapiradi, matn kursor joyiga
tushadi (lotin yozuvida). Keyin odatdagidek ✨ uni do'stning tiliga o'giradi. Maqsad — telefonda uzun o'zbekcha
xabarni yozmasdan aytib turish.

## Nima uchun shunday

- **Apple o'zbekchani tanimaydi.** 2026-10-10 da tekshirildi: `SFSpeechRecognizer.supportedLocales()` (62 til) va yangi
  `SpeechTranscriber.supportedLocales` (45 til) ro'yxatida `uz` yo'q (turk va rus bor). Tizim diktovkasi o'zbekcha
  ishlamaydi — tashqi dvigatel kerak.
- **Gemini audio'ni yaxshi o'qiydi.** Uchta o'zbekcha gap (Gemini TTS bilan yaratilgan toza ovoz) → `3.5-flash`:
  100% (3/3), `3.5-flash-lite`: 100/82/100% (raqamni "9:00" deb yozdi), `3.6-flash`: 80–90% ("Salom" o'rniga
  "Salam"); 8–10 soniyalik audioga 1.3–2 s. Bu sun'iy ovoz — haqiqiy ovozdagi aniqlik telefonda o'lchanadi.
- **iPhone klaviaturasi mikrofondan foydalana olmaydi** (Apple qoidasi). Yozib olishni asosiy ilova qiladi.

Qarorlar:

| Savol | Qaror |
|---|---|
| Platforma | Avval iPhone (Android — to'g'ridan-to'g'ri mikrofon, Mac — tezkor tugmani bosib turib gapirish: keyinroq) |
| Oqim | Klaviaturada 🎤 → ilova ochilib yozadi → foydalanuvchi chatga qaytadi, yozuv fonda davom etadi → klaviaturada ⏹ → matn kursor joyiga tushadi |
| Zaxira yo'l | Ilovada alohida "Gapirish" ekrani; natija klaviaturadagi "🎤 Qo'yish" tugmasi orqali maydonga qo'yiladi |
| Dvigatel | Gemini audio (AAC 16 kHz mono), mavjud modellar zanjiri `Hedge` bilan |
| Yozuv | Lotin yozuvi; boshqa tildagi so'zlar (inglizcha, ruscha) aytilganidek qoladi; tarjima qilinmaydi |
| Maxsus | Maksimum 90 soniya; audio transkripsiyadan keyin o'chiriladi |

## Oqim

1. Klaviaturada ✨ yonida 🎤 tugmasi. Bosilsa: klaviatura yangi `id` (UUID) yaratadi va `aikeyboard://voice?id=<id>`
   ni ochadi. Full Access o'chiq bo'lsa — ✨ dagidek tushuntirish xabari.
2. Ilova ochiladi (`onOpenURL`) va **"Gapirish"** ekranini ko'rsatadi: katta mikrofon, taymer, "Chatga qayting —
   yozuv davom etadi (pastki chekka bo'ylab suring)" yo'riqnomasi, To'xtatish tugmasi. Yozuv boshlanishi bilan holat
   `recording` bo'ladi.
3. Foydalanuvchi chatga qaytadi (iOS yozuvni fonda ushlab turadi, to'q sariq mikrofon nuqtasi ko'rinib turadi).
   Klaviaturada status "🔴 Yozilmoqda" va 🎤 o'rnida ⏹.
4. ⏹ bosilsa (yoki ilovaning To'xtatish tugmasi, yoki 90 s): yozuv to'xtaydi, holat `transcribing`, klaviaturada "…".
5. Ilova audio'ni Gemini'ga yuboradi; natija `done` + matn. Klaviatura `id` mos kelganini ko'rib matnni **kursor
   joyiga** qo'shadi (matn oldidan bo'shliq, agar kerak bo'lsa) va holatni tozalaydi.

`id` mos kelmasa (boshqa klaviatura nusxasi, ilova qo'lda ochilgan, klaviatura yopilgan edi) — matn avtomatik
qo'yilmaydi (noto'g'ri maydonga tushmasligi uchun): klaviaturada "🎤 Ovozli matn tayyor — qo'yish" tugmasi chiqadi,
bosilsa qo'yiladi.

## Holat (`SharedState.voice`)

```swift
struct VoiceState: Codable, Equatable {
    enum Phase: String, Codable { case recording, transcribing, done, failed }
    var id: String
    var phase: Phase
    var since: Date          // joriy bosqich boshlangan vaqt
    var text: String?        // done
    var error: String?       // failed
}
```

Muddatlar (sof funksiyalar, `now` bo'yicha, `nextDeadline` ga qo'shiladi — spinner/xato qatoridagidek): `recording` 100 s
dan keyin, `transcribing` 60 s dan keyin eskirgan hisoblanadi (ilova o'ldirilgan) va bo'sh holat sifatida ko'rinadi;
`done` natija 10 daqiqa, `failed` 2 daqiqa ko'rinadi. Klaviatura 🎤 bosganda "ochilmoqda" holatini o'zida saqlaydi
(`pendingVoiceID`); 6 soniyada `recording` kelmasa: "Ilova ochilmadi — AI Keyboard ilovasini oching → Gapirish".

## Ilova tomoni

- **`VoiceRecorder`** (`@MainActor`): `AVAudioSession` (`.record`) foreground'da faollashtiriladi; `AVAudioRecorder`
  AAC (`kAudioFormatMPEG4AAC`), 16 000 Hz, 1 kanal, ~32 kbit/s, fayl `tmp/` da (App Group'ga yozilmaydi). 90 s
  taymeri; uzilish (qo'ng'iroq, boshqa ilova audio'si) → shu paytgacha yozilgani bilan to'xtatiladi.
- **To'xtatish manbalari:** ekrandagi tugma, 90 s, uzilish, klaviaturadan Darwin bildirishnomasi
  (`AppGroup.voiceStopRequested`); ilova fonda ishlab turgani uchun u yetib keladi.
- **`VoiceScreen`** (SwiftUI sheet): yuqoridagi holatlar; natija matni, "Nusxa olish", "Qayta yozish". `ContentView`
  da qo'lda ochuvchi "Gapirish" qatori ham bor (zaxira yo'l).
- **Transkripsiya:** `Translator.transcribe(audio:)` → `Gemini.generate` (`Part.audio`, JSON sxema `{ "text": … }`).
  Prompt: "Siz o'zbekcha gapiruvchining qisqa ovozli xabarini yozasiz. Aytilganini aynan, o'zbek lotin yozuvida
  (oʻ/gʻ uchun '), tabiiy tinish belgilari bilan yozing. Boshqa tildagi so'zlarni aytilganidek qoldiring. Tarjima
  qilmang, qisqartirmang, hech narsa qo'shmang. Nutq bo'lmasa — bo'sh satr."
- **Loyiha sozlamalari** (`ios/project.yml`): `NSMicrophoneUsageDescription`, `UIBackgroundModes: [audio]`,
  `CFBundleURLTypes` (`aikeyboard`). Pullik akkaunt kerak emas.

## Klaviatura tomoni

- 🎤 tugmasi (`mic.fill`, 36×30 kapsula) ✨ yonida; yozuv paytida qizil ⏹, transkripsiya paytida spinner.
- Status qatori: `recording` — "🔴 Yozilmoqda — tugagach ⏹"; `transcribing` — "Matn yozilmoqda…"; `failed` — xato
  matni (qizil); tayyor-lekin-qo'yilmagan — "🎤 Ovozli matn tayyor — qo'yish". Taymer tiklanmaydi (batareya): faqat
  holat matni; qolgan vaqt ilova ekranida.
- **Ilovani ochish:** klaviatura `UIApplication` ni responder zanjiridan topadi va `openURL:options:completionHandler:`
  ni selektor orqali chaqiradi (`UIApplication.shared` kengaytmalarda taqiqlangan). Bu Apple hujjatlashtirmagan
  yo'l — iOS 27'da ishlashi telefonda tekshiriladi.
- Matn qo'yish: `textDocumentProxy.insertText`. Yozib bo'lgach klaviatura ko'rinmasa — natija `done` holatida
  qoladi (10 daqiqa), keyingi ko'rinishda "qo'yish" tugmasi chiqadi.

## Xatolar

- Mikrofon ruxsati yo'q → ilova ekrani Settings'ga havola bilan tushuntiradi; klaviaturada `failed` + matn.
- Kalit yo'q yoki barcha modellar xato (zanjir tugagach) → `failed`, ilova ekranida "Qayta urinish" (audio hali o'chmagan).
- Bo'sh natija ("nutq topilmadi") → `failed` "Ovoz eshitilmadi".
- Ilova yozuv paytida o'ldirilsa → `recording` 100 s dan keyin eskiradi, klaviatura odatdagi holatga qaytadi.

## Maxfiylik

- Mikrofon faqat 🎤 yoki "Gapirish" tugmasi bosilganda yoqiladi; iOS to'q sariq nuqta ko'rsatadi; 90 s chegarasi.
- Audio faqat `tmp/` da; transkripsiyadan keyin (muvaffaqiyatda ham, xatoda ham, "Qayta urinish" bo'lmasa) darhol o'chiriladi.
  Audio faqat Gemini'ga yuboriladi (skrinshotdagidek), logga yozilmaydi; transkript matni log'ga tushmaydi.
- Natija matni App Group holatida 10 daqiqa turadi va qo'yilgach tozalanadi.

## Sinash

- **Unit testlar** (mikrofonsiz): `VoiceState` muddatlari va `nextDeadline`, "id mos keladi → avtomatik qo'yish /
  mos kelmaydi → tugma" qarori, qo'yiladigan matnni tayyorlash (bo'shliq qoidasi), `Gemini.Part.audio` JSON shakli,
  transkripsiya javobini ochish (bo'sh matn → xato).
- **Telefonda qo'lda:** (1) ilovada "Gapirish" → haqiqiy ovoz bilan aniqlik; (2) klaviaturadan 🎤 → ilova ochilishi;
  (3) chatga qaytgach yozuv davom etishi; (4) ⏹ → matn tushishi. Haqiqiy aniqlik uchun foydalanuvchining ovozli
  xabari (Voice Memos) ham `devicectl`/AirDrop bilan olinadi.

## Bosqichlar

| Bosqich | Mazmun |
|---|---|
| **M1** | Ilova tomoni (recorder, transkripsiya, "Gapirish" ekrani, URL sxema, holat) va klaviatura tomoni (🎤, status, ochish, qo'yish), unit testlar; telefonda 1–4 tekshiruv |
| **M2** | Natijaga qarab: ochish usuli ishlamasa — faqat zaxira yo'l; yozuv taymeri, uzilishlar, kirill yozuvi tanlovi, ✨ ni to'g'ridan-to'g'ri ovozdan |

## Xavflar

| Xavf | Chora |
|---|---|
| iOS 27'da klaviaturadan ilovani ochish usuli ishlamasligi | M1 da birinchi tekshiriladi; zaxira yo'l (ekran + "Qo'yish" tugmasi) to'liq ishlaydi |
| Chatga qaytgach yozuv to'xtab qolishi (fon cheklovi) | `audio` fon rejimi + foreground'da faollashtirilgan sessiya; telefonda tekshiriladi, aks holda yozuv ilova ochiq turgandagina |
| Haqiqiy ovozda (shovqin, tez nutq) aniqlik past | Telefonda o'lchanadi; modellar zanjiri; M2 da tahrir imkoni |
| Raqam/so'z imlosi ("9:00" yoki "to'qqiz") | Prompt qoidasi sinovdan keyin aniqlashtiriladi |
| Bepul imzoda qayta o'rnatishda mikrofon ruxsati tushib ketishi | Yangi o'rnatishda bir marta qayta so'raladi, odatiy holat |

## Doiradan tashqari (keyinroq)

- Android (klaviaturadan to'g'ridan-to'g'ri mikrofon) va Mac (tezkor tugmani bosib turib gapirish).
- Jonli (oqimli) transkripsiya: `gemini-3.5-transcribe-live`; ovozdan darhol do'st tiliga: `gemini-3.5-live-translate-preview`.
- Kirill yozuvida natija, so'zlarni tuzatish lug'ati.
