# iPhone: o'zbekcha ovozdan matn (M1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Klaviaturadagi 🎤 → ilova yozib oladi → Gemini o'zbekcha matnga aylantiradi → matn kursor joyiga tushadi; zaxira yo'l — ilovadagi "Gapirish" ekrani.

**Architecture:** Sessiya holati (`VoiceState`) App Group'dagi `SharedState.voice` orqali ilova va klaviatura o'rtasida bo'lishiladi (holatlar: recording → transcribing → done/failed, har biri o'z muddati bilan). Ilova tomoni `VoiceController` (mikrofon `AudioRecording` protokoli orqasida — testda soxta, ishda `AVAudioRecorder`) yozadi va `Translator.transcribe` (Gemini audio, `Hedge` zanjiri) orqali matn oladi. Klaviatura 🎤 bosilganda `aikeyboard://voice?id=…` ni ochadi, holatni kuzatadi va natijani `id` mos kelsa o'zi, aks holda tugma orqali qo'yadi.

**Tech Stack:** Swift 5 (language mode), SwiftUI + UIKit, AVFoundation (`AVAudioRecorder`, `AVAudioApplication`), XcodeGen, XCTest (host'siz bundle), Gemini REST (`inlineData` audio).

Spec: `docs/superpowers/specs/2026-10-10-ios-voice-dictation-design.md`.

## Global Constraints

- iOS deployment target `18.0`, `SWIFT_VERSION: "5.0"`; Xcode loyihasi faqat `xcodegen generate` bilan; barcha buyruqlar `ios/` papkasidan.
- Yozuv: AAC (`kAudioFormatMPEG4AAC`), 16 000 Hz, 1 kanal, 32 kbit/s, `.m4a`, faqat `tmp/` da; Gemini'ga `mimeType: "audio/mp4"` bilan (tekshirilgan: `audio/mp4`, `audio/m4a`, `audio/aac` hammasi ishlaydi). Maksimum 90 soniya.
- Natija lotin yozuvida; tarjima qilinmaydi. Audio fayl transkripsiyadan keyin o'chiriladi (muvaffaqiyatda ham, "Ovoz eshitilmadi"da ham); faqat qayta urinish mumkin bo'lgan xatoda qoladi. Audio va transkript matni logga yozilmaydi.
- Mikrofon faqat 🎤 yoki "Gapirish" tugmasi bosilganda yoqiladi.
- Muddatlar (sof funksiyalar, `now` bo'yicha): `recording` 100 s, `transcribing` 60 s, `done` 10 daqiqa, `failed` 2 daqiqa; klaviatura "ochilmoqda" holatida 6 soniya kutadi.
- Klaviaturada kuzatiladigan xossalar faqat qiymat o'zgarganda yoziladi; taymer yoki uzluksiz animatsiya qo'shilmaydi (batareya).
- Testlar faqat shu loyihaning `AI Keyboard Demo` simulatorida: `id=A68FA497-8B43-4D49-949B-92D20087F069`. Boshqa sessiyalarning simulatorlariga tegilmaydi.
- `ios/Shared/Secrets.swift` ga tegilmaydi, kalit hech qayerda chiqarilmaydi. Commit'lar repo-local noreply email bilan (allaqachon sozlangan), oxirida `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Izohlar inglizcha, *nima uchun*ni tushuntiradi; UI matnlari o'zbekcha (lotin).
- Push/PR foydalanuvchining alohida tasdig'isiz qilinmaydi.

Test buyrug'i ("TEST"):

```bash
cd ~/Desktop/side-projects/ai-keyboard/ios && xcodegen generate >/dev/null && xcodebuild test -project AIKeyboard.xcodeproj -scheme Tarjimon -destination 'id=A68FA497-8B43-4D49-949B-92D20087F069' -derivedDataPath build -only-testing:AIKeyboardTests 2>&1 | grep -E "error:|failed|Executed [0-9]+ tests|\*\* TEST" | sort -u | tail -12
```

Natija chiqmasa, `xcodebuild` natijalarni yig'ishda osilib qolgan bo'lishi mumkin: shu buyruqni fonda (`run_in_background`) qayta ishga tushiring va chiqish faylini o'qing.

Build buyrug'i ("BUILD"):

```bash
cd ~/Desktop/side-projects/ai-keyboard/ios && xcodegen generate >/dev/null && xcodebuild -project AIKeyboard.xcodeproj -scheme Tarjimon -configuration Debug -destination 'id=A68FA497-8B43-4D49-949B-92D20087F069' -derivedDataPath build build 2>&1 | grep -E "error:|\*\* BUILD" | sort -u | tail -10
```

---

## File structure

| Fayl | Mas'uliyat |
|---|---|
| `ios/Shared/VoiceState.swift` (yangi) | `VoiceState` (+ muddatlar), `VoiceLink` |
| `ios/Shared/SharedStore.swift` (o'zgaradi) | `SharedState.voice`, `activeVoice(at:)`, `nextDeadline`, `AppGroup.voiceStopRequested` |
| `ios/Shared/VoiceInsertion.swift` (yangi) | Sof mantiq: `VoiceInsertion` (qo'yish qarori, matnni tayyorlash), `VoiceStatus` (klaviatura ko'rsatadigan holat) |
| `ios/Shared/GeminiPart.swift` (yangi) | `GeminiPart` (`.text`, `.jpeg`, `.audio`) |
| `ios/Shared/Gemini.swift` (o'zgaradi) | `typealias Part = GeminiPart`, `hedgeDelay` |
| `ios/Shared/VoiceTranscript.swift` (yangi) | `VoiceError`, `VoiceTranscript` |
| `ios/Shared/Translator.swift` (o'zgaradi) | `Translator.transcribe`, `Prompts.transcribeSystem/Schema` |
| `ios/App/VoiceController.swift` (yangi) | `AudioRecording`, `VoiceController` (yozish → transkripsiya oqimi) |
| `ios/App/AVRecorder.swift` (yangi) | `AVAudioRecorder` bilan `AudioRecording` |
| `ios/App/VoiceController+Live.swift` (yangi) | Haqiqiy ulanishlar (`VoiceController.live()`) |
| `ios/App/VoiceScreen.swift` (yangi) | "Gapirish" ekrani (SwiftUI sheet) |
| `ios/App/TarjimonApp.swift`, `ios/App/ContentView.swift` (o'zgaradi) | URL, muhit, "Gapirish" qatori, sheet |
| `ios/project.yml` (o'zgaradi) | Info.plist kalitlari, test manbalari |
| `ios/Keyboard/KeyboardModel.swift`, `KeyboardView.swift`, `KeyboardViewController.swift` (o'zgaradi) | 🎤, status, ilovani ochish, matn qo'yish |
| `ios/Tests/Voice*.swift`, `GeminiPartTests.swift` (yangi) | Unit testlar |

---

### Task 1: `VoiceState`, muddatlar va `VoiceLink`

**Files:**
- Create: `ios/Shared/VoiceState.swift`
- Create: `ios/Tests/VoiceStateTests.swift`
- Modify: `ios/Shared/SharedStore.swift` (`AppGroup`, `SharedState`)
- Modify: `ios/project.yml` (`AIKeyboardTests.sources`)

**Interfaces:**
- Produces: `VoiceState { id: String; phase: Phase; since: Date; text: String?; error: String? }`; `VoiceState.Phase { recording, transcribing, done, failed }`; `VoiceState.recordingLimit: TimeInterval` (90); `VoiceState.lifetime(of:) -> TimeInterval`; `VoiceState.expiry: Date`; `VoiceState.isLive(at:) -> Bool`; `VoiceLink.url(id:) -> URL`; `VoiceLink.parse(_:) -> String?`; `SharedState.voice: VoiceState?`; `SharedState.activeVoice(at:) -> VoiceState?`; `AppGroup.voiceStopRequested: String`.

- [ ] **Step 1: Test manbasini ro'yxatga qo'shish**

`ios/project.yml` da `AIKeyboardTests` → `sources` ga `Shared/ProvisioningExpiry.swift` qatoridan keyin qo'shing:

```yaml
      - Shared/VoiceState.swift
```

- [ ] **Step 2: Failing test yozish**

`ios/Tests/VoiceStateTests.swift`:

```swift
import XCTest

final class VoiceStateTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 810_000_000)

    private func voice(_ phase: VoiceState.Phase, since: TimeInterval = 0) -> VoiceState {
        VoiceState(
            id: "a", phase: phase, since: now + since,
            text: phase == .done ? "salom" : nil, error: phase == .failed ? "xato" : nil)
    }

    func testEachPhaseHasItsOwnLifetime() {
        XCTAssertTrue(voice(.recording).isLive(at: now + 99))
        XCTAssertFalse(voice(.recording).isLive(at: now + 100))
        XCTAssertTrue(voice(.transcribing).isLive(at: now + 59))
        XCTAssertFalse(voice(.transcribing).isLive(at: now + 60))
        XCTAssertTrue(voice(.done).isLive(at: now + 599))
        XCTAssertFalse(voice(.done).isLive(at: now + 600))
        XCTAssertTrue(voice(.failed).isLive(at: now + 119))
        XCTAssertFalse(voice(.failed).isLive(at: now + 120))
    }

    func testRecordingOutlastsTheRecordingLimit() {
        XCTAssertEqual(VoiceState.recordingLimit, 90)
        XCTAssertGreaterThan(VoiceState.lifetime(of: .recording), VoiceState.recordingLimit)
    }

    func testActiveVoiceHidesADeadSession() {
        var state = SharedState()
        state.voice = voice(.recording)
        XCTAssertNotNil(state.activeVoice(at: now + 50))
        XCTAssertNil(state.activeVoice(at: now + 100))
        XCTAssertNil(SharedState().activeVoice(at: now))
    }

    func testNextDeadlineIncludesTheVoiceExpiry() {
        var state = SharedState()
        state.voice = voice(.recording)
        XCTAssertEqual(state.nextDeadline(after: now), now + 100)
        state.contextDate = now - 880 // goes stale at now + 20, sooner than the voice session
        XCTAssertEqual(state.nextDeadline(after: now), now + 20)
    }

    func testVoiceSurvivesTheSharedFileRoundTrip() throws {
        var state = SharedState()
        state.voice = voice(.done)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(SharedState.self, from: data).voice, state.voice)
    }

    func testStateFilesWithoutVoiceStillLoad() throws {
        let data = try JSONEncoder().encode(SharedState())
        XCTAssertNil(try JSONDecoder().decode(SharedState.self, from: data).voice)
    }

    // MARK: Link

    func testLinkRoundTripsTheSessionID() {
        XCTAssertEqual(VoiceLink.parse(VoiceLink.url(id: "abc-123")), "abc-123")
    }

    func testForeignLinksAreIgnored() {
        XCTAssertNil(VoiceLink.parse(URL(string: "https://example.com/voice?id=1")!))
        XCTAssertNil(VoiceLink.parse(URL(string: "aikeyboard://other?id=1")!))
    }

    func testLinkWithoutIDGetsAFreshOne() throws {
        let id = try XCTUnwrap(VoiceLink.parse(URL(string: "aikeyboard://voice")!))
        XCTAssertFalse(id.isEmpty)
    }
}
```

- [ ] **Step 3: Test yiqilishini ko'rish**

Run: TEST
Expected: `Spec validation error: ... missing source directory ".../Shared/VoiceState.swift"` (loyiha yaratilmaydi) — qizil holat.

- [ ] **Step 4: `VoiceState` va `VoiceLink`**

`ios/Shared/VoiceState.swift`:

```swift
import Foundation

/// The voice-dictation session as the app and the keyboard share it (`SharedState.voice`). The app writes it as it
/// records and transcribes; the keyboard reads it to show progress and to pick up the text.
struct VoiceState: Codable, Equatable {
    enum Phase: String, Codable { case recording, transcribing, done, failed }

    /// Set by the keyboard when it asks for a session; lets it tell its own result from a stray one.
    var id: String
    var phase: Phase
    /// When the current phase began.
    var since: Date
    /// `done`: what was said.
    var text: String?
    /// `failed`: why, in words for the user.
    var error: String?

    /// The app stops recording by itself after this.
    static let recordingLimit: TimeInterval = 90

    /// How long a phase may last before it is taken for dead — the app was killed mid-way — and stops showing.
    /// `recording` outlasts the recording limit.
    static func lifetime(of phase: Phase) -> TimeInterval {
        switch phase {
        case .recording: 100
        case .transcribing: 60
        case .done: 10 * 60
        case .failed: 2 * 60
        }
    }

    var expiry: Date { since + Self.lifetime(of: phase) }

    func isLive(at now: Date) -> Bool { now < expiry }
}

/// `aikeyboard://voice?id=<id>` — what the keyboard's 🎤 opens.
enum VoiceLink {
    static let scheme = "aikeyboard"

    static func url(id: String) -> URL { URL(string: "\(scheme)://voice?id=\(id)")! }

    /// The session id in a voice link; a fresh one when the link carries none; nil when it is not a voice link.
    static func parse(_ url: URL) -> String? {
        guard url.scheme == scheme, url.host == "voice" else { return nil }
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "id" }?.value
        return id?.isEmpty == false ? id : UUID().uuidString
    }
}
```

- [ ] **Step 5: `SharedState` ga ulash**

`ios/Shared/SharedStore.swift` — `enum AppGroup` ichiga, `diagnosticsChanged` dan oldin qo'shing:

```swift
    /// Darwin notification: the keyboard's ⏹ asks the app to stop recording and transcribe.
    static let voiceStopRequested = "com.ibrokhim.dmtranslator.voiceStopRequested"
```

`struct SharedState` ichida `var diagnosticsEnabled: Bool?` dan keyin qo'shing:

```swift
    /// Voice dictation: written by the app as it records and transcribes, read by the keyboard.
    var voice: VoiceState?
```

`extension SharedState` ichida `nextDeadline` ni almashtiring (voice muddati qo'shiladi) va undan keyin yangi funksiya:

```swift
    func nextDeadline(after now: Date) -> Date? {
        [
            analyzingSince.map { $0 + SharedStore.analysisTimeout },
            lastErrorDate.map { $0 + SharedStore.errorLifetime },
            contextDate.map { $0 + SharedStore.contextLifetime },
            voice?.expiry,
        ]
        .compactMap { $0 }
        .filter { $0 > now }
        .min()
    }

    /// The voice session while it is still believed; a dead one (app killed mid-way) shows as none.
    func activeVoice(at now: Date) -> VoiceState? {
        guard let voice, voice.isLive(at: now) else { return nil }
        return voice
    }
```

- [ ] **Step 6: Test o'tishini ko'rish**

Run: TEST
Expected: `VoiceStateTests` dagi 9 test `passed`, avvalgilar ham yashil, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/project.yml ios/Shared/VoiceState.swift ios/Shared/SharedStore.swift ios/Tests/VoiceStateTests.swift && git commit -q -F - <<'EOF'
iOS ovoz: VoiceState, muddatlar va aikeyboard://voice havolasi

Sessiya holati (recording → transcribing → done/failed) App Group holatida
bo'lishiladi; har bosqich o'z muddatidan keyin eskiradi (ilova o'ldirilsa
klaviatura osilib qolmaydi) va nextDeadline'ga kiradi.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: Qo'yish qarori va klaviatura holati (`VoiceInsertion`, `VoiceStatus`)

**Files:**
- Create: `ios/Shared/VoiceInsertion.swift`
- Create: `ios/Tests/VoiceInsertionTests.swift`
- Modify: `ios/project.yml` (`AIKeyboardTests.sources`)

**Interfaces:**
- Consumes: `VoiceState` (Task 1).
- Produces: `VoiceInsertion.Decision { none, insert(String), offer(String) }`; `VoiceInsertion.decision(voice: VoiceState?, pendingID: String?, now: Date) -> Decision`; `VoiceInsertion.prepared(_ text: String, before: String?) -> String`; `VoiceStatus { idle, opening, openFailed, recording, transcribing, ready(String), failed(String) }`; `VoiceStatus.openingTimeout: TimeInterval` (6); `VoiceStatus.of(voice:pendingID:openingSince:now:) -> VoiceStatus`.

- [ ] **Step 1: Test manbasini ro'yxatga qo'shish**

`ios/project.yml` da `AIKeyboardTests` → `sources` ga `Shared/VoiceState.swift` qatoridan keyin:

```yaml
      - Shared/VoiceInsertion.swift
```

- [ ] **Step 2: Failing test yozish**

`ios/Tests/VoiceInsertionTests.swift`:

```swift
import XCTest

final class VoiceInsertionTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 810_000_000)

    private func voice(_ phase: VoiceState.Phase, id: String = "a", text: String? = nil, error: String? = nil,
                       since: TimeInterval = 0) -> VoiceState {
        VoiceState(id: id, phase: phase, since: now + since, text: text, error: error)
    }

    // MARK: Decision

    func testOwnFinishedSessionIsInsertedAtOnce() {
        XCTAssertEqual(
            VoiceInsertion.decision(voice: voice(.done, text: "salom"), pendingID: "a", now: now),
            .insert("salom"))
    }

    func testSomeoneElsesResultIsOnlyOffered() {
        XCTAssertEqual(
            VoiceInsertion.decision(voice: voice(.done, id: "b", text: "salom"), pendingID: "a", now: now),
            .offer("salom"))
        XCTAssertEqual(
            VoiceInsertion.decision(voice: voice(.done, text: "salom"), pendingID: nil, now: now),
            .offer("salom"))
    }

    func testNothingToDoUntilTheSessionIsDone() {
        XCTAssertEqual(VoiceInsertion.decision(voice: nil, pendingID: "a", now: now), .none)
        XCTAssertEqual(VoiceInsertion.decision(voice: voice(.recording), pendingID: "a", now: now), .none)
        XCTAssertEqual(VoiceInsertion.decision(voice: voice(.failed, error: "x"), pendingID: "a", now: now), .none)
    }

    func testExpiredOrEmptyResultsAreIgnored() {
        XCTAssertEqual(
            VoiceInsertion.decision(voice: voice(.done, text: "salom"), pendingID: "a", now: now + 601), .none)
        XCTAssertEqual(VoiceInsertion.decision(voice: voice(.done, text: ""), pendingID: "a", now: now), .none)
        XCTAssertEqual(VoiceInsertion.decision(voice: voice(.done), pendingID: "a", now: now), .none)
    }

    // MARK: Text

    func testDictationContinuesTheSentenceWithASpace() {
        XCTAssertEqual(VoiceInsertion.prepared("salom", before: "men"), " salom")
    }

    func testNoSpaceAtTheStartAfterASpaceOrANewLine() {
        XCTAssertEqual(VoiceInsertion.prepared("salom", before: nil), "salom")
        XCTAssertEqual(VoiceInsertion.prepared("salom", before: ""), "salom")
        XCTAssertEqual(VoiceInsertion.prepared("salom", before: "men "), "salom")
        XCTAssertEqual(VoiceInsertion.prepared("salom", before: "men\n"), "salom")
    }

    func testSurroundingWhitespaceOfTheTranscriptIsDropped() {
        XCTAssertEqual(VoiceInsertion.prepared("  salom \n", before: "men"), " salom")
    }

    // MARK: Status

    private func status(_ voice: VoiceState?, pending: String? = "a", opening: TimeInterval? = nil,
                        at offset: TimeInterval = 0) -> VoiceStatus {
        VoiceStatus.of(
            voice: voice, pendingID: pending, openingSince: opening.map { now + $0 }, now: now + offset)
    }

    func testStatusFollowsTheLiveSession() {
        XCTAssertEqual(status(voice(.recording)), .recording)
        XCTAssertEqual(status(voice(.transcribing)), .transcribing)
        XCTAssertEqual(status(voice(.failed, error: "Ovoz eshitilmadi")), .failed("Ovoz eshitilmadi"))
    }

    func testFinishedResultIsReadyUnlessItIsOursToInsert() {
        XCTAssertEqual(status(voice(.done, id: "b", text: "salom")), .ready("salom"))
        XCTAssertEqual(status(voice(.done, text: "salom")), .idle)
    }

    func testWaitingForTheAppToAnswer() {
        XCTAssertEqual(status(nil, opening: 0, at: 2), .opening)
        XCTAssertEqual(status(nil, opening: 0, at: 6), .openFailed)
        XCTAssertEqual(status(nil), .idle)
    }

    func testAnsweringAppEndsTheWait() {
        XCTAssertEqual(status(voice(.recording), opening: 0, at: 2), .recording)
    }

    func testDeadSessionLooksLikeNone() {
        XCTAssertEqual(status(voice(.recording), at: 200), .idle)
    }
}
```

- [ ] **Step 3: Test yiqilishini ko'rish**

Run: TEST
Expected: `missing source directory ".../Shared/VoiceInsertion.swift"` — qizil holat.

- [ ] **Step 4: Mantiq**

`ios/Shared/VoiceInsertion.swift`:

```swift
import Foundation

/// What the keyboard does with a finished voice session, and what it shows while one is going on. Pure, so the
/// rules are tested without a keyboard.
enum VoiceInsertion {
    enum Decision: Equatable {
        case none
        /// This keyboard asked for the session and it is done: put the text in.
        case insert(String)
        /// A result is waiting but nothing here asked for it — offer a button rather than guess the field.
        case offer(String)
    }

    static func decision(voice: VoiceState?, pendingID: String?, now: Date) -> Decision {
        guard let voice, voice.isLive(at: now), voice.phase == .done,
              let text = voice.text, !text.isEmpty
        else { return .none }
        return voice.id == pendingID ? .insert(text) : .offer(text)
    }

    /// Dictation continues the sentence: a space before the text, unless the cursor is at the very start or
    /// already after a space or a new line.
    static func prepared(_ text: String, before: String?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = before?.last, !last.isWhitespace else { return trimmed }
        return " " + trimmed
    }
}

/// The keyboard's view of voice dictation.
enum VoiceStatus: Equatable {
    case idle
    /// 🎤 was tapped and the app has not started recording yet.
    case opening
    /// The app did not answer in time — iOS may have refused to open it from the keyboard.
    case openFailed
    case recording
    case transcribing
    /// A result is waiting for the user to put it in.
    case ready(String)
    case failed(String)

    /// How long the keyboard waits for the app to start recording.
    static let openingTimeout: TimeInterval = 6

    static func of(voice: VoiceState?, pendingID: String?, openingSince: Date?, now: Date) -> VoiceStatus {
        if let voice, voice.isLive(at: now) {
            switch voice.phase {
            case .recording: return .recording
            case .transcribing: return .transcribing
            case .done:
                guard let text = voice.text, !text.isEmpty else { return .idle }
                // Our own result is inserted at once; until then it is not worth a button.
                return voice.id == pendingID ? .idle : .ready(text)
            case .failed: return .failed(voice.error ?? "Ovozdan matn: xato")
            }
        }
        guard let openingSince else { return .idle }
        return now.timeIntervalSince(openingSince) < openingTimeout ? .opening : .openFailed
    }
}
```

- [ ] **Step 5: Test o'tishini ko'rish**

Run: TEST
Expected: `VoiceInsertionTests` dagi 12 test `passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/project.yml ios/Shared/VoiceInsertion.swift ios/Tests/VoiceInsertionTests.swift && git commit -q -F - <<'EOF'
iOS ovoz: qo'yish qarori va klaviatura holati (sof mantiq)

O'z sessiyasi natijasi darhol qo'yiladi, begona natija faqat tugma bilan
(noto'g'ri maydonga tushmasligi uchun). Matn oldiga kerak bo'lsa bo'shliq
qo'yiladi. Ilova 6 soniyada javob bermasa "ochilmadi" holati.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Gemini audio va transkripsiya

**Files:**
- Create: `ios/Shared/GeminiPart.swift`
- Create: `ios/Shared/VoiceTranscript.swift`
- Create: `ios/Tests/GeminiPartTests.swift`
- Create: `ios/Tests/VoiceTranscriptTests.swift`
- Modify: `ios/Shared/Gemini.swift` (nested `Part` → typealias, `hedgeDelay`)
- Modify: `ios/Shared/Translator.swift` (`Translator.transcribe`, `Prompts.transcribeSystem/Schema`)
- Modify: `ios/project.yml` (`AIKeyboardTests.sources`)

**Interfaces:**
- Produces: `GeminiPart { text(String), jpeg(Data), audio(Data, mimeType: String) }`, `GeminiPart.json: [String: Any]`, `GeminiPart.isMedia: Bool`; `Gemini.Part` (= `GeminiPart`); `VoiceError { microphoneDenied, recordingFailed, noSpeech }: LocalizedError, Equatable`; `VoiceTranscript.Result { text: String }: Decodable`; `VoiceTranscript.text(from:) throws -> String`; `Translator.transcribe(audio: Data, mimeType: String = "audio/mp4") async throws -> String`.

- [ ] **Step 1: Test manbalarini ro'yxatga qo'shish**

`ios/project.yml` da `AIKeyboardTests` → `sources` ga `Shared/VoiceInsertion.swift` qatoridan keyin:

```yaml
      - Shared/GeminiPart.swift
      - Shared/VoiceTranscript.swift
```

- [ ] **Step 2: Failing testlar**

`ios/Tests/GeminiPartTests.swift`:

```swift
import XCTest

final class GeminiPartTests: XCTestCase {
    func testAudioIsSentAsInlineDataWithItsMimeType() throws {
        let bytes = Data([1, 2, 3, 4])
        let json = GeminiPart.audio(bytes, mimeType: "audio/mp4").json
        let inline = try XCTUnwrap(json["inlineData"] as? [String: String])
        XCTAssertEqual(inline["mimeType"], "audio/mp4")
        XCTAssertEqual(inline["data"], bytes.base64EncodedString())
    }

    func testImageAndTextKeepTheirShape() throws {
        XCTAssertEqual(GeminiPart.text("salom").json["text"] as? String, "salom")
        let inline = try XCTUnwrap(GeminiPart.jpeg(Data([9])).json["inlineData"] as? [String: String])
        XCTAssertEqual(inline["mimeType"], "image/jpeg")
    }

    func testOnlyMediaCountsAsMedia() {
        XCTAssertTrue(GeminiPart.audio(Data(), mimeType: "audio/mp4").isMedia)
        XCTAssertTrue(GeminiPart.jpeg(Data()).isMedia)
        XCTAssertFalse(GeminiPart.text("x").isMedia)
    }
}
```

`ios/Tests/VoiceTranscriptTests.swift`:

```swift
import XCTest

final class VoiceTranscriptTests: XCTestCase {
    private func result(_ json: String) throws -> VoiceTranscript.Result {
        try JSONDecoder().decode(VoiceTranscript.Result.self, from: Data(json.utf8))
    }

    func testTranscriptIsTrimmed() throws {
        XCTAssertEqual(try VoiceTranscript.text(from: result(#"{"text": "  salom dunyo \n"}"#)), "salom dunyo")
    }

    func testEmptyTranscriptMeansNoSpeech() throws {
        XCTAssertThrowsError(try VoiceTranscript.text(from: result(#"{"text": "   "}"#))) {
            XCTAssertEqual($0 as? VoiceError, .noSpeech)
        }
    }

    func testEveryErrorExplainsItselfInUzbek() {
        for error in [VoiceError.microphoneDenied, .recordingFailed, .noSpeech] {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertEqual(VoiceError.noSpeech.localizedDescription, "Ovoz eshitilmadi")
        XCTAssertTrue(VoiceError.microphoneDenied.localizedDescription.contains("Mikrofon"))
    }
}
```

- [ ] **Step 3: Test yiqilishini ko'rish**

Run: TEST
Expected: `missing source directory ".../Shared/GeminiPart.swift"` — qizil holat.

- [ ] **Step 4: `GeminiPart` va `VoiceTranscript`**

`ios/Shared/GeminiPart.swift`:

```swift
import Foundation

/// One piece of a Gemini request. A top-level type (not nested in `Gemini`) so it compiles, and is tested, without
/// the networking and key code.
enum GeminiPart {
    case text(String)
    case jpeg(Data)
    case audio(Data, mimeType: String)

    var json: [String: Any] {
        switch self {
        case .text(let text): ["text": text]
        case .jpeg(let data): ["inlineData": ["mimeType": "image/jpeg", "data": data.base64EncodedString()]]
        case .audio(let data, let mimeType): ["inlineData": ["mimeType": mimeType, "data": data.base64EncodedString()]]
        }
    }

    /// Images and audio take longer to read than text.
    var isMedia: Bool {
        if case .text = self { return false }
        return true
    }
}
```

`ios/Shared/VoiceTranscript.swift`:

```swift
import Foundation

enum VoiceError: LocalizedError, Equatable {
    case microphoneDenied
    case recordingFailed
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Mikrofonga ruxsat yo'q — Settings → AI Keyboard → Microphone"
        case .recordingFailed: "Yozib bo'lmadi — qayta urinib ko'ring"
        case .noSpeech: "Ovoz eshitilmadi"
        }
    }
}

enum VoiceTranscript {
    /// The model's JSON reply.
    struct Result: Decodable {
        var text: String
    }

    /// An empty transcript is how the model says it heard no speech.
    static func text(from result: Result) throws -> String {
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw VoiceError.noSpeech }
        return trimmed
    }
}
```

- [ ] **Step 5: `Gemini.swift` ni `GeminiPart` ga o'tkazish**

`ios/Shared/Gemini.swift` da nested `enum Part { ... }` bloki (3–14-qatorlar) ni quyidagiga almashtiring:

```swift
    typealias Part = GeminiPart
```

`hedgeDelay` ni almashtiring:

```swift
    /// How long a model may stay quiet before the next one is started alongside it. A screenshot or a voice
    /// message takes longer to read than a rewrite, so it gets more time before paying for a second request.
    static func hedgeDelay(for parts: [Part]) -> Duration {
        parts.contains(where: \.isMedia) ? .seconds(6) : .seconds(4)
    }
```

(Izoh va eski `hedgeDelay` shu bilan almashadi.)

- [ ] **Step 6: `Translator.transcribe` va prompt**

`ios/Shared/Translator.swift` da `enum Translator` ichida `rewrite` funksiyasidan oldin qo'shing:

```swift
    /// A voice message from an Uzbek speaker → what was said, in Latin script. Throws `VoiceError.noSpeech` when the
    /// model heard none.
    static func transcribe(audio: Data, mimeType: String = "audio/mp4") async throws -> String {
        let result = try await Gemini.generate(
            VoiceTranscript.Result.self, system: Prompts.transcribeSystem,
            parts: [.audio(audio, mimeType: mimeType)], schema: Prompts.transcribeSchema)
        return try VoiceTranscript.text(from: result)
    }
```

`enum Prompts` ichida `rewriteSystem` dan oldin qo'shing:

```swift
    static let transcribeSystem = """
    You transcribe a short voice message from an Uzbek speaker who is chatting with a friend.
    Write exactly what was said, in Uzbek Latin script (use ' for oʻ/gʻ), with natural punctuation.
    Keep words in other languages (English, Russian) as spoken. Do not translate, summarize, correct or add anything.
    If there is no speech, return an empty string.

    Return JSON:
    - text: the transcript.
    """

    static let transcribeSchema: [String: Any] = [
        "type": "object",
        "properties": ["text": ["type": "string"]],
        "required": ["text"],
    ]
```

- [ ] **Step 7: Test va build**

Run: TEST → Expected: `GeminiPartTests` (3) va `VoiceTranscriptTests` (3) `passed`, `** TEST SUCCEEDED **`.
Run: BUILD → Expected: `** BUILD SUCCEEDED **` (`Translator`, `Gemini` yangi turlar bilan kompilyatsiya bo'ladi).

- [ ] **Step 8: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/project.yml ios/Shared/GeminiPart.swift ios/Shared/VoiceTranscript.swift ios/Shared/Gemini.swift ios/Shared/Translator.swift ios/Tests/GeminiPartTests.swift ios/Tests/VoiceTranscriptTests.swift && git commit -q -F - <<'EOF'
iOS ovoz: Gemini audio va o'zbekcha transkripsiya

GeminiPart alohida turga chiqdi (.audio qo'shildi), Translator.transcribe
audio'ni lotin yozuvidagi matnga aylantiradi (JSON {text}, bo'sh matn =
"Ovoz eshitilmadi"). Modellar zanjiri Hedge bilan o'sha-o'sha; audio ham
rasmdek 6 soniyadan keyin parallel zaxira oladi.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: `VoiceController` — yozish va transkripsiya oqimi

**Files:**
- Create: `ios/App/VoiceController.swift`
- Create: `ios/Tests/VoiceControllerTests.swift`
- Modify: `ios/project.yml` (`AIKeyboardTests.sources`)

**Interfaces:**
- Consumes: `VoiceState`, `VoiceLink` (Task 1); `VoiceError` (Task 3); `SharedState` (Task 1).
- Produces: `AudioRecording` (`@MainActor` protokol: `start() async throws`, `stop() -> URL?`); `VoiceController` (`@MainActor`, `ObservableObject`) — `state: VoiceState?` (`@Published`), `showsScreen: Bool` (`@Published`), `canRetry: Bool`, `work: Task<Void, Never>?`, `init(recorder:recordingLimit:transcriber:update:runInBackground:)`, `start(id:) async`, `stop()`, `retry()`, `handle(url:)`, `startManually()`; `VoiceController.minimumBytes` (3 000); `VoiceController.StoreUpdate`.

- [ ] **Step 1: Test manbasini ro'yxatga qo'shish**

`ios/project.yml` da `AIKeyboardTests` → `sources` ga `Shared/VoiceTranscript.swift` qatoridan keyin:

```yaml
      - App/VoiceController.swift
```

- [ ] **Step 2: Failing testlar**

`ios/Tests/VoiceControllerTests.swift`:

```swift
import XCTest

@MainActor
final class VoiceControllerTests: XCTestCase {
    private final class FakeRecorder: AudioRecording {
        var startError: Error?
        var file: URL?
        private(set) var startCount = 0

        func start() async throws {
            startCount += 1
            if let startError { throw startError }
        }

        func stop() -> URL? { file }
    }

    private final class Store {
        var state = SharedState()
    }

    private let recorder = FakeRecorder()
    private let store = Store()
    private var files: [URL] = []

    override func tearDown() {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private func audioFile(bytes: Int) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 7, count: bytes))
        files.append(url)
        return url
    }

    private func controller(
        limit: Duration = .seconds(90),
        transcriber: @escaping (Data) async throws -> String = { _ in "salom" }
    ) -> VoiceController {
        VoiceController(
            recorder: recorder, recordingLimit: limit, transcriber: transcriber,
            update: { [store] change in change(&store.state) })
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // MARK: Recording

    func testStartPublishesRecording() async {
        let controller = controller()
        await controller.start(id: "a")
        XCTAssertEqual(controller.state?.phase, .recording)
        XCTAssertEqual(store.state.voice?.id, "a")
        XCTAssertEqual(store.state.voice?.phase, .recording)
        XCTAssertEqual(recorder.startCount, 1)
    }

    func testSecondStartWhileRecordingIsIgnored() async {
        let controller = controller()
        await controller.start(id: "a")
        await controller.start(id: "b")
        XCTAssertEqual(controller.state?.id, "a")
        XCTAssertEqual(recorder.startCount, 1)
    }

    func testMicrophoneDeniedFailsWithItsExplanation() async {
        recorder.startError = VoiceError.microphoneDenied
        let controller = controller()
        await controller.start(id: "a")
        XCTAssertEqual(controller.state?.phase, .failed)
        XCTAssertTrue(controller.state?.error?.contains("Mikrofon") == true)
        XCTAssertEqual(store.state.voice?.phase, .failed)
    }

    // MARK: Transcription

    func testStopTranscribesPublishesTheTextAndDeletesTheFile() async {
        let file = audioFile(bytes: 5_000)
        recorder.file = file
        let controller = controller { data in
            XCTAssertEqual(data.count, 5_000)
            return "men bozorga bordim"
        }
        await controller.start(id: "a")
        controller.stop()
        XCTAssertEqual(controller.state?.phase, .transcribing)
        await controller.work?.value
        XCTAssertEqual(controller.state?.phase, .done)
        XCTAssertEqual(controller.state?.text, "men bozorga bordim")
        XCTAssertEqual(store.state.voice?.text, "men bozorga bordim")
        XCTAssertFalse(exists(file))
        XCTAssertFalse(controller.canRetry)
    }

    func testAlmostEmptyFileFailsAtOnceAndIsDeleted() async {
        let file = audioFile(bytes: 100)
        recorder.file = file
        let controller = controller()
        await controller.start(id: "a")
        controller.stop()
        XCTAssertEqual(controller.state?.phase, .failed)
        XCTAssertEqual(controller.state?.error, "Ovoz eshitilmadi")
        XCTAssertFalse(exists(file))
    }

    func testNoSpeechFromTheModelDeletesTheFile() async {
        let file = audioFile(bytes: 5_000)
        recorder.file = file
        let controller = controller { _ in throw VoiceError.noSpeech }
        await controller.start(id: "a")
        controller.stop()
        await controller.work?.value
        XCTAssertEqual(controller.state?.error, "Ovoz eshitilmadi")
        XCTAssertFalse(exists(file))
        XCTAssertFalse(controller.canRetry)
    }

    func testNetworkFailureKeepsTheFileSoItCanBeRetried() async {
        let file = audioFile(bytes: 5_000)
        recorder.file = file
        var calls = 0
        let controller = controller { _ in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return "yana urinib ko'rdim"
        }
        await controller.start(id: "a")
        controller.stop()
        await controller.work?.value
        XCTAssertEqual(controller.state?.phase, .failed)
        XCTAssertTrue(controller.state?.error?.contains("Internet") == true)
        XCTAssertTrue(controller.canRetry)
        XCTAssertTrue(exists(file))

        controller.retry()
        await controller.work?.value
        XCTAssertEqual(controller.state?.text, "yana urinib ko'rdim")
        XCTAssertFalse(exists(file))
    }

    func testRecordingLimitStopsAndTranscribesByItself() async throws {
        recorder.file = audioFile(bytes: 5_000)
        let controller = controller(limit: .milliseconds(50))
        await controller.start(id: "a")
        try await Task.sleep(for: .milliseconds(400))
        await controller.work?.value
        XCTAssertEqual(controller.state?.phase, .done)
    }

    func testOldTranscriptionDoesNotOverwriteANewSession() async {
        recorder.file = audioFile(bytes: 5_000)
        let controller = controller { _ in
            try await Task.sleep(for: .milliseconds(150))
            return "eski"
        }
        await controller.start(id: "a")
        controller.stop()
        await controller.start(id: "b")
        await controller.work?.value
        XCTAssertEqual(controller.state?.id, "b")
        XCTAssertEqual(controller.state?.phase, .recording)
        XCTAssertEqual(store.state.voice?.id, "b")
    }

    func testStopWithoutRecordingDoesNothing() {
        let controller = controller()
        controller.stop()
        XCTAssertNil(controller.state)
        XCTAssertNil(store.state.voice)
    }

    // MARK: Links

    func testVoiceLinkOpensTheScreenAndStartsRecording() async {
        let controller = controller()
        controller.handle(url: VoiceLink.url(id: "kb-1"))
        XCTAssertTrue(controller.showsScreen)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(controller.state?.id, "kb-1")
        XCTAssertEqual(controller.state?.phase, .recording)
    }

    func testForeignLinkChangesNothing() {
        let controller = controller()
        controller.handle(url: URL(string: "https://example.com")!)
        XCTAssertFalse(controller.showsScreen)
        XCTAssertNil(controller.state)
    }
}
```

- [ ] **Step 3: Test yiqilishini ko'rish**

Run: TEST
Expected: `missing source directory ".../App/VoiceController.swift"` — qizil holat.

- [ ] **Step 4: `VoiceController`**

`ios/App/VoiceController.swift`:

```swift
import Combine
import Foundation

/// The microphone side of `VoiceController`, behind a protocol so the flow is tested without a microphone.
@MainActor
protocol AudioRecording: AnyObject {
    /// Starts recording into a fresh file; throws `VoiceError.microphoneDenied` or `.recordingFailed`.
    func start() async throws
    /// Ends the recording and returns its file; nil when nothing was recorded.
    func stop() -> URL?
}

/// Records a voice message, has it transcribed and publishes each step in `SharedState.voice` so the keyboard can
/// follow along and pick the text up.
@MainActor
final class VoiceController: ObservableObject {
    typealias StoreUpdate = ((inout SharedState) -> Void) -> Void

    /// What this controller last published; the "Gapirish" screen reads it.
    @Published private(set) var state: VoiceState?
    /// The "Gapirish" sheet.
    @Published var showsScreen = false

    /// A file smaller than this holds no speech worth sending — a tap, a muted microphone.
    static let minimumBytes = 3_000

    private let recorder: AudioRecording
    private let recordingLimit: Duration
    private let transcriber: (Data) async throws -> String
    private let update: StoreUpdate
    private let runInBackground: (@escaping () async -> Void) async -> Void

    private var limitTask: Task<Void, Never>?
    /// The latest transcription, for tests to wait on.
    private(set) var work: Task<Void, Never>?
    /// Kept after a failed transcription so "Qayta urinish" can send the same recording again.
    private var heldFile: URL?
    private var starting = false
    /// Bumped by every new session; a transcription of an older one must not overwrite the newer.
    private var generation = 0

    init(
        recorder: AudioRecording,
        recordingLimit: Duration = .seconds(VoiceState.recordingLimit),
        transcriber: @escaping (Data) async throws -> String,
        update: @escaping StoreUpdate,
        // The app may be in the background when the keyboard's ⏹ arrives; the real one asks iOS for time to finish.
        runInBackground: @escaping (@escaping () async -> Void) async -> Void = { await $0() }
    ) {
        self.recorder = recorder
        self.recordingLimit = recordingLimit
        self.transcriber = transcriber
        self.update = update
        self.runInBackground = runInBackground
    }

    var canRetry: Bool { heldFile != nil }

    // MARK: Entry points

    /// `aikeyboard://voice?id=…` from the keyboard.
    func handle(url: URL) {
        guard let id = VoiceLink.parse(url) else { return }
        showsScreen = true
        Task { await start(id: id) }
    }

    /// The "Gapirish" row in the app.
    func startManually() {
        showsScreen = true
        Task { await start(id: UUID().uuidString) }
    }

    // MARK: Recording

    func start(id: String) async {
        guard state?.phase != .recording, !starting else { return }
        starting = true
        defer { starting = false }
        generation += 1
        discardHeldFile()
        do {
            try await recorder.start()
        } catch {
            publish(VoiceState(id: id, phase: .failed, since: Date(), error: Self.message(for: error)))
            return
        }
        publish(VoiceState(id: id, phase: .recording, since: Date()))
        let limit = recordingLimit
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// From the screen, the keyboard's ⏹, the limit or an interruption.
    func stop() {
        guard let current = state, current.phase == .recording else { return }
        limitTask?.cancel()
        limitTask = nil
        let recorded = recorder.stop()
        guard let file = recorded, Self.size(of: file) >= Self.minimumBytes else {
            if let recorded { remove(recorded) }
            publish(VoiceState(id: current.id, phase: .failed, since: Date(), error: VoiceError.noSpeech.localizedDescription))
            return
        }
        publish(VoiceState(id: current.id, phase: .transcribing, since: Date()))
        beginTranscription(of: file, id: current.id)
    }

    func retry() {
        guard let current = state, current.phase == .failed, let file = heldFile else { return }
        publish(VoiceState(id: current.id, phase: .transcribing, since: Date()))
        beginTranscription(of: file, id: current.id)
    }

    // MARK: Transcription

    private func beginTranscription(of file: URL, id: String) {
        let generation = generation
        work = Task { [weak self] in
            guard let self else { return }
            await runInBackground { [weak self] in
                await self?.finish(file: file, id: id, generation: generation)
            }
        }
    }

    private func finish(file: URL, id: String, generation: Int) async {
        let outcome: Result<String, Error>
        do {
            outcome = .success(try await transcriber(try Data(contentsOf: file)))
        } catch {
            outcome = .failure(error)
        }
        let current = generation == self.generation
        switch outcome {
        case .success(let text):
            remove(file)
            heldFile = nil
            if current { publish(VoiceState(id: id, phase: .done, since: Date(), text: text)) }
        case .failure(let error):
            // "No speech" would come out the same again; anything else (network, overload) is worth another try.
            if current, (error as? VoiceError) != .noSpeech {
                heldFile = file
            } else {
                remove(file)
                if current { heldFile = nil }
            }
            if current {
                publish(VoiceState(id: id, phase: .failed, since: Date(), error: Self.message(for: error)))
            }
        }
    }

    // MARK: Helpers

    private func publish(_ new: VoiceState?) {
        state = new
        update { $0.voice = new }
    }

    private func discardHeldFile() {
        if let heldFile { remove(heldFile) }
        heldFile = nil
    }

    private func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
    }

    private static func size(of file: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
    }

    private static func message(for error: Error) -> String {
        if error is URLError { return "Internet bilan muammo — qayta urinib ko'ring" }
        return error.localizedDescription
    }
}
```

- [ ] **Step 5: Test o'tishini ko'rish**

Run: TEST
Expected: `VoiceControllerTests` dagi 12 test `passed`, avvalgilar yashil, `** TEST SUCCEEDED **`. Agar `testRecordingLimitStopsAndTranscribesByItself` yoki `testVoiceLinkOpensTheScreenAndStartsRecording` beqaror bo'lsa, kutish vaqtini oshiring (400 → 800 ms), mantiqni emas.

- [ ] **Step 6: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/project.yml ios/App/VoiceController.swift ios/Tests/VoiceControllerTests.swift && git commit -q -F - <<'EOF'
iOS ovoz: VoiceController — yozish va transkripsiya oqimi

Mikrofon AudioRecording protokoli orqasida, shuning uchun oqim testda soxta
yozuvchi bilan tekshiriladi: 90 s chegarasi, juda qisqa yozuv, "Ovoz
eshitilmadi" (fayl o'chadi), tarmoq xatosida fayl qayta urinish uchun
qoladi, eski transkripsiya yangi sessiyani bosib ketmaydi.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: Ilova tomoni — yozuvchi, "Gapirish" ekrani, URL sxema

**Files:**
- Create: `ios/App/AVRecorder.swift`
- Create: `ios/App/VoiceController+Live.swift`
- Create: `ios/App/VoiceScreen.swift`
- Modify: `ios/App/TarjimonApp.swift`
- Modify: `ios/App/ContentView.swift`
- Modify: `ios/project.yml` (Info.plist kalitlari)

**Interfaces:**
- Consumes: `VoiceController`, `AudioRecording` (Task 4); `VoiceError` (Task 3); `Translator.transcribe` (Task 3); `AppGroup.voiceStopRequested`, `DarwinObserver` (Task 1 / mavjud).
- Produces: `AVRecorder: AudioRecording` (`onInterruption`); `VoiceController.live() -> VoiceController`; `VoiceScreen`.

- [ ] **Step 1: Info.plist kalitlari**

`ios/project.yml` da `Tarjimon` target'ining `info.properties` ostiga (`UISupportedInterfaceOrientations` dan keyin) qo'shing:

```yaml
        NSMicrophoneUsageDescription: "Gapirganingizni o'zbekcha matnga aylantirish uchun mikrofon kerak."
        UIBackgroundModes: [audio]
        CFBundleURLTypes:
          - CFBundleURLName: com.ibrokhim.dmtranslator
            CFBundleURLSchemes: [aikeyboard]
```

- [ ] **Step 2: `AVRecorder`**

`ios/App/AVRecorder.swift`:

```swift
import AVFoundation

/// `AudioRecording` on the real microphone. The session is activated while the app is in the foreground; with the
/// `audio` background mode iOS then lets the recording run on after the user returns to the chat.
@MainActor
final class AVRecorder: AudioRecording {
    private var recorder: AVAudioRecorder?
    private var interruptionObserver: NSObjectProtocol?

    /// A call or another app took the audio: the recording so far is what there will be.
    var onInterruption: (() -> Void)?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceError.microphoneDenied }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
            // Speech does not need more: 16 kHz mono at 32 kbit/s is ~260 KB for the longest (90 s) message.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else { throw VoiceError.recordingFailed }
            self.recorder = recorder
        } catch let error as VoiceError {
            throw error
        } catch {
            throw VoiceError.recordingFailed
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began
            else { return }
            MainActor.assumeIsolated { self?.onInterruption?() }
        }
    }

    func stop() -> URL? {
        let url = recorder?.url
        recorder?.stop()
        recorder = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }
}
```

- [ ] **Step 3: Haqiqiy ulanishlar**

`ios/App/VoiceController+Live.swift`:

```swift
import UIKit

extension VoiceController {
    /// The controller wired to the real microphone, Gemini and the shared state.
    static func live() -> VoiceController {
        let recorder = AVRecorder()
        let controller = VoiceController(
            recorder: recorder,
            transcriber: { try await Translator.transcribe(audio: $0) },
            update: { change in SharedStore.update(change) },
            // The keyboard's ⏹ can arrive with the app in the background; without this iOS may suspend it
            // between the recording ending and the transcript landing.
            runInBackground: { work in
                let task = UIApplication.shared.beginBackgroundTask(withName: "voice-transcribe")
                await work()
                UIApplication.shared.endBackgroundTask(task)
            })
        recorder.onInterruption = { [weak controller] in controller?.stop() }
        return controller
    }
}
```

- [ ] **Step 4: "Gapirish" ekrani**

`ios/App/VoiceScreen.swift`:

```swift
import SwiftUI

/// The dictation sheet: opened by the keyboard's 🎤 (and by the "Gapirish" row), it records, shows the progress and
/// the result. Also the fallback when the keyboard cannot open the app: the text can be copied from here.
struct VoiceScreen: View {
    @EnvironmentObject private var voice: VoiceController

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                content
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .navigationTitle("Gapirish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Yopish") { voice.showsScreen = false }
                }
            }
        }
        .interactiveDismissDisabled(voice.state?.phase == .recording)
    }

    @ViewBuilder
    private var content: some View {
        switch voice.state?.phase {
        case .recording: recording
        case .transcribing: transcribing
        case .done: result
        case .failed: failure
        case nil: ready
        }
    }

    private var ready: some View {
        VStack(spacing: 20) {
            icon("mic.fill", color: .accentColor)
            Text("O'zbekcha gapiring — matn yoziladi.").multilineTextAlignment(.center)
            Button("Yozishni boshlash") { start() }.buttonStyle(.borderedProminent)
        }
    }

    private var recording: some View {
        VStack(spacing: 20) {
            icon("mic.fill", color: .red)
            if let since = voice.state?.since {
                // One tick a second, only while this screen is on and recording.
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Self.clock(context.date.timeIntervalSince(since)))
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                }
            }
            Text("Chatga qayting — yozuv davom etadi.\nPastki chekka bo'ylab o'ngga suring. Tugagach klaviaturadagi ⏹ ni bosing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("To'xtatish") { voice.stop() }.buttonStyle(.borderedProminent).tint(.red)
        }
    }

    private var transcribing: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Matn yozilmoqda…").foregroundStyle(.secondary)
        }
    }

    private var result: some View {
        VStack(spacing: 16) {
            Text(voice.state?.text ?? "")
                .font(.title3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Klaviaturada «🎤 Qo'yish» tugmasi bu matnni maydonga qo'yadi.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Nusxa olish") { UIPasteboard.general.string = voice.state?.text }
                    .buttonStyle(.bordered)
                Button("Qayta yozish") { start() }.buttonStyle(.bordered)
            }
        }
    }

    private var failure: some View {
        VStack(spacing: 16) {
            icon("exclamationmark.triangle.fill", color: .orange)
            Text(voice.state?.error ?? "Xato").multilineTextAlignment(.center)
            if voice.state?.error == VoiceError.microphoneDenied.localizedDescription {
                Button("Sozlamalarni ochish") {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
                .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 12) {
                if voice.canRetry {
                    Button("Qayta urinish") { voice.retry() }.buttonStyle(.borderedProminent)
                }
                Button("Qayta yozish") { start() }.buttonStyle(.bordered)
            }
        }
    }

    private func icon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 44))
            .foregroundStyle(.white)
            .frame(width: 96, height: 96)
            .background(Circle().fill(color))
    }

    private func start() {
        Task { await voice.start(id: UUID().uuidString) }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 5: Ilovaga ulash**

`ios/App/TarjimonApp.swift` ni to'liq quyidagiga almashtiring:

```swift
import SwiftUI

@main
struct TarjimonApp: App {
    @StateObject private var voice = VoiceController.live()
    /// The keyboard's ⏹ arrives as a Darwin notification, also while the app is in the background recording.
    @State private var stopObserver: DarwinObserver?

    init() {
        DiagnosticsStore.migrateLegacyFile()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(voice)
                .onOpenURL { voice.handle(url: $0) }
                .task {
                    stopObserver = DarwinObserver(name: AppGroup.voiceStopRequested) { [weak controller = voice] in
                        controller?.stop()
                    }
                }
        }
    }
}
```

`ios/App/ContentView.swift` da:

(a) `struct ContentView: View {` ichida, `@StateObject private var store = SharedStateModel()` dan keyin qo'shing:

```swift
    @EnvironmentObject private var voice: VoiceController
```

(b) `body` dagi `Form` ichida `testSection` dan keyin `voiceSection` qo'shing:

```swift
                testSection
                voiceSection
```

(c) `.onChange(of: pickerItem)` zanjiriga (`NavigationStack { ... }` dan keyin, `.task { await refreshExpiryReminders() }` oldiga) sheet qo'shing:

```swift
        .sheet(isPresented: $voice.showsScreen) {
            VoiceScreen().environmentObject(voice)
        }
```

(d) `// MARK: Test` bo'limidan oldin yangi xususiyat:

```swift
    // MARK: Voice

    private var voiceSection: some View {
        Section {
            Button { voice.startManually() } label: {
                Label("Gapirish (o'zbekcha → matn)", systemImage: "mic.fill")
            }
        } footer: {
            Text("Klaviaturadagi 🎤 ham shu ekranni ochadi. Gapirasiz, matn maydonga tushadi.")
        }
    }

```

- [ ] **Step 6: Build va ekranni Simulator'da ko'rish**

Run: BUILD → Expected: `** BUILD SUCCEEDED **`.

```bash
cd ~/Desktop/side-projects/ai-keyboard/ios && SIM=A68FA497-8B43-4D49-949B-92D20087F069 && xcrun simctl install $SIM build/Build/Products/Debug-iphonesimulator/Tarjimon.app && xcrun simctl launch --terminate-running-process $SIM com.ibrokhim.dmtranslator && sleep 4 && xcrun simctl openurl $SIM "aikeyboard://voice?id=sim-test"
```

iOS Simulator boshqaruvi (`device: A68FA497-8B43-4D49-949B-92D20087F069`): `screenshot`. Expected: "Gapirish" varag'i ochiq; mikrofon ruxsati so'rovi (Allow bosing) yoki Mac mikrofoni orqali qizil mikrofon va ishlayotgan taymer; "To'xtatish" bosilsa — Mac mikrofonida jimlik bo'lgani uchun "Ovoz eshitilmadi" (yoki Gemini javobi) ko'rinadi. Varaq ochilmasa — URL sxema `Info.plist` ga yetib bormagan: `ios/App/Info.plist` dagi `CFBundleURLTypes` ni tekshiring.

- [ ] **Step 7: Testlar va commit**

Run: TEST → Expected: hammasi yashil.

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/project.yml ios/App ios/Tests && git status --short | head -12 && git commit -q -F - <<'EOF'
iOS ovoz: ilova tomoni — yozuvchi, "Gapirish" ekrani, aikeyboard:// havolasi

AVAudioRecorder (AAC 16 kHz mono) audio fon rejimi bilan: chatga qaytgach
yozuv davom etadi. Transkripsiya beginBackgroundTask ichida. Klaviaturaning
⏹ i Darwin bildirishnomasi bilan keladi. Ekran: yozish, taymer, natija,
nusxa olish, qayta urinish. Info.plist: mikrofon matni, audio fon rejimi,
aikeyboard sxemasi.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

(Agar `git status` `ios/App/Info.plist` ni o'zgargan deb ko'rsatsa — u ham shu commit'ga kiradi, `git add ios/App` allaqachon qamraydi.)

---

### Task 6: Klaviatura — 🎤, holat, ilovani ochish, matn qo'yish

**Files:**
- Modify: `ios/Keyboard/KeyboardModel.swift`
- Modify: `ios/Keyboard/KeyboardView.swift`
- Modify: `ios/Keyboard/KeyboardViewController.swift`

**Interfaces:**
- Consumes: `VoiceStatus`, `VoiceInsertion` (Task 2); `VoiceLink`, `SharedState.activeVoice(at:)`, `AppGroup.voiceStopRequested` (Task 1).
- Produces: `KeyboardModel.voiceStatus: VoiceStatus`; `tapMic()`; `reconcileVoice()`; `openApp: ((URL) -> Void)?`.

- [ ] **Step 1: Model — holat va usullar**

`ios/Keyboard/KeyboardModel.swift`:

(a) `var variantListFocus: Suggestion.ID?` dan keyin (`var hasFullAccess = false` dan oldin) qo'shing:

```swift
    /// Voice dictation: when 🎤 was tapped and the app has not answered yet (see `VoiceStatus`).
    var voiceOpeningSince: Date?
```

(b) `@ObservationIgnored weak var controller: UIInputViewController?` dan keyin qo'shing:

```swift
    /// Opens a URL in the app; set by the view controller (an extension cannot use `UIApplication.shared`).
    @ObservationIgnored var openApp: ((URL) -> Void)?
    /// The voice session this keyboard asked the app for; its result is inserted without asking.
    @ObservationIgnored var pendingVoiceID: String?
    @ObservationIgnored private var voiceOpenTask: Task<Void, Never>?
```

(c) `var context: ChatAnalysis? { ... }` dan keyin hisoblanuvchi xossa:

```swift
    var voiceStatus: VoiceStatus {
        VoiceStatus.of(voice: state.voice, pendingID: pendingVoiceID, openingSince: voiceOpeningSince, now: now)
    }
```

(d) `reloadState()` ichida `if context != nil, showsTargetPicker { showsTargetPicker = false }` qatoridan keyin, `scheduleRefresh()` dan oldin:

```swift
        reconcileVoice()
```

(e) `scheduleRefresh()` ichida `closeVariantListIfEmpty()` dan keyin (`scheduleRefresh()` rekursiv chaqiruvidan oldin):

```swift
            reconcileVoice()
```

(f) `stopRefresh()` ichiga qo'shing:

```swift
        voiceOpenTask?.cancel()
        voiceOpenTask = nil
```

(g) `func toggleDetails() { ... }` dan keyin yangi usullar:

```swift
    // MARK: Voice

    /// 🎤: starts a session, stops the running one or puts a waiting result in.
    func tapMic() {
        guard hasFullAccess else {
            flash("🎤 uchun Settings'da AI Keyboard → Allow Full Access'ni yoqing")
            return
        }
        switch voiceStatus {
        case .recording:
            keyDown()
            DarwinNotification.post(AppGroup.voiceStopRequested)
        case .transcribing, .opening:
            break
        case .ready(let text):
            insertVoiceText(text)
        case .idle, .openFailed, .failed:
            startVoice()
        }
    }

    private func startVoice() {
        keyDown()
        let id = UUID().uuidString
        pendingVoiceID = id
        voiceOpeningSince = Date()
        openApp?(VoiceLink.url(id: id))
        // After the wait the status turns into "the app did not open"; nothing else would move `now` then.
        voiceOpenTask?.cancel()
        voiceOpenTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(VoiceStatus.openingTimeout + 0.2))
            guard !Task.isCancelled, let self else { return }
            now = Date()
        }
    }

    /// Called whenever the shared state or the time moves: the app answered, or our own session finished.
    func reconcileVoice() {
        if voiceOpeningSince != nil, state.activeVoice(at: now) != nil { voiceOpeningSince = nil }
        if case .insert(let text) = VoiceInsertion.decision(voice: state.voice, pendingID: pendingVoiceID, now: now) {
            insertVoiceText(text)
        }
    }

    private func insertVoiceText(_ text: String) {
        proxy?.insertText(VoiceInsertion.prepared(text, before: proxy?.documentContextBeforeInput))
        pendingVoiceID = nil
        if voiceOpeningSince != nil { voiceOpeningSince = nil }
        // Consumed: the next session starts clean, and a second keyboard does not offer it again.
        SharedStore.update { $0.voice = nil }
        reloadState()
        autoCapitalize()
    }
```

- [ ] **Step 2: Ko'rinish — 🎤 tugmasi va status**

`ios/Keyboard/KeyboardView.swift`:

(a) `SuggestionBar.body` dagi `if !model.chips.isEmpty { expandButton }` qatoridan keyin (`magicButton` dan oldin) qo'shing:

```swift
                micButton
```

(b) `status` ichida `if let notice = model.notice { ... }` shoxidan keyin, `} else if !model.variants.isEmpty {` shoxidan oldin yangi shox:

```swift
        } else if model.voiceStatus != .idle {
            voiceStatusView
```

(c) `/// Opens every reply in full — a chip shows two lines of it.` izohidan oldin ikki yangi xususiyat:

```swift
    /// 🎤: starts dictation, stops it while it records, or puts a finished result in.
    private var micButton: some View {
        let status = model.voiceStatus
        let busy = status == .opening || status == .transcribing
        return Button(action: model.tapMic) {
            ZStack {
                switch status {
                case .recording:
                    Image(systemName: "stop.fill").foregroundStyle(.white)
                case .opening, .transcribing:
                    ProgressView().controlSize(.small)
                case .ready:
                    Image(systemName: "text.insert").foregroundStyle(.white)
                default:
                    Image(systemName: "mic.fill").foregroundStyle(.primary)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 36, height: 30)
            .background(Capsule().fill(micFill(status)))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("Ovozdan matn")
    }

    private func micFill(_ status: VoiceStatus) -> Color {
        switch status {
        case .recording: .red
        case .ready: .accentColor
        default: KeyboardColors.key
        }
    }

    @ViewBuilder
    private var voiceStatusView: some View {
        switch model.voiceStatus {
        case .opening:
            Text("Ilova ochilmoqda…").font(.system(size: 13)).foregroundStyle(.secondary)
        case .openFailed:
            Text("Ilova ochilmadi — AI Keyboard ilovasini oching → Gapirish")
                .font(.system(size: 12)).foregroundStyle(.orange).lineLimit(2)
        case .recording:
            Text("🔴 Yozilmoqda — tugagach ⏹ ni bosing").font(.system(size: 13, weight: .medium)).lineLimit(2)
        case .transcribing:
            Text("Matn yozilmoqda…").font(.system(size: 13)).foregroundStyle(.secondary)
        case .ready:
            Text("🎤 Ovozli matn tayyor — qo'yish").font(.system(size: 13, weight: .medium)).lineLimit(2)
        case .failed(let message):
            Text(message).font(.system(size: 12)).foregroundStyle(.red).lineLimit(2)
        case .idle:
            EmptyView()
        }
    }

```

- [ ] **Step 3: Ilovani ochish va ko'rinishda moslashtirish**

`ios/Keyboard/KeyboardViewController.swift`:

(a) `import SwiftUI\nimport UIKit` ga `import os` qo'shing:

```swift
import os
import SwiftUI
import UIKit
```

(b) `viewDidLoad` da `model.controller = self` dan keyin:

```swift
        model.openApp = { [weak self] url in self?.openApp(url) }
```

(c) `viewWillAppear` da `model.reloadState()` dan keyin, `model.scheduleRefresh()` dan oldin:

```swift
        model.reconcileVoice()
```

(d) `// MARK: Diagnostics` belgisidan oldin yangi usul:

```swift
    // MARK: Voice

    /// A keyboard has no `UIApplication.shared`; the app is the end of the responder chain. `openURL:options:
    /// completionHandler:` is called through its implementation because the typed method is unavailable in
    /// extensions. Not documented by Apple — whether iOS lets it through is seen from the app answering
    /// (`VoiceStatus.openFailed` after 6 s otherwise).
    func openApp(_ url: URL) {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                // A C function type can only carry Objective-C types: NSURL and NSDictionary, not URL and [:].
                typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let selector = NSSelectorFromString("openURL:options:completionHandler:")
                if let implementation = application.method(for: selector) {
                    unsafeBitCast(implementation, to: Open.self)(application, selector, url as NSURL, [:] as NSDictionary, nil)
                    Logger(subsystem: "com.ibrokhim.dmtranslator", category: "voice").info("asked the app to open")
                }
                return
            }
            responder = current.next
        }
    }

```

- [ ] **Step 4: Build va holatlarni Simulator'da ko'rish**

Run: BUILD → Expected: `** BUILD SUCCEEDED **`.

Holatlarni boshqarish uchun (App Group `state.json` ga `voice` yozib):

```bash
cd ~/Desktop/side-projects/ai-keyboard/ios && SIM=A68FA497-8B43-4D49-949B-92D20087F069 && xcrun simctl install $SIM build/Build/Products/Debug-iphonesimulator/Tarjimon.app && G="$(xcrun simctl get_app_container $SIM com.ibrokhim.dmtranslator group.com.ibrokhim.dmtranslator)" && cat > /tmp/voice-state.py <<'EOF'
import json, sys, time
path, phase = sys.argv[1], sys.argv[2]
d = json.load(open(path))
d["context"] = None; d["contextDate"] = None
voice = {"id": "other", "phase": phase, "since": time.time() - 978307200}
if phase == "done": voice["text"] = "men seni juda sog'indim"
if phase == "failed": voice["error"] = "Ovoz eshitilmadi"
d["voice"] = voice
json.dump(d, open(path, "w"))
EOF
for phase in recording; do python3 /tmp/voice-state.py "$G/state.json" $phase; done; xcrun simctl launch --terminate-running-process $SIM com.ibrokhim.dmtranslator -focusTestField YES
```

Sinov maydoniga bosib (kerak bo'lsa pastga surib) klaviaturani oching; `screenshot`. Expected, `recording`: status "🔴 Yozilmoqda — tugagach ⏹ ni bosing", 🎤 o'rnida qizil ⏹. Keyin `python3 /tmp/voice-state.py "$G/state.json" transcribing` (va `done`, `failed`) ni ishga tushirib, ilovani qayta ishga tushirmasdan klaviaturani yopib-oching: `transcribing` — "Matn yozilmoqda…" va aylanuvchi belgi; `done` (id `other` — begona) — "🎤 Ovozli matn tayyor — qo'yish" va ko'k tugma, bosilsa matn maydonga qo'yiladi va `state.json` dan `voice` o'chadi; `failed` — qizil "Ovoz eshitilmadi".

🎤 ni bosish (voice yo'q holatda): Simulator'da klaviaturadan ilovani ochish yo'li ishlasa varaq ochiladi; ishlamasa 6 soniyadan keyin "Ilova ochilmadi — …" ko'rinadi. Ikkala natija ham xatti-harakat sifatida to'g'ri; haqiqiy javob telefonda (Task 7).

- [ ] **Step 5: Testlar va commit**

Run: TEST → Expected: hammasi yashil.

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/Keyboard && git commit -q -F - <<'EOF'
iOS ovoz: klaviaturada 🎤 — holat, ilovani ochish, matn qo'yish

🎤 ilovani aikeyboard://voice orqali ochadi, yozuv paytida ⏹ ga aylanadi
(Darwin bildirishnomasi bilan to'xtatadi), natija id mos kelsa kursor joyiga
o'zi tushadi, aks holda "Qo'yish" tugmasi bilan. Ilova 6 soniyada javob
bermasa "ochilmadi" xabari. Ochish usuli (responder zanjiri) hujjatlanmagan —
telefonda tekshiriladi.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 7: Hujjat, yakuniy tekshiruv, telefonga o'rnatish

**Files:**
- Modify: `CONTRIBUTING.md` ("Sinash" bo'limi)

- [ ] **Step 1: CONTRIBUTING**

`CONTRIBUTING.md` da "## Sinash" bo'limidagi `- **Diagnostika**: ...` bandidan keyin (`- Issue va PR'larga ...` dan oldin) qo'shing:

```markdown
- **Ovozdan matn** (o'zbekcha, Gemini orqali): klaviaturadagi 🎤 ilovani ochadi, ilova yozib oladi, ⏹ dan keyin
  matn kursor joyiga tushadi. Mikrofon va fon yozish faqat haqiqiy telefonda to'liq sinaladi; Simulator'da ilovadagi
  "Gapirish" ekrani Mac mikrofoni bilan ishlaydi.
```

- [ ] **Step 2: Yakuniy tekshiruv**

Run: TEST → Expected: hammasi yashil (avvalgi 60 + yangi ~39 test).

```bash
cd ~/Desktop/side-projects/ai-keyboard/ios && xcodebuild -project AIKeyboard.xcodeproj -scheme Tarjimon -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|\*\* BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

Sirlar tekshiruvi:

```bash
cd ~/Desktop/side-projects/ai-keyboard && git diff --name-only main...HEAD | grep -iE "secrets\.swift$|local\.properties|keystore|\.jks|xcodeproj|\.m4a" || echo "toza"; git log -p main..HEAD | grep -cE "AIza[0-9A-Za-z_-]{20,}"; git log --format='%ae' main..HEAD | sort -u
```

Expected: `toza`, `0`, faqat `95557944+ibroxiim@users.noreply.github.com`.

- [ ] **Step 3: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add CONTRIBUTING.md && git commit -q -F - <<'EOF'
Hujjatlar: ovozdan matn sinovi

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 4: Telefonga o'rnatish**

Telefon Mac'ga ulangan va qulfi ochiq bo'lishi kerak.

```bash
cd ~/Desktop/side-projects/ai-keyboard/ios && xcodebuild -project AIKeyboard.xcodeproj -scheme Tarjimon -configuration Release -destination 'id=00008120-000E4C3A3CDB401E' -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|\*\* BUILD" | tail -2 && xcrun devicectl device install app --device 00008120-000E4C3A3CDB401E build/Build/Products/Release-iphoneos/Tarjimon.app 2>&1 | grep -iE "error|installed" | head -2
```

Expected: `App installed:`.

- [ ] **Step 5: Telefonda tekshiruv (foydalanuvchi bilan)**

Foydalanuvchiga quyidagilarni bajartiring va har biri natijasini so'rang:

1. **Ilova ekrani:** AI Keyboard ilovasi → "Gapirish" → ruxsatni bering → 10–15 soniya o'zbekcha gapiring → To'xtatish. Kutiladi: matn chiqadi (vaqti ~2–4 s), aniqlik qoniqarlimi?
2. **🎤 ilovani ochadimi:** Telegram → Saved Messages → AI Keyboard → 🎤. Kutiladi: "Gapirish" ilovasi ochiladi va yozuv boshlanadi. Ochilmasa: klaviaturada 6 soniyadan keyin "Ilova ochilmadi" — bu `openApp` usuli iOS 27'da ishlamasligini bildiradi (M2: faqat zaxira yo'l).
3. **Fonda davom etish:** Ilova ochilgach chatga qayting (pastki chekka bo'ylab o'ngga suring). Klaviaturada "🔴 Yozilmoqda" va ⏹ ko'rinishi kerak.
4. **To'xtatish va qo'yish:** ⏹ bosing. Kutiladi: "Matn yozilmoqda…" → matn kursor joyiga tushadi.

Natijada: `devicectl device copy from ... --source Library/diagnostics.json` kerak emas; ilova log'lari uchun `xcrun devicectl device process launch --console` yoki Console.app'da `category: voice` filtri.

- [ ] **Step 6: Eslatma**

M1 natijalarini (ochish usuli ishladimi, fon yozuvi davom etdimi, aniqlik) `~/.claude/projects/.../memory/tarjimon-dm-translator.md` ga qisqa yozib qo'ying va `docs/superpowers/specs/2026-10-10-ios-voice-dictation-design.md` dagi "Xavflar" bo'limini haqiqiy natijaga moslang.
