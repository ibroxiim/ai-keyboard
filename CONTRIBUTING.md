# Hissa qo'shish

> **English:** Contributions are welcome! Fork the repo, work on a branch in your fork and open a Pull Request
> against `main` (direct pushes to `main` are blocked). Docs are in Uzbek, but issues and PRs in English are fine.

AI Keyboard'ni yaxshilashga yordam berganingiz uchun rahmat. Quyidagi qadamlar PR'ingiz tez ko'rib chiqilishi uchun.

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
cp Shared/Secrets.swift.example Shared/Secrets.swift   # o'z kalitingizni qo'ying
xcodegen generate
open AIKeyboard.xcodeproj
```

O'z iPhone'ingizda ishga tushirish uchun Apple akkauntingizga mos ID'lar kerak. Quyidagilarni **faqat lokal**
o'zgartiring va PR'ga qo'shmang:

- `project.yml` — `DEVELOPMENT_TEAM`, ikkala `PRODUCT_BUNDLE_IDENTIFIER`, ikkala `com.apple.security.application-groups`
- `Shared/SharedStore.swift` — `AppGroup.id`
- `Shared/KeyboardOrder.swift` — `tarjimonID` (klaviatura bundle ID'si)
- `tools/make_shortcut.py` — `BUNDLE_ID`, `TEAM_ID` (keyin shortcut faylini qayta yarating, README'ga qarang)

`Shared/Secrets.swift` gitignore'da — API kalitlar hech qachon commit qilinmaydi.

## Sinash

Klaviatura kengaytmasini sinashning o'z cheklovlari bor:

- **Iloji bo'lsa haqiqiy iPhone'da sinang.** Lag, haptic va harf pufakchasini faqat qurilmada baholash mumkin.
- **Simulatorda** matnni ekrandagi klaviatura tugmalari bilan yozing. Mac klaviaturasidan (`hardware keyboard`)
  kiritilgan matnni kengaytma ko'rmaydi — ✨ noto'g'ri ishlayotgandek tuyuladi, lekin bu simulator xususiyati.
- Simulatorda **Back Tap** ham, **Shortcuts** ilovasi ham yo'q. Skrinshot tahlilini ilovadagi
  «DM skrinshotini tanlash» orqali sinang.
- Issue va PR'larga **haqiqiy DM skrinshotlarini qo'ymang** — boshqa odamlarning xabarlari. Ismlar va matnni yashiring
  yoki soxta suhbat ishlating.

## Kod

- Atrofdagi kod uslubiga moslang: nomlash, izohlar zichligi, Swift 5 language mode.
- Izohlar *nima uchun*ni tushuntirsin, *nima*ni emas.
- **Yozish yo'li UIKit'da qoladi.** Tugmalar (`Keyboard/KeysUIView.swift`) va emoji paneli ataylab UIKit —
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
