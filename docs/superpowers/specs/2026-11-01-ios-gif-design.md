# AI Keyboard — iPhone: GIF qidirish va yuborish (dizayn)

Sana: 2026-11-01 · Holat: tasdiqlangan, implementatsiya shu branch'da (faqat iOS; Android keyinroq)

## Maqsad

Klaviaturadan chiqmasdan GIF topib yuborish — Gboard'dagidek. Manba: **Tenor v2** (Google'ning GIF xizmati;
Google rasm qidiruvining API'si yo'q). Kalit `Secrets.tenorAPIKey` (gitignore'da), bepul, Google Cloud'dan.

## Oqim

1. Bo'sh holatda status qatorida **GIF** tugmasi (✨ → til tugmasi yonida). Full Access shart (tarmoq + nusxa taxtasi).
2. Bosilsa bar o'rnida **qidiruv qatori + 118 pt GIF tasmasi** ochiladi, klaviatura shunga qarab o'sadi
   (`KeyboardMetrics.BarMode.gif`). Tugmalar joyida qoladi va **qidiruvga yozadi** (`type/backspace/space` →
   `gifQuery`; return → qidiruv). Klaviatura o'zining maydoniga klaviatura chaqira olmaydi, shuning uchun shunday.
3. Bo'sh so'rovda `featured` (trend), yozganda har pauzadan 350 ms keyin `search` (so'rov har harfda emas).
4. Tasmada `tinygif` (≈220 px) animatsiyali ko'rinadi — `CGAnimateImageDataWithBlock` kadrlarni birma-bir dekodlaydi,
   10 ta GIF xotirada 10 ta kadr turadi (kengaytma xotirasi kichik). Yuklanganlar `NSCache`da.
5. GIF bosilsa to'liq `gif` yuklanadi, `UIPasteboard`ga `com.compuserve.gif` sifatida qo'yiladi, panel yopiladi va
   6 s: «GIF nusxalandi — maydonni bosib turib Paste ni bosing». iOS klaviaturaga rasmni maydonga qo'yishga
   ruxsat bermaydi — Gboard ham shunday ikki qadam.

## Qilinmaydi / keyinroq

- Google rasm qidiruvi (API yo'q). GIPHY — Tenor yetarli.
- Tenor `registershare` (reyting uchun) — keyin.
- Android: `commitContent` orqali to'g'ridan-to'g'ri yuborish — alohida bosqich.

## Sinash

Unit: `Tenor.parse` (ikkala format bo'lmagan natija tashlanadi), URL (q, featured, filterlar), xato matnlari,
`KeyboardMetrics` balandliklari. Simulator (Full Access yoqilgan): tugma, panel, yozish qidiruvga ketishi, kalit
bo'lmasa xabar; kalit bilan — haqiqiy qidiruv va nusxalash (Pasteboard'da `public.gif`/`com.compuserve.gif`).
