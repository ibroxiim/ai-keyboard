# AI Keyboard — DM uchun AI klaviatura

Chet ellik do'stlar bilan DM'da yozishish uchun iOS va Android klaviatura. Klaviatura ekrandagi suhbatni o'qiydi,
kelgan xabar tarjimasi va 3 ta tayyor javobni chiqaradi. Yoqmasa — o'zbekcha yozib ✨ ni bosasiz, AI suhbat
kontekstiga mos tarjima qilib beradi. iOS'da suhbat telefon orqasiga 2 marta urib (Back Tap) o'qiladi, Android'da —
klaviaturadagi 📖 tugmasi bilan yoki avtomatik ([Android (beta)](#android-beta)).

```
Back Tap ─► Shortcut: [Take Screenshot] → [Suhbatni tahlil qil]   (ios/App/AnalyzeChatIntent.swift)
                                              │ fonda, ilova ochilmaydi
                                              ▼
                     skrinshot (720px JPEG) → Gemini → { tarjima, 3 javob, kontekst }
                                              │
                         App Group: state.json + Darwin notification
                                              │
Klaviatura ◄──────────────────────────────────┘   (ios/Keyboard/)
   ✨: maydondagi matn + kontekst → Gemini → 3 variant → tanlangani maydonni almashtiradi
```

## Tuzilishi

Monorepo: har platforma o'z papkasida, hujjatlar va litsenziyalar ildizda.

| Papka | Nima |
|---|---|
| `ios/Shared/` | Gemini klienti, promptlar, App Group holati — ilova va klaviatura ikkalasida |
| `ios/App/` | Sozlash ekrani, Shortcuts amali (App Intent), skrinshotni siqish |
| `ios/Keyboard/` | Klaviatura: UIKit tugmalar (lotin oʻ/gʻ, kirill), takliflar qatori, ✨, emoji paneli |
| `ios/tools/` | Shortcut faylini yaratish skripti, ikonka manbasi (SVG), Simulator uchun Back Tap skripti |
| `android/` | Android klaviatura (Kotlin, Gradle) — [Android (beta)](#android-beta) |

Model: `gemini-3.5-flash-lite`, band bo'lsa `gemini-3.5-flash`. Skrinshot ikki parallel so'rovda o'qiladi:
tarjima ~2s, tayyor javoblar ~3s. ✨ ~1.5s.

## Ishga tushirish

```bash
cd ios
cp Shared/Secrets.swift.example Shared/Secrets.swift   # kalitni qo'ying
xcodegen generate
open AIKeyboard.xcodeproj
```

Boshqa Apple akkaunt bilan: `ios/project.yml` dagi `DEVELOPMENT_TEAM` va bundle ID'larni (App Group bilan birga)
o'zingiznikiga almashtiring, keyin `ios/tools/make_shortcut.py` ni qayta ishga tushiring.

Xcode'da iPhone'ni tanlab Run. Bepul Apple ID bilan:
- telefonda Settings → General → VPN & Device Management → developer'ga ishonish;
- ilova 7 kundan keyin ochilmay qoladi — Xcode'dan qayta Run qilinadi;
- bitta qurilmaga bepul profil bilan ko'pi bilan 3 ta ilova o'rnatiladi.

## Telefonda sozlash

1. Settings → General → Keyboard → Keyboards → Add New Keyboard → **AI Keyboard**
2. AI Keyboard → **Allow Full Access** (AI internet orqali ishlaydi; harf yozish usiz ham ishlaydi)
3. Ilovada **Shortcut'ni qo'shish** → Shortcuts → **Add Shortcut** (tayyor fayl: `ios/App/Resources/AI Keyboard.shortcut`)
4. Settings → Accessibility → Touch → **Back Tap** → Double Tap → **AI Keyboard** shortcut'i

Ilova sozlash qadamlarini o'zi belgilaydi: 1 — `AppleKeyboards`, 2 — klaviatura Full Access bilan ochilganda,
3–4 — shortcut birinchi marta ishlaganda.

Kontekst 15 daqiqa amal qiladi — keyin klaviatura eski takliflarni ko'rsatmaydi va "kimga yozyapsiz?" deb
do'stlar (skrinshotlardan eslab qolingan: ism, til, ohang) va tillar tugmalarini chiqaradi.

## Shortcut faylini qayta yaratish

Bundle ID, team yoki intent nomi o'zgarsa (`ios/tools/make_shortcut.py` ichida):

```bash
cd ios
python3 tools/make_shortcut.py
shortcuts sign --mode anyone --input build/AIKeyboard-unsigned.shortcut --output "App/Resources/AI Keyboard.shortcut"
```

## Cheklovlar

- Klaviatura faqat o'zi yozgan matnni ishonchli ko'radi. Boshqa klaviaturada yozilgan matnni ✨ ko'rmasligi mumkin.
- iOS: API kalit ilova ichida — faqat shaxsiy foydalanish uchun. Boshqalarga tarqatishdan oldin kalitni server
  (masalan Cloudflare Worker) orqasiga o'tkazish kerak. Android'da har foydalanuvchi o'z kalitini kiritadi.
- Android: Google Play hozircha yo'q — Play Accessibility API'dan foydalanishni cheklaydi; Play versiyasi uchun
  skrinshot (MediaProjection) varianti keyinroq.

## Android (beta)

`android/` — Kotlin, alohida Gradle loyiha. iOS bilan bir xil imkoniyatlar: tarjima + 3 javob, ✨, do'stlarni
eslab qolish, lotin/kirill, emoji paneli. Farqi — suhbatni qanday o'qishi:

- Klaviaturadagi **📖** bosilganda Accessibility xizmati yozayotgan ilovangizdagi chat **matnini** o'qiydi
  (skrinshotsiz — tezroq va arzonroq). Ilova matnni bermasa, skrinshot olinadi (Android 11+).
- **Avtomatik o'qish** (sozlama, standart o'chiq): messengerda klaviatura ochilishi bilan tarjima tayyor.
  Chat o'zgarmasa Gemini'ga qayta yuborilmaydi.
- Gemini kalitini har kim **o'zi kiritadi** (bepul: [aistudio.google.com/apikey](https://aistudio.google.com/apikey)) —
  APK ichida kalit yo'q.

### O'rnatish

1. [Releases](https://github.com/ibroxiim/ai-keyboard/releases) dan `AIKeyboard-*.apk` ni yuklab oching
   (brauzerga "noma'lum ilovalarni o'rnatish" ruxsatini bering).
2. AI Keyboard ilovasida 4 qadam: klaviaturani yoqish → tanlash → chatni o'qishga ruxsat → Gemini kaliti.
3. DM'da klaviaturadagi **📖 Chatni o'qish** ni bosing.

### Manbadan build

```bash
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties
echo "gemini.apiKey=SIZNING_KALITINGIZ" >> local.properties   # faqat debug build uchun, ixtiyoriy
./gradlew :app:testDebugUnitTest :app:assembleDebug
```

Android Studio bilan ham ochiladi (`android/` papkasini). JDK 17+, compileSdk 36.

| Papka | Nima |
|---|---|
| `android/.../ime/` | Klaviatura: tugmalar (Canvas), takliflar paneli (Compose), emoji, avtomatik o'qish |
| `android/.../reader/` | Accessibility xizmati: chat matnini `[TOP]/[L]/[R]` qatorlarga o'giradi |
| `android/.../ai/` | Gemini klienti (zaxira modelga parallel so'rov), promptlar, tahlil |
| `android/.../data/` | Holat (JSON + StateFlow), do'stlar, kalit |
| `android/.../app/` | Sozlash ekrani, demo chat |

## Hissa qo'shish

Takliflar va PR'lar ochiq! Fork → branch → Pull Request. `main`'ga to'g'ridan-to'g'ri push yopiq.
Batafsil: [CONTRIBUTING.md](CONTRIBUTING.md).

## Litsenziya

Quyidagilardan biri, o'zingiz tanlaysiz:

- [MIT](LICENSE-MIT)
- [Apache License 2.0](LICENSE-APACHE)
