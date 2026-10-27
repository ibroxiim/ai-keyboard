# AI Keyboard — iPhone: ✨ sozlash, tuzatishlardan o'rganish, 📋 nusxadan tarjima (dizayn)

Sana: 2026-10-27 · Holat: foydalanuvchi tasdiqlagan, implementatsiya shu branch'da

Gemini ilovasidagi sessiya nega yaxshi: (1) "biroz yumshoqroq qil" deb qayta so'rash mumkin, (2) u foydalanuvchi
tuzatishlarini eslab qoladi. Klaviaturada ikkalasi ham yo'q edi. Uchinchisi — skrinshotsiz, aniq matn bilan tarjima.

## A. ✨ sozlash tugmalari

- Variantlar chiqqach status qatorida to'rtta kichik tugma: **qisqaroq · iliqroq · rasmiyroq · hazil**
  (`RewriteTweak`: shorter/warmer/formal/playful). Bosilsa yoqiladi/o'chadi, bir nechtasi birga bo'lishi mumkin;
  har o'zgarishda o'sha qoralama uchun variantlar qayta so'raladi (`KeyboardModel.refine`).
- Prompt: `rewriteInput` ga `Adjust: shorter; warmer` qatori, `rewriteSystem` da "Adjust bo'lsa uchala variantga ham
  qo'lla" qoidasi. Tanlangan variant emas, **asl qoralama** qayta yoziladi — ma'no yo'qolmasin.
- Yangi variantlar kelganda tanlov belgisi tushadi; "↩︎ Asli" o'z joyida qoladi.

## B. Tuzatishlardan o'rganish (`Friend.examples`)

- Foydalanuvchi variantni tanlab, yuborishdan oldin qo'lda o'zgartirsa, maydon bo'shaganda (yuborildi) klaviatura
  **qoralama → taklif → yuborilgan** uchligini o'sha do'stga yozib qo'yadi (`EditLearning.example`, oxirgi 20 ta).
- Saqlanmaydi: o'zgarmagan tanlov; yuborilgan matn taklifning boshi yoki oxiri bo'lsa (host ilova
  `documentContext`ni qirqadi — bu tahrir emas); juda qisqa yoki bo'sh matn.
- ✨ so'roviga shu do'stning oxirgi 10 misoli "how the user changed earlier suggestions" sifatida ketadi.
- "Suhbat xotirasi" tugmasiga bo'ysunadi: o'chiq bo'lsa yig'ilmaydi va tozalanadi. Do'st ekranida soni va tozalash.
- Faqat telefonda; Gemini'ga faqat ✨ bilan, faqat shu do'st uchun.

## C. 📋 Nusxadan tarjima

- Full Access bo'lsa va nusxa taxtasida klaviatura oxirgi ko'rganidan **yangi** matn bo'lsa (`changeCount`),
  status qatorida "📋 Tarjima" tugmasi. Bosilsa matn o'qiladi (iOS "nusxa oldi" bannerini ko'rsatadi — normal),
  bitta Gemini so'rovi (`Prompts.clipboardSystem`): til, ohang, tarjima (har xabar/abzats alohida qatorda),
  qisqa xulosa, 3 javob. Natija `SharedState.context` ga yoziladi — tarjima qatori, kartochka, ✨ konteksti,
  do'st xotirasi o'z-o'zidan ishlaydi. Do'st = faol do'st (bo'lsa).
- Skrinshotdan farqi: OCR yo'q, matn aniq, ~1 s; faqat nusxa olingan qism (ko'pincha bitta xabar).
- Tugma bir marta ishlatilgach yoki yangi nusxa kelmaguncha ko'rinmaydi.

## D. O'qilishi (`Suggestion.read`)

- Lotin yoki kirillda yozilmaydigan tillar (koreys, yapon, xitoy, arab…) uchun har javob/variantga lotin
  transkripsiyasi: koreys — Revised Romanization, yapon — Hepburn, xitoy — ohangli pinyin. Boshqa tillarda maydon yo'q.
- Chipda ikkinchi qatorda "o'qilishi · ma'nosi", to'liq ro'yxatda alohida kursiv qator. Sxemada ixtiyoriy —
  eski saqlangan holat o'zgarishsiz yuklanadi.

## Qilinmaydi: oqimli (streaming) javob

2026-10-27 sinovi: `streamGenerateContent?alt=sse` (Flash-Lite, JSON) — butun javob 38 s kutildi, keyin barcha
bo'laklar 0,16 s ichida keldi. Tarjima ~50 token, Flash-Lite ularni ~0,2 s da yozadi: kechikish birinchi tokengacha
bo'lgan vaqtda, oqimli ko'rsatish eng ko'pi bilan ~0,2 s "his" beradi. Buning uchun SSE o'qish, Hedge'dagi ikki
modelning oqimini ajratish va App Group fayliga ko'p marta yozish kerak bo'lardi — foydasi narxini oqlamaydi.
Haqiqiy tezlik yo'li — model tanlovi (`Hedge`) va so'rov hajmi.

## Sinash

Unit: `RewriteTweak` prompt qatori; `EditLearning.example` qoidalari (o'zgarmagan, qirqilgan, haqiqiy tahrir,
chegara); `Friend.learn` 20 ta chegara va "xotira o'chiq" holati; `Prompts.clipboardSystem` asosiy qoidalar;
`ClipboardRead → ChatAnalysis`. Qolgani telefonda (Simulator'da Full Access yo'q).
