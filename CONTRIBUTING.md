# Hissa qo'shish

> **English:** Contributions are welcome! Fork the repo, work on a branch in your fork and open a Pull Request
> against `main` (direct pushes to `main` are blocked). Docs are in Uzbek, but issues and PRs in English are fine.

AI Keyboard'ni yaxshilashga yordam berganingiz uchun rahmat. Quyidagi qadamlar PR'ingiz tez ko'rib chiqilishi uchun.
Loyihadagi muloqot [Code of Conduct](CODE_OF_CONDUCT.md) qoidalariga amal qiladi.

## Qanday ishlaydi

1. Reponi **fork** qiling (`main`'ga to'g'ridan-to'g'ri push yopiq — o'zgarishlar faqat Pull Request orqali).
2. Fork'ingizda branch oching: `feature/qisqa-nom` yoki `fix/qisqa-nom`.
3. O'zgartiring, sinang, commit qiling.
4. `ibroxiim/ai-keyboard` ning `main` branchiga **Pull Request** oching. Shablon so'ragan maydonlarni to'ldiring.
5. Kamida bitta tasdiqdan va barcha izohlar yopilgandan keyin merge qilinadi.

Katta o'zgarish (yangi ekran, arxitektura) rejalashtirayotgan bo'lsangiz, avval **Issue** ochib fikringizni yozing —
keraksiz ishdan qutulasiz.

## Ishga tushirish

Kerak: Xcode (iOS 18+ SDK), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`),
Gemini API kaliti ([AI Studio](https://aistudio.google.com/apikey), bepul).

```bash
cd ios
cp Shared/Secrets.swift.example Shared/Secrets.swift   # o'z kalitingizni qo'ying
xcodegen generate
open AIKeyboard.xcodeproj
```

O'z iPhone'ingizda ishga tushirish uchun Apple akkauntingizga mos ID'lar kerak. Quyidagilarni **faqat lokal**
o'zgartiring va PR'ga qo'shmang:

- `ios/project.yml` — `DEVELOPMENT_TEAM`, ikkala `PRODUCT_BUNDLE_IDENTIFIER`, ikkala `com.apple.security.application-groups`
- `ios/Shared/SharedStore.swift` — `AppGroup.id`
- `ios/Shared/EnabledKeyboards.swift` — `aiKeyboardID` (klaviatura bundle ID'si)
- `ios/tools/make_shortcut.py` — `BUNDLE_ID`, `TEAM_ID` (keyin shortcut faylini qayta yarating, README'ga qarang)

`ios/Shared/Secrets.swift` gitignore'da — API kalitlar hech qachon commit qilinmaydi. GIF qidiruvi uchun
shu faylga `klipyAPIKey` ham qo'yiladi (KLIPY Partner Panel, https://klipy.com/developers — test kaliti soatiga
100 so'rov, production kaliti forma orqali; Google'ning Tenor API'si 2026-06-30 da yopilgan); bo'sh qolsa
klaviaturadagi GIF tugmasi buni aytadi, qolgani ishlayveradi. Kalitni qo'lda yozmasdan `ios/tools/set-klipy-key.sh`
bilan kiriting — terminalda ko'rinmaydi va shell tarixiga tushmaydi.

## Android

```bash
cd android
./gradlew :app:testDebugUnitTest      # JVM testlar (Gemini'ga murojaat qilmaydi)
./gradlew :app:assembleDebug          # app/build/outputs/apk/debug/app-debug.apk
LIVE_GEMINI=1 ./gradlew :app:testDebugUnitTest --tests '*GeminiLiveTest'   # haqiqiy Gemini (kalit local.properties'da)
```

Emulyatorda: `adb shell ime enable/set com.ibrokhim.aikeyboard/.ime.AiKeyboardService`, ilovadagi "Demo chat"da
📖 ni sinang. Android klaviaturasi iOS bilan bir xil AI imkoniyatlarga ega (tarjima qoidalari, ✨ sozlash tugmalari,
«↩︎ Asli», 📋 nusxadan tarjima, do'st ko'rsatmasi va xotirasi, o'qilish) — prompt va ma'lumot mantig'i ikki tomonda
qo'lda bir xil saqlanadi: `ios/Shared/Prompts.swift` ↔ `android/.../ai/Prompts.kt`. Birini o'zgartirsangiz,
ikkinchisini ham o'zgartiring. Debug build `AIKeys` logcat tegida tugma koordinatalarini yozadi — `android/tools/adb-type.py "matn"`
ular orqali matnni tugmalar bilan yozadi. Kod va testlarda faqat to'qima ismlar va suhbatlar.

## Sinash

Klaviatura kengaytmasini sinashning o'z cheklovlari bor:

- **Iloji bo'lsa haqiqiy iPhone'da sinang.** Lag, haptic va harf pufakchasini faqat qurilmada baholash mumkin.
- **Simulatorda** matnni ekrandagi klaviatura tugmalari bilan yozing. Mac klaviaturasidan (`hardware keyboard`)
  kiritilgan matnni kengaytma ko'rmaydi — ✨ noto'g'ri ishlayotgandek tuyuladi, lekin bu simulator xususiyati.
- Simulatorda **Back Tap** ham, **Shortcuts** ilovasi ham yo'q. Debug build'da `ios/tools/simulate-back-tap.sh`
  uning o'rnini bosadi: klaviatura ekranda turganda ishga tushiring — simulator ekrani xuddi Back Tap'dagidek
  tahlil qilinadi. Yoki ilovadagi «DM skrinshotini tanlash» orqali sinang.
- Simulator'da ✨ holatini ko'rish uchun (Full Access'siz ham) Debug build'da `ios/tools/simulate-variants.sh`:
  klaviatura ekranda turganda ishga tushiring — uchta soxta variant, «↩︎ Asli» va bitta yoqilgan sozlash tugmasi
  chiqadi. Simulator Sozlamalarida AI Keyboard'ni qo'shib Full Access'ni yoqish ham mumkin (Settings → General →
  Keyboard → Keyboards) — shunda ✨ va 📋 haqiqiy Gemini bilan ishlaydi.
- **Unit testlar** (teginish mantig'i, muddatlar, diagnostika):
  `cd ios && xcodegen generate && xcodebuild test -project AIKeyboard.xcodeproj -scheme Tarjimon -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIKeyboardTests`
- **Diagnostika**: ilovada Diagnostika → yoqing. Klaviatura har ochilishida qisqa hisobot yozadi (teginishlar,
  yo'qolganlari, kechikish, CPU, harorat — yozilgan matn saqlanmaydi). «Yozish testi» harf yo'qolishini tekshiradi.
  Instruments'ning Points of Interest trekida tugma, ✨ va Back Tap bosqichlari ko'rinadi.
- **Ovozdan matn** (o'zbekcha, Gemini orqali): klaviaturadagi 🎤 ilovani ochadi, ilova yozib oladi, ⏹ dan keyin
  matn kursor joyiga tushadi. Mikrofon va fon yozish faqat haqiqiy telefonda to'liq sinaladi; Simulator'da ilovadagi
  "Gapirish" ekrani Mac mikrofoni bilan ishlaydi.
- **Prompt'lar** (`ios/Shared/Prompts.swift`) o'zgarsa, haqiqiy Gemini bilan kamida bitta **5–6 ta ketma-ket xabarli**
  to'qima suhbatda sinang: har xabar alohida qatorda tarjima bo'lishi kerak. Matnli testlar prompt'ning asosiy
  qoidalari o'chib ketmasligini tekshiradi, tarjima sifatini emas.
- **✨ dan keyin**: variantlar qatorida «qisqaroq · iliqroq · rasmiyroq · hazil» tugmalari (asl qoralama qayta
  so'raladi), «↩︎ Asli» qoralamani qaytaradi. Variantni yuborishdan oldin o'zgartirsangiz, klaviatura buni o'sha
  do'st uchun misol sifatida eslab qoladi (ilovada do'st ekranida ko'rinadi va unutiladi).
- **📋 Tarjima**: DM'da xabarni nusxalasangiz klaviaturada tugma chiqadi — skrinshotsiz, aniq matn bilan. iOS
  «AI Keyboard … dan nusxa oldi» bannerini ko'rsatadi, bu normal. Full Access kerak, shuning uchun Simulator'da
  sinalmaydi.
- Issue va PR'larga **haqiqiy DM skrinshotlarini qo'ymang** — boshqa odamlarning xabarlari. Ismlar va matnni yashiring
  yoki soxta suhbat ishlating.

## Kod

- Atrofdagi kod uslubiga moslang: nomlash, izohlar zichligi, Swift 5 language mode.
- Izohlar *nima uchun*ni tushuntirsin, *nima*ni emas.
- **Yozish yo'li UIKit'da qoladi.** Tugmalar (`ios/Keyboard/KeysUIView.swift`) va emoji paneli ataylab UIKit —
  SwiftUI gesture'lari sezilarli lag berdi. `KeyboardModel` `@Observable`: xususiyatlarni faqat qiymat o'zgarganda
  yozing, aks holda har harfda klaviatura qayta chiziladi.
- Klaviatura kengaytmasining xotira limiti kichik — og'ir kutubxonalar va katta rasmlardan qoching.
- Bitta PR — bitta mavzu. Kichik PR tezroq ko'rib chiqiladi.

## Nimadan boshlash mumkin

- Emoji panelida teri rangi variantlari va to'liq Unicode ro'yxati
- Ilova interfeysini ingliz tiliga lokalizatsiya qilish
- `Friend.isSamePerson` va promptlar uchun unit testlar
- GitHub Actions: har PR'da build tekshiruvi
- iPad joylashuvi

## Litsenziya

Loyiha [MIT](LICENSE-MIT) yoki [Apache 2.0](LICENSE-APACHE) litsenziyasi ostida — foydalanuvchi tanlaydi.
Agar boshqacha aniq aytmagan bo'lsangiz, loyihaga qo'shish uchun yuborgan har qanday hissangiz ham xuddi shu
ikki litsenziya ostida, qo'shimcha shartlarsiz tarqatiladi.
