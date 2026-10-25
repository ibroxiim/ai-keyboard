# AI Keyboard — iPhone: tarjima sifati va suhbat xotirasi (dizayn)

Sana: 2026-10-15 · Holat: yo'nalish tasdiqlangan (foydalanuvchi to'rtala taklifni ma'qulladi), mayda qarorlar quyida

## Muammo

Foydalanuvchi Gemini ilovasida yillar davomida bitta tarjima sessiyasidan foydalangan; birinchi ko'rsatma —
"chiroyli qilib tarjima qilib ber". Klaviaturadagi tarjima undan yomonroq:

1. **Faqat oxirgi xabar tarjima bo'ladi.** Do'st 6 ta xabarni ketma-ket yuborsa, skrinshotdan keyin oxirgisi chiqadi.
   Sabab kodda: `quickSystem` "latest message(s)" deydi (ikki ma'noli), `detailsSystem` esa transkriptni 6 ta
   xabar bilan cheklaydi.
2. **So'zma-so'z, "Google Translate" uslubi.** Hozir hech qanday uslub ko'rsatmasi yo'q; birinchi model Flash-Lite,
   fikrlash `minimal`, eng tez javob bergan yutadi (`Hedge`).
3. **Xotira yo'q.** Gemini sessiyasi har xabarda butun tarixni qayta yuboradi (avvalgi ko'rsatmalar, ismlar, uslub).
   Bizda har so'rov noldan boshlanadi. ✨ uchun skrinshot 15 daqiqada eskiradi, keyin faqat "ohang" qoladi.
4. **Muloqot darajasi.** Koreys (반말/존댓말), rus (ты/вы), turk (sen/siz) tillarida ✨ ba'zan do'stga haddan tashqari
   rasmiy yozadi.

Sinov (2026-10-15, 10 ta to'qima xabar): Flash-Lite oddiy gaplarda yaxshi, lekin idiomada adashadi ("the other day" →
"kecha"). Kuchliroq Flash modellar o'sha kuni 6–47 s javob berdi va 429 qaytardi, shuning uchun faqat modelni
almashtirish yechim emas.

## Qarorlar

### A. Butun javobsiz qism tarjimasi (M1)

- `last_incoming_uz`: "them" ning **oxirgi "me" xabaridan keyingi barcha xabarlari**, tartib bilan, har xabar alohida
  qatorda. Birortasini tashlash yoki qo'shib yuborish taqiqlanadi.
- Transkript chegarasi 6 → 12 xabar (xotira va ✨ konteksti uchun).
- Klaviaturadagi bir qatorli xulosada qatorlar " · " bilan ulanadi; kartochka tafsilotida (`ContextDetails`) va
  Shortcut dialogida alohida qatorlar.

### B. Tarjima uslubi (M1)

- Asosiy qoida doim promptda: tabiiy, ravon, og'zaki o'zbekcha — "do'sting og'zaki tushuntirgandek", so'zma-so'z
  emas; ma'no, ohang, emoji, raqam va ismlar saqlanadi; to'qima sleng yo'q.
- Ilovada **"Tarjima uslubi"** matn maydoni (ixtiyoriy, 500 belgigacha): foydalanuvchi Gemini sessiyasidagi
  ko'rsatmasini shu yerga qo'yadi. Prompt'ga "foydalanuvchining o'z ko'rsatmasi" sifatida qo'shiladi (tarjima va ✨ ikkalasi).

### C. Muloqot darajasi (M1)

- `tone` tavsifi endi tilning gap darajasini ham o'z ichiga oladi (Korean 반말/존댓말, Russian ты/вы, Turkish sen/siz,
  Japanese casual/polite). Bu `Friend.tone` orqali ✨ ga yetadi.
- ✨ qoidasi: do'st/yaqin xabarlar darajasiga mos yoz; chat rasmiy bo'lmasa eng rasmiy shaklni tanlama.
- Ilovadagi do'stlar ro'yxatida har do'st uchun qo'lda **Avto / Norasmiy / Rasmiy** tanlovi (`Friend.formality`).
  Qo'lda tanlangan qiymat yangi skrinshotlarda saqlanib qoladi va ✨ ga "user's choice" sifatida beriladi.

### D. Do'st bo'yicha suhbat xotirasi (M2)

- `Friend.history: [ChatAnalysis.Line]?` — shu do'st bilan skrinshotlardan yig'ilgan oxirgi **40** xabar (eskidan yangiga).
- Yangi transkript tarixga **ustma-ust tushgan joyidan** qo'shiladi: tarixning oxiridagi `k` qator yangi transkriptning
  boshidagi `k` qatorga teng bo'lsa (harf-raqamga normallangan, harf registri hisobga olinmaydi), faqat qolgani
  qo'shiladi; to'liq ichida bo'lsa — o'zgarmaydi; umuman mos kelmasa — yangi deb qo'shiladi.
- ✨ uchun kontekst: do'stning tarixi (oxirgi 20 qator). Skrinshot yangi bo'lsa tarix uning ustiga qurilgan; eskirgan
  bo'lsa ham klaviatura "qaysi suhbat, nima haqida" ni biladi (prompt'da "oldingi skrinshotlardan, eng yangisi bo'lmasligi mumkin").
- Skrinshotni tahlil qilish so'rovlariga (tarjima, takliflar) tarix **berilmaydi**: do'st ismi aynan shu so'rovda
  aniqlanadi, tarixni tanlash uchun undan oldin ma'lum bo'lishi kerak edi. Skrinshotning o'zi yaqin kontekstni beradi.
- **Maxfiylik:** faqat qurilmada (App Group), Gemini'ga faqat ✨ so'rovi bilan, o'sha do'st uchun yuboriladi.
  Do'stni o'chirish tarixini ham o'chiradi. Ilovada "Suhbat xotirasi" tugmasi (standart: yoqilgan); o'chirilsa
  mavjud tarix tozalanadi va yangisi yig'ilmaydi.

### E. Sifatli rejim (M3)

- Ilovada "Sifatli tarjima (sekinroq)" tugmasi, standart **o'chiq**.
- Yoqilsa skrinshot tarjimasi va ✨ uchun: modellar tartibi `3.6-flash, 3.5-flash, 3.5-flash-lite, 3.1-flash-lite`,
  `thinkingLevel: low`, `Hedge` kutish vaqti 2×, so'rov vaqt chegarasi 30 s. Ovozdan matn o'zgarmaydi.
- Rejim qiymatini baholash foydalanuvchining o'zida: haqiqiy suhbatlarda yoqib sinab ko'riladi (yuqoridagi sinovda
  kuchli Flash modellar aniq yaxshi chiqmagan, shuning uchun va'da berilmaydi).

### F. Do'st bo'yicha ko'rsatma, kattaroq limit, fayldan yuklash (2026-10-25)

- Umumiy "Tarjima uslubi" **qanday tarjima qilish**ni aytadi; har do'stning **"Ko'rsatma"**si (`Friend.notes`) esa
  **bu odam bilan qanday gaplashaman**ni: "sinfdoshim, hazil aralash", "sen deb gapiramiz".
- Kelgan xabar tarjimasida do'st o'sha so'rovning o'zida aniqlanadi, shuning uchun skrinshot so'rovlariga (tarjima
  ham, takliflar ham) **barcha tanish do'stlarning** ko'rsatmalari ism bilan yuboriladi (`Prompts.knownFriendsPart`),
  model topgan do'stnikini qo'llaydi. ✨ da do'st oldindan ma'lum — faqat uniki ketadi.
- Limit 500 → 4000 → **12 000 belgi** (≈3000 token; 2026-10-25 kechqurun: Gemini o'z uslubini yozib berganda 4000
  ga sig'madi), umumiy va har do'st uchun alohida. Skrinshot so'rovida hamma do'stning ko'rsatmasi **jami 24 000
  belgi**gacha (eng yaqinda yozishganlardan boshlab, `Prompts.friendNotesBudget`). Cheksiz emas: har so'rovga
  qo'shiladi, kattasi javobni sekinlashtiradi va asosiy qoidalarni suyultiradi.
- Ilovada to'liq ekranli muharrir (`InstructionsEditor`): hisoblagich, "Fayldan yuklash" (Files: .md/.txt, matn
  maydonga **ko'chiriladi**, fayl bog'lanmaydi — nima yuborilayotgani doim ko'rinib turadi), "Tozalash". Saqlash
  ekrandan chiqilganda yoki ilova fonga ketganda (har harfda emas — har saqlash klaviaturani uyg'otadi).
- Do'st ekrani (`FriendDetailView`): til/ohang, daraja, ko'rsatma, xotira soni + tozalash, o'chirish. Ro'yxatdagi
  inline daraja menyusi olib tashlandi.
- Maslahat (ilovadagi izohda ham): sifatlardan ko'ra **«asl → yaxshi tarjima» misollari** kuchliroq; Gemini
  sessiyasini Google Docs'ga eksport qilib, undan 15–20 misol olinadi — shu MD fayl bo'ladi.

## O'zgarishlar xaritasi

| Fayl | O'zgarish |
|---|---|
| `Shared/Translator.swift` (`Prompts`) | yangi `quickSystem` (A, B, C), `detailsSystem` (12 xabar, ohang), `rewriteSystem` (C), `rewriteInput` (tarix, daraja, uslub) |
| `Shared/Models.swift` | `lastIncomingUz` ko'p qatorli; transkript 12 |
| `Shared/SharedStore.swift` | `SharedState.translationStyle`, `rememberChats`, `qualityMode`; `Friend.formality`, `Friend.history`; `remember()` ularni saqlaydi |
| `Shared/ChatHistory.swift` (yangi) | ustma-ust birlashtirish (sof mantiq, testlanadi) |
| `Shared/Gemini.swift` | `Quality` (.fast/.careful) |
| `Shared/Prompts.swift` (yangi, `Translator.swift`dan ajratildi) | prompt'lar sof mantiq bo'lib testlanadi |
| `App/ContentView.swift` | uslub (muharrirga havola), tugmalar, do'stlar ro'yxati → do'st ekrani |
| `App/InstructionsEditor.swift`, `App/InstructionsImport.swift`, `App/FriendDetailView.swift` (yangi) | muharrir, fayl o'qish (sof mantiq, testlanadi), do'st ekrani |
| `Keyboard/KeyboardModel.swift`, `KeyboardView.swift` | ✨ ga uslub, tarix, daraja; ko'p qatorli xulosa |

## Sinash

- Unit testlar: `ChatHistory.merge` (ustma-ust, ichida, mos kelmaydi, OCR farqi, chegara), `Prompts` (uslub va
  daraja prompt'ga tushadi, bo'sh bo'lsa tushmaydi), `Friend.formality` yangi skrinshotda saqlanadi, `Quality`
  konfiguratsiyasi, eski `state.json` yuklanishi.
- Haqiqiy API bilan: `scratchpad`dagi 11 xabarlik to'plam (6 ta ketma-ket xabar holatlari bilan) eski va yangi
  prompt'ni solishtiradi; natijalar shu hujjatga qisqa yoziladi.
- Telefonda: 6 ta ketma-ket xabarli chat skrinshoti → kartochkada 6 qator; ✨ ni skrinshotsiz bosish → tarix bilan.

## Prompt sinovi (2026-10-15, Flash-Lite, 11 to'qima holat)

Holatlar: 8 ta bitta/ikki xabarli (EN, KO, RU) va 3 ta **5–6 ta ketma-ket xabarli** (EN, KO, RU).

| Konfiguratsiya | Natija |
|---|---|
| Eski prompt, `minimal` | Ketma-ket xabarlarni **bitta gapga qo'shib yuboradi**, ba'zilarini tashlaydi ("ok cool / wait" birlashdi); ba'zan qavs ichida ortiqcha izoh |
| Yangi prompt (A+B), `minimal` | 3/3 holatda **har xabar alohida qatorda**, hech biri tashlanmadi; ohang tabiiyroq; qavs izohlari kam |
| Yangi prompt, `low` | Yaxshilamadi, to'qima so'zlar chiqdi ("bratchi", "bor yo'qdan tinmaysan-a") → standart `minimal` qoladi |

Qolgan kamchiliklar: ba'zan `ʻ` va `'` aralashadi, bitta-ikkita g'alati so'z ("uchalikmas"). Bular "Tarjima uslubi"
va keyingi sinovlar bilan kuzatiladi.

## Qilinmaydi

- Gemini ilovasidagi sessiyani (uning tarixini) import qilish: bunday API yo'q.
- Skrinshot tahliliga tarix berish (yuqoridagi sabab bilan) — keyinroq, agar ism oldindan aniq bo'lsa.
- Android: mantiq ko'chiriladi, lekin bu bosqichda emas.
