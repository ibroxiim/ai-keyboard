# AI Keyboard — iPhone: GIF qidirish va yuborish (dizayn)

Sana: 2026-11-01 · Holat: tasdiqlangan, implementatsiya shu branch'da (faqat iOS; Android keyinroq)

## Maqsad

Klaviaturadan chiqmasdan GIF topib yuborish — Gboard'dagidek. Manba: **KLIPY GIF API v1**. Dastlab Tenor
mo'ljallangan edi, lekin Google Tenor API'ni **2026-06-30 da yopgan** (yangi kalit berilmaydi, eskilari xato
qaytaradi); KLIPY o'zini Tenor'ning o'rnini bosuvchi deb taqdim etadi. Kalit `Secrets.klipyAPIKey` (gitignore'da),
Partner Panel'dan: test kaliti soatiga 100 so'rov, production — forma orqali. Google rasm qidiruvining API'si yo'q.

KLIPY talablari: media faqat ularning URL'idan (qayta joylash yo'q — bizda faqat sessiya ichidagi `NSCache`),
natijalar berilgan tartibda, KLIPY nomi natijalar yonida (qidiruv qatorida "GIF / KLIPY").

## Oqim

1. Bo'sh holatda status qatorida **GIF** tugmasi (✨ → til tugmasi yonida). Full Access shart (tarmoq + nusxa taxtasi).
2. Bosilsa bar o'rnida **qidiruv qatori + 118 pt GIF tasmasi** ochiladi, klaviatura shunga qarab o'sadi
   (`KeyboardMetrics.BarMode.gif`). Tugmalar joyida qoladi va **qidiruvga yozadi** (`type/backspace/space` →
   `gifQuery`; return → qidiruv). Klaviatura o'zining maydoniga klaviatura chaqira olmaydi, shuning uchun shunday.
3. Bo'sh so'rovda `gifs/trending`, yozganda har pauzadan 350 ms keyin `gifs/search` (so'rov har harfda emas);
   `content_filter=medium`, `format_filter=gif`, `per_page=20`. Kalit URL yo'lida: `/api/v1/{key}/gifs/…`.
4. Tasmada `file.sm.gif` (≈220 px) animatsiyali ko'rinadi — `CGAnimateImageDataWithBlock` kadrlarni birma-bir dekodlaydi,
   10 ta GIF xotirada 10 ta kadr turadi (kengaytma xotirasi kichik). Yuklanganlar `NSCache`da.
5. GIF bosilsa `file.md.gif` (498 px, ~3–4 MB) yuklanadi, `UIPasteboard`ga `com.compuserve.gif` sifatida qo'yiladi, panel yopiladi va
   6 s: «GIF nusxalandi — maydonni bosib turib Paste ni bosing». iOS klaviaturaga rasmni maydonga qo'yishga
   ruxsat bermaydi — Gboard ham shunday ikki qadam.

## Qilinmaydi / keyinroq

- Google rasm qidiruvi (API yo'q). GIPHY — Tenor yetarli.
- KLIPY `share/{slug}` (reyting uchun) — keyin.
- Android: `commitContent` orqali to'g'ridan-to'g'ri yuborish — alohida bosqich.

## Sinash

Unit: `Klipy.parse` (ikkala format bo'lmagan natija tashlanadi), URL (q, featured, filterlar), xato matnlari,
`KeyboardMetrics` balandliklari. Simulator (Full Access yoqilgan): tugma, panel, yozish qidiruvga ketishi, kalit
bo'lmasa xabar; kalit bilan — haqiqiy qidiruv va nusxalash (Pasteboard'da `public.gif`/`com.compuserve.gif`).

### 2026-11-01 sinov natijasi (iPhone 17 Simulator, haqiqiy KLIPY kaliti)

- Trending va qidiruv («cat») ishladi: tasma animatsiyali GIF'lar bilan to'ldi, tugmalar qidiruv maydoniga yozdi.
- Topilgan xato: GIF bosilganda hech narsa bo'lmasdi. Sabab — `Button` yorlig'i `UIViewRepresentable` (`UIImageView`)
  bo'lsa, SwiftUI bosishni tugmaga yetkazmaydi. Yechim: `AnimatedGifView` ga `.allowsHitTesting(false)`, yorliqqa
  `.contentShape(...)`, `GifImageView`da `isUserInteractionEnabled = false`. Shundan keyin «GIF nusxalandi» xabari
  chiqdi va panel yopildi. `file.md.gif` ≈ 270 KB, 0.4 s da yuklanadi.
- Kalitni fayl orqali emas, terminalda ko'rinmas kiritish uchun `ios/tools/set-klipy-key.sh`.
