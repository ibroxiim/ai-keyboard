# iOS optimizatsiyasi M1 — diagnostika va aniq xatolar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Klaviaturaga o'lchov asbobi (diagnostika sessiyalari, teginish jurnali, ilovadagi Diagnostika ekrani) qo'shish va kod o'qishda ko'ringan aniq xatolarni tuzatish: to'xtamay qoladigan spinner, teginishni kuzatishdagi zaif joylar, rebuild'da harf yo'qolishi, bo'sh joy + harf tartibi.

**Architecture:** Teginish mantig'i `KeysUIView` dan UIKit'siz `TouchTracker` ga ko'chadi (hodisa → amallar + natija yozuvlari); `KeysUIView` faqat UIKit teginishlarini uzatadi va amallarni bajaradi. Diagnostika yoqiq bo'lsa, `KeyboardDiagnostics` sessiyasi (jurnal, runloop kuzatuvchisi, harorat, CPU/xotira) klaviatura ko'ringan paytdan yopilguncha yig'iladi va App Group'dagi `diagnostics.json` ga bir marta yoziladi. Vaqtga bog'liq holat (spinner, xato qatori, kontekst) `now` asosida hisoblanadi va eng yaqin muddatda bitta `Task.sleep` bilan yangilanadi.

**Tech Stack:** Swift 5 (language mode), UIKit + SwiftUI, XcodeGen, XCTest (host'siz unit-test bundle), `os.OSSignposter`, Darwin (`getrusage`, `task_info`), CoreFoundation (`CFRunLoopObserver`).

Spec: `docs/superpowers/specs/2026-09-28-ios-performance-design.md` (M1 bo'limlari).

## Global Constraints

- iOS deployment target `18.0`, `SWIFT_VERSION: "5.0"`; Xcode loyihasi faqat `xcodegen generate` bilan (`*.xcodeproj` gitignore'da, commit qilinmaydi). Barcha buyruqlar `ios/` papkasidan.
- Diagnostika harf, matn va `textDocumentProxy` mazmunini **hech qachon** yozmaydi. Oddiy chatlarda faqat hisoblagichlar; tugma pozitsiyalari (`detail`) faqat ilovaning test maydonida (`DiagnosticsMarker.contentType`).
- Diagnostika standart holatda o'chiq; taymer, alohida oqim, doimiy so'rov yo'q; faylga sessiya oxirida bir marta, asosiy oqimdan tashqarida yoziladi.
- Yozish yo'li UIKit'da qoladi (`KeysUIView`), SwiftUI faqat panel.
- Testlar faqat shu loyihaning `AI Keyboard Demo` simulatorida: `id=A68FA497-8B43-4D49-949B-92D20087F069`. Boshqa sessiyalarning simulator/emulyatorlariga tegilmaydi.
- `ios/Shared/Secrets.swift` ga tegilmaydi, kalit hech qayerda chiqarilmaydi. Commit'lar repo-local noreply email bilan (`95557944+ibroxiim@users.noreply.github.com` — allaqachon sozlangan), oxirida `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Kod izohlari inglizcha, *nima uchun*ni tushuntiradi; UI matnlari o'zbekcha (lotin).
- Push/PR foydalanuvchining alohida tasdig'isiz qilinmaydi.

Test buyrug'i (keyingi vazifalarda "TEST" deb ataladi):

```bash
cd ~/Desktop/side-projects/ai-keyboard/ios && xcodegen generate >/dev/null && xcodebuild test -project AIKeyboard.xcodeproj -scheme Tarjimon -destination 'id=A68FA497-8B43-4D49-949B-92D20087F069' -derivedDataPath build -only-testing:AIKeyboardTests 2>&1 | grep -E "error:|Test Case .*(passed|failed)|Executed|\*\* TEST" | tail -40
```

Build buyrug'i ("BUILD"):

```bash
cd ~/Desktop/side-projects/ai-keyboard/ios && xcodegen generate >/dev/null && xcodebuild -project AIKeyboard.xcodeproj -scheme Tarjimon -configuration Debug -destination 'id=A68FA497-8B43-4D49-949B-92D20087F069' -derivedDataPath build build 2>&1 | grep -E "error:|warning: .*(TouchTracker|Diagnostics|KeysUIView)|\*\* BUILD" | tail -20
```

---

## File structure

| Fayl | Mas'uliyat |
|---|---|
| `ios/project.yml` (o'zgaradi) | `AIKeyboardTests` target, `Tarjimon` sxemasiga test |
| `ios/Tests/*.swift` (yangi) | Unit testlar |
| `ios/Shared/SharedStore.swift` (o'zgaradi) | `isAnalyzing(at:)`, `recentError(at:)`, `nextDeadline(after:)`, `diagnosticsEnabled`, `AppGroup.diagnosticsChanged` |
| `ios/Shared/TouchOutcome.swift` (yangi) | Teginish natijasi turlari — klaviatura ham, ilova ham ishlatadi |
| `ios/Shared/DiagnosticsModel.swift` (yangi) | `DiagnosticSession`, `DiagnosticZone`, `DiagnosticsStore` (`diagnostics.json`), `DiagnosticsMarker` |
| `ios/Shared/PhraseDiff.swift` (yangi) | Test iborasi va yozilganni solishtirish (Levenshtein tekislash) |
| `ios/Shared/Signposts.swift` (yangi) | Instruments uchun `OSSignposter` intervallari |
| `ios/Keyboard/TouchTracker.swift` (yangi) | Teginish mantig'i, UIKit'siz |
| `ios/Keyboard/Diagnostics/TouchJournal.swift` (yangi) | Bir sessiyaning teginish natijalari va kechikishlari |
| `ios/Keyboard/Diagnostics/KeyboardDiagnostics.swift` (yangi) | Sessiya: jurnal + runloop + harorat + CPU/xotira |
| `ios/Keyboard/KeysUIView.swift` (o'zgaradi) | `TouchTracker` ni ishlatadi, jurnalga yozadi |
| `ios/Keyboard/KeyboardModel.swift` (o'zgaradi) | `now` asosidagi `isAnalyzing`/`recentError`, muddat rejalashtirish, `diagnostics` |
| `ios/Keyboard/KeyboardView.swift` (o'zgaradi) | `model.isAnalyzing` / `model.recentError` |
| `ios/Keyboard/KeyboardViewController.swift` (o'zgaradi) | Muddat rejalashtirishni boshlash/to'xtatish, diagnostika sessiyasi |
| `ios/Shared/ChatAnalysisService.swift`, `Translator.swift`, `Gemini.swift` (o'zgaradi) | Signpost'lar |
| `ios/App/DiagnosticsView.swift` (yangi) | Diagnostika ekrani |
| `ios/App/ContentView.swift` (o'zgaradi) | Diagnostika'ga havola |
| `CONTRIBUTING.md`, `.github/pull_request_template.md` (o'zgaradi) | Testlar va diagnostika |

---

### Task 1: Test target va to'xtamay qoladigan spinner

**Files:**
- Modify: `ios/project.yml`
- Create: `ios/Tests/SharedStateDeadlineTests.swift`
- Modify: `ios/Shared/SharedStore.swift` (`SharedStore` konstantalari, `extension SharedState`)
- Modify: `ios/Keyboard/KeyboardModel.swift`
- Modify: `ios/Keyboard/KeyboardView.swift:85,138,143`
- Modify: `ios/Keyboard/KeyboardViewController.swift` (`viewWillAppear`, yangi `viewDidDisappear`)

**Interfaces:**
- Produces: `SharedStore.errorLifetime: TimeInterval` (120); `SharedState.isAnalyzing(at: Date) -> Bool`; `SharedState.recentError(at: Date) -> String?`; `SharedState.nextDeadline(after: Date) -> Date?`; `KeyboardModel.isAnalyzing: Bool`; `KeyboardModel.recentError: String?`; `KeyboardModel.scheduleRefresh()`; `KeyboardModel.stopRefresh()`. Test target `AIKeyboardTests` (keyingi vazifalar unga manba fayl qo'shadi).

- [ ] **Step 1: Test target qo'shish**

`ios/project.yml` da `Tarjimon` target'idagi `    scheme: {}` qatorini almashtiring:

```yaml
    scheme:
      testTargets: [AIKeyboardTests]
```

Faylning oxiriga (`TarjimonKeyboard` target'idan keyin, `targets:` ostida) qo'shing:

```yaml
  AIKeyboardTests:
    type: bundle.unit-test
    platform: iOS
    # No host app: the tests compile the pure-logic sources they cover directly.
    sources:
      - Tests
      - Shared/SharedStore.swift
      - Shared/Models.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.ibrokhim.dmtranslator.tests
        GENERATE_INFOPLIST_FILE: YES
```

- [ ] **Step 2: Failing test yozish**

`ios/Tests/SharedStateDeadlineTests.swift`:

```swift
import XCTest

final class SharedStateDeadlineTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testNoDeadlineWithoutTimedState() {
        XCTAssertNil(SharedState().nextDeadline(after: now))
    }

    func testEarliestFutureDeadlineWins() {
        var state = SharedState()
        state.analyzingSince = now.addingTimeInterval(-10) // times out at now + 50
        state.lastErrorDate = now.addingTimeInterval(-100) // expires at now + 20
        state.contextDate = now // goes stale at now + 900
        XCTAssertEqual(state.nextDeadline(after: now), now.addingTimeInterval(20))
    }

    func testPassedDeadlinesAreSkipped() {
        var state = SharedState()
        state.analyzingSince = now.addingTimeInterval(-120) // already timed out
        state.contextDate = now.addingTimeInterval(-60) // goes stale at now + 840
        XCTAssertEqual(state.nextDeadline(after: now), now.addingTimeInterval(840))
    }

    func testStuckAnalysisStopsAtTimeout() {
        var state = SharedState()
        state.analyzingSince = now
        XCTAssertTrue(state.isAnalyzing(at: now.addingTimeInterval(59)))
        XCTAssertFalse(state.isAnalyzing(at: now.addingTimeInterval(60)))
    }

    func testErrorLineExpires() {
        var state = SharedState()
        state.lastError = "Gemini 503"
        state.lastErrorDate = now
        XCTAssertEqual(state.recentError(at: now.addingTimeInterval(119)), "Gemini 503")
        XCTAssertNil(state.recentError(at: now.addingTimeInterval(120)))
    }
}
```

- [ ] **Step 3: Test yiqilishini ko'rish**

Run: TEST
Expected: `error: value of type 'SharedState' has no member 'nextDeadline'` (va `isAnalyzing(at:)`, `recentError(at:)`), `** TEST FAILED **`.

- [ ] **Step 4: `SharedState` muddatlari**

`ios/Shared/SharedStore.swift` da `enum SharedStore` boshidagi konstantalarga qo'shing:

```swift
    static let contextLifetime: TimeInterval = 15 * 60
    static let analysisTimeout: TimeInterval = 60
    /// How long an analysis error stays in the keyboard's status line.
    static let errorLifetime: TimeInterval = 120
```

(`contextLifetime` va `analysisTimeout` qatorlari allaqachon bor — faqat `errorLifetime` qo'shiladi.)

`extension SharedState` dagi `isAnalyzing` va `recentError` xususiyatlarini (hozirgi 118–126-qatorlar) quyidagiga almashtiring:

```swift
    var isAnalyzing: Bool { isAnalyzing(at: Date()) }

    func isAnalyzing(at now: Date) -> Bool {
        guard let analyzingSince else { return false }
        return now.timeIntervalSince(analyzingSince) < SharedStore.analysisTimeout
    }

    var recentError: String? { recentError(at: Date()) }

    func recentError(at now: Date) -> String? {
        guard let lastError, let lastErrorDate,
              now.timeIntervalSince(lastErrorDate) < SharedStore.errorLifetime
        else { return nil }
        return lastError
    }

    /// The next moment something time-based changes on screen: the analysis spinner times out, the error line
    /// expires or the context goes stale. Nothing else re-renders the keyboard then, so it wakes for this.
    func nextDeadline(after now: Date) -> Date? {
        [
            analyzingSince.map { $0 + SharedStore.analysisTimeout },
            lastErrorDate.map { $0 + SharedStore.errorLifetime },
            contextDate.map { $0 + SharedStore.contextLifetime },
        ]
        .compactMap { $0 }
        .filter { $0 > now }
        .min()
    }
```

- [ ] **Step 5: Test o'tishini ko'rish**

Run: TEST
Expected: `SharedStateDeadlineTests` dagi 5 test `passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Klaviatura `now` bo'yicha yangilanadi**

`ios/Keyboard/KeyboardModel.swift`:

`var context: ChatAnalysis? { state.freshContext(at: now) }` qatoridan keyin qo'shing:

```swift
    /// Read against `now`, like `context`, so a timed-out spinner or an old error goes away on its own.
    var isAnalyzing: Bool { state.isAnalyzing(at: now) }
    var recentError: String? { state.recentError(at: now) }
```

`barExpanded` ni almashtiring:

```swift
    var barExpanded: Bool { !chips.isEmpty || isAnalyzing || showsTargetPicker }
```

`@ObservationIgnored private var noticeTask: Task<Void, Never>?` qatoridan keyin qo'shing:

```swift
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
```

`reloadState()` ni almashtiring (oxiriga `scheduleRefresh()` qo'shiladi) va undan keyin ikki yangi metod:

```swift
    func reloadState() {
        let loaded = SharedStore.load()
        guard loaded != state else { return }
        let previousContextDate = state.contextDate
        state = loaded
        // ✨ variants belong to the chat they were made for.
        if state.contextDate != previousContextDate, !variants.isEmpty { variants = [] }
        if context == nil, showsDetails { showsDetails = false }
        // Suggestions take over the row once a screenshot lands.
        if context != nil, showsTargetPicker { showsTargetPicker = false }
        scheduleRefresh()
    }

    /// The spinner, the error line and the context expire by time alone, and nothing else re-renders the bar
    /// when they do — a stuck `analyzingSince` kept the spinner turning at the display's refresh rate. Sleep
    /// until the next deadline instead of polling, then move `now`.
    func scheduleRefresh() {
        refreshTask?.cancel()
        guard let deadline = state.nextDeadline(after: now) else { return }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            now = Date()
            scheduleRefresh()
        }
    }

    func stopRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
```

`ios/Keyboard/KeyboardView.swift` da uch joyni almashtiring:
- 85-qator: `if model.chips.isEmpty && model.state.isAnalyzing {` → `if model.chips.isEmpty && model.isAnalyzing {`
- 138-qator: `} else if model.state.isAnalyzing {` → `} else if model.isAnalyzing {`
- 143-qator: `} else if let error = model.state.recentError {` → `} else if let error = model.recentError {`

`ios/Keyboard/KeyboardViewController.swift` da `viewWillAppear` ichida `model.reloadState()` dan keyin qo'shing:

```swift
        model.scheduleRefresh()
```

va `viewWillAppear` dan keyin yangi metod:

```swift
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.stopRefresh()
    }
```

- [ ] **Step 7: Build va testlar**

Run: BUILD → Expected: `** BUILD SUCCEEDED **`.
Run: TEST → Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/project.yml ios/Tests ios/Shared/SharedStore.swift ios/Keyboard/KeyboardModel.swift ios/Keyboard/KeyboardView.swift ios/Keyboard/KeyboardViewController.swift && git commit -q -F - <<'EOF'
iOS: to'xtamay qoladigan spinner tuzatildi, unit test target

Spinner, xato qatori va kontekst muddati endi `now` asosida hisoblanadi va
klaviatura eng yaqin muddatda bitta Task.sleep bilan uyg'onadi. Oldin tahlil
tugamay qolsa spinner klaviatura ochiq turgan butun vaqt aylanardi.
Loyihaga birinchi test target qo'shildi (AIKeyboardTests, host'siz).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: `TouchTracker` — teginish mantig'i UIKit'siz

**Files:**
- Create: `ios/Shared/TouchOutcome.swift`
- Create: `ios/Keyboard/TouchTracker.swift`
- Create: `ios/Tests/TouchTrackerTests.swift`
- Modify: `ios/project.yml` (`AIKeyboardTests.sources`)

**Interfaces:**
- Produces:
  - `enum TouchOutcome: String { case typed, rolledOver, slid, committedOnRebuild, recoveredMissingEnd, cancelledBySystem, function }` + `var producedCharacter: Bool`
  - `struct TouchTracker` — `var keys: [KeyKind]`, `mutating func handle(_ event: Event) -> Output`
  - `TouchTracker.KeyKind: String { character, space, newline, backspace, shift, function }`
  - `TouchTracker.Event`: `.began(id: ObjectIdentifier, key: Int, x: CGFloat, time: TimeInterval, alive: Set<ObjectIdentifier>)`, `.moved(id:key: Int?, x:)`, `.ended(id:time:)`, `.cancelled(id:)`, `.willRebuild`
  - `TouchTracker.Action: Equatable`: `.keyDown, .type(key:), .space, .newline, .backspace, .shift, .release(key:), .press(key:), .unpress(key:), .startRepeat, .stopRepeat, .beginCursorDrag(key:), .endCursorDrag(key:), .moveCursor(Int), .showPopup(key:), .hidePopup`
  - `TouchTracker.Record: Equatable { key: Int; outcome: TouchOutcome; eventTime: TimeInterval? }`
  - `TouchTracker.Output: Equatable { actions: [Action]; records: [Record] }`

- [ ] **Step 1: Test manbalarini ro'yxatga qo'shish**

`ios/project.yml` da `AIKeyboardTests` → `sources` ro'yxatiga qo'shing:

```yaml
      - Shared/TouchOutcome.swift
      - Keyboard/TouchTracker.swift
```

- [ ] **Step 2: Failing testlar**

`ios/Tests/TouchTrackerTests.swift`:

```swift
import XCTest

final class TouchTrackerTests: XCTestCase {
    private typealias Record = TouchTracker.Record

    /// Stand-ins for UITouch: only their identity matters. Kept alive so the identifiers stay distinct.
    private final class Finger {}
    private let finger1 = Finger()
    private let finger2 = Finger()
    private var f1: ObjectIdentifier { ObjectIdentifier(finger1) }
    private var f2: ObjectIdentifier { ObjectIdentifier(finger2) }

    private let charA = 0, charB = 1, space = 2, backspace = 3, shift = 4, globe = 5, newline = 6

    private func makeTracker() -> TouchTracker {
        var tracker = TouchTracker()
        tracker.keys = [.character, .character, .space, .backspace, .shift, .function, .newline]
        return tracker
    }

    func testTapTypesOnTouchUp() {
        var tracker = makeTracker()
        let down = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        XCTAssertEqual(down.actions, [.keyDown, .showPopup(key: charA)])
        XCTAssertEqual(down.records, [])
        let up = tracker.handle(.ended(id: f1, time: 1.1))
        XCTAssertEqual(up.actions, [.type(key: charA), .hidePopup])
        XCTAssertEqual(up.records, [Record(key: charA, outcome: .typed, eventTime: 1.1)])
    }

    func testNewFingerCommitsHeldCharacterFirst() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        let second = tracker.handle(.began(id: f2, key: charB, x: 0, time: 1.05, alive: [f1, f2]))
        XCTAssertEqual(second.actions, [.type(key: charA), .hidePopup, .keyDown, .showPopup(key: charB)])
        XCTAssertEqual(second.records, [Record(key: charA, outcome: .rolledOver, eventTime: 1.05)])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.1)).actions, [])
        XCTAssertEqual(tracker.handle(.ended(id: f2, time: 1.2)).actions, [.type(key: charB), .hidePopup])
    }

    func testSpaceStillHeldWhenNextLetterLandsIsTypedFirst() {
        var tracker = makeTracker()
        XCTAssertEqual(
            tracker.handle(.began(id: f1, key: space, x: 100, time: 1, alive: [f1])).actions,
            [.keyDown, .press(key: space)])
        let letter = tracker.handle(.began(id: f2, key: charA, x: 0, time: 1.05, alive: [f1, f2]))
        XCTAssertEqual(letter.actions, [.space, .keyDown, .showPopup(key: charA)])
        XCTAssertEqual(letter.records, [Record(key: space, outcome: .function, eventTime: 1.05)])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.1)).actions, [.unpress(key: space)])
        XCTAssertEqual(tracker.handle(.ended(id: f2, time: 1.2)).actions, [.type(key: charA), .hidePopup])
    }

    func testDraggedSpaceMovesCursorAndIsNotRolledOver() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: space, x: 100, time: 1, alive: [f1]))
        XCTAssertEqual(tracker.handle(.moved(id: f1, key: space, x: 130)).actions, [.beginCursorDrag(key: space)])
        XCTAssertEqual(tracker.handle(.moved(id: f1, key: space, x: 150)).actions, [.moveCursor(2)])
        XCTAssertEqual(
            tracker.handle(.began(id: f2, key: charA, x: 0, time: 1.3, alive: [f1, f2])).actions,
            [.keyDown, .showPopup(key: charA)])
        XCTAssertEqual(
            tracker.handle(.ended(id: f1, time: 1.4)).actions,
            [.unpress(key: space), .endCursorDrag(key: space)])
    }

    func testRebuildTypesHeldCharacterInsteadOfDroppingIt() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        let rebuild = tracker.handle(.willRebuild)
        XCTAssertEqual(rebuild.actions, [.type(key: charA), .hidePopup])
        XCTAssertEqual(rebuild.records, [Record(key: charA, outcome: .committedOnRebuild, eventTime: nil)])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.2)).actions, [])
    }

    func testTouchThatLostItsEndIsTypedWhenTheNextOneBegins() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        let next = tracker.handle(.began(id: f2, key: charB, x: 0, time: 2, alive: [f2]))
        XCTAssertEqual(next.actions, [.type(key: charA), .hidePopup, .keyDown, .showPopup(key: charB)])
        XCTAssertEqual(next.records, [Record(key: charA, outcome: .recoveredMissingEnd, eventTime: nil)])
    }

    func testReusedTouchObjectDoesNotSwallowTheNewPress() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        let reused = tracker.handle(.began(id: f1, key: charB, x: 0, time: 2, alive: [f1]))
        XCTAssertEqual(reused.actions, [.type(key: charA), .hidePopup, .keyDown, .showPopup(key: charB)])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 2.1)).actions, [.type(key: charB), .hidePopup])
    }

    func testCancelledTouchIsRecordedAndNotTyped() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        let cancel = tracker.handle(.cancelled(id: f1))
        XCTAssertEqual(cancel.actions, [.hidePopup])
        XCTAssertEqual(cancel.records, [Record(key: charA, outcome: .cancelledBySystem, eventTime: nil)])
    }

    func testBackspaceActsOnTouchDownAndRepeatsWhileHeld() {
        var tracker = makeTracker()
        let down = tracker.handle(.began(id: f1, key: backspace, x: 0, time: 1, alive: [f1]))
        XCTAssertEqual(down.actions, [.keyDown, .press(key: backspace), .backspace, .startRepeat])
        XCTAssertEqual(down.records, [Record(key: backspace, outcome: .function, eventTime: 1)])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.5)).actions, [.unpress(key: backspace), .stopRepeat])
    }

    func testSlidingToAnotherLetterTypesThatLetter() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: charA, x: 0, time: 1, alive: [f1]))
        XCTAssertEqual(tracker.handle(.moved(id: f1, key: charB, x: 40)).actions, [.showPopup(key: charB)])
        let up = tracker.handle(.ended(id: f1, time: 1.2))
        XCTAssertEqual(up.actions, [.type(key: charB), .hidePopup])
        XCTAssertEqual(up.records, [Record(key: charB, outcome: .slid, eventTime: 1.2)])
    }

    func testShiftActsOnTouchDownOnly() {
        var tracker = makeTracker()
        XCTAssertEqual(tracker.handle(.began(id: f1, key: shift, x: 0, time: 1, alive: [f1])).actions, [.keyDown, .shift])
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.1)).actions, [.unpress(key: shift)])
    }

    func testFunctionKeyActsOnTouchUp() {
        var tracker = makeTracker()
        XCTAssertEqual(
            tracker.handle(.began(id: f1, key: globe, x: 0, time: 1, alive: [f1])).actions,
            [.keyDown, .press(key: globe)])
        let up = tracker.handle(.ended(id: f1, time: 1.1))
        XCTAssertEqual(up.actions, [.release(key: globe), .unpress(key: globe)])
        XCTAssertEqual(up.records, [Record(key: globe, outcome: .function, eventTime: 1.1)])
    }

    func testNewlineActsOnTouchUp() {
        var tracker = makeTracker()
        _ = tracker.handle(.began(id: f1, key: newline, x: 0, time: 1, alive: [f1]))
        XCTAssertEqual(tracker.handle(.ended(id: f1, time: 1.1)).actions, [.newline, .unpress(key: newline)])
    }
}
```

- [ ] **Step 3: Test yiqilishini ko'rish**

Run: TEST
Expected: `error: cannot find 'TouchTracker' in scope` (manba fayllar hali yo'q — xcodegen ogohlantirishi ham bo'lishi mumkin), `** TEST FAILED **`.

- [ ] **Step 4: `TouchOutcome`**

`ios/Shared/TouchOutcome.swift`:

```swift
import Foundation

/// What became of one touch on the keys. The keyboard's journal counts these; the app's Diagnostika screen
/// reads the counts back by `rawValue`.
enum TouchOutcome: String {
    case typed
    /// Typed early because the next finger landed while this one was still down.
    case rolledOver
    /// Typed after the finger slid onto another character.
    case slid
    /// Typed because the keys were rebuilt under the finger (layer or alphabet change).
    case committedOnRebuild
    /// UIKit never delivered the end; typed when the next touch showed it was gone.
    case recoveredMissingEnd
    /// The system cancelled the touch; nothing was typed.
    case cancelledBySystem
    /// Space, return, backspace, shift or another function key did its action.
    case function

    var producedCharacter: Bool {
        switch self {
        case .typed, .rolledOver, .slid, .committedOnRebuild, .recoveredMissingEnd: true
        case .cancelledBySystem, .function: false
        }
    }
}
```

- [ ] **Step 5: `TouchTracker`**

`ios/Keyboard/TouchTracker.swift`:

```swift
import Foundation

/// The key area's touch logic without UIKit, so it can be unit tested. `KeysUIView` turns UIKit touches into
/// `Event`s, performs the returned `Action`s in order and hands the `Record`s to the diagnostics journal.
/// - popup, haptic and click fire on touch-down, the character is inserted on touch-up (like iOS);
/// - fast typing rolls over: a new press commits a character — or a space — that is still held, so the text
///   keeps the order the keys were pressed in;
/// - sliding the finger moves the popup to the key under it; dragging space moves the cursor.
struct TouchTracker {
    enum KeyKind: String {
        case character, space, newline, backspace, shift
        /// Acts on touch-up: globe, КИР/LAT, emoji, 123/ABC/#+=.
        case function
    }

    enum Event {
        /// `alive` is every touch UIKit still tracks (`event.allTouches`); a remembered touch missing from it
        /// never delivered its end.
        case began(id: ObjectIdentifier, key: Int, x: CGFloat, time: TimeInterval, alive: Set<ObjectIdentifier>)
        case moved(id: ObjectIdentifier, key: Int?, x: CGFloat)
        case ended(id: ObjectIdentifier, time: TimeInterval)
        case cancelled(id: ObjectIdentifier)
        /// The keys are about to be rebuilt (layer or alphabet change); `keys` is replaced right after.
        case willRebuild
    }

    enum Action: Equatable {
        /// Haptic and key click.
        case keyDown
        case type(key: Int)
        case space
        case newline
        case backspace
        case shift
        /// Touch-up action of a `.function` key.
        case release(key: Int)
        case press(key: Int)
        case unpress(key: Int)
        case startRepeat
        case stopRepeat
        case beginCursorDrag(key: Int)
        case endCursorDrag(key: Int)
        case moveCursor(Int)
        case showPopup(key: Int)
        case hidePopup
    }

    struct Record: Equatable {
        var key: Int
        var outcome: TouchOutcome
        /// When the touch event that caused the action happened (`UITouch.timestamp`). Nil when no touch event
        /// did — a rebuild, a recovered end, a cancellation — so it stays out of the latency figures.
        var eventTime: TimeInterval?
    }

    struct Output: Equatable {
        var actions: [Action] = []
        var records: [Record] = []
    }

    private struct Touch {
        let id: ObjectIdentifier
        var key: Int
        let startX: CGFloat
        var committed = false
        var slid = false
        var dragging = false
        var consumed: CGFloat = 0
    }

    /// Kind of each key, by index. Set after every rebuild.
    var keys: [KeyKind] = []
    private var touches: [Touch] = []
    private var popupOwner: ObjectIdentifier?

    mutating func handle(_ event: Event) -> Output {
        var out = Output()
        switch event {
        case let .began(id, key, x, time, alive):
            began(id: id, key: key, x: x, time: time, alive: alive, into: &out)
        case let .moved(id, key, x):
            moved(id: id, key: key, x: x, into: &out)
        case let .ended(id, time):
            ended(id: id, time: time, into: &out)
        case let .cancelled(id):
            cancelled(id: id, into: &out)
        case .willRebuild:
            willRebuild(into: &out)
        }
        return out
    }

    private mutating func began(
        id: ObjectIdentifier, key: Int, x: CGFloat, time: TimeInterval, alive: Set<ObjectIdentifier>,
        into out: inout Output
    ) {
        // UIKit reuses UITouch objects, so a remembered touch with this id, or one UIKit no longer tracks, lost
        // its end somewhere. The user did press it: type what it still holds instead of letting it swallow
        // the presses that follow.
        for stale in touches where stale.id == id || !alive.contains(stale.id) {
            if !stale.committed, keys[stale.key] == .character {
                out.actions.append(.type(key: stale.key))
                out.records.append(Record(key: stale.key, outcome: .recoveredMissingEnd, eventTime: nil))
            }
            finish(stale, into: &out)
        }
        // Rollover: the new finger commits what the others still hold.
        for index in touches.indices where !touches[index].committed {
            let held = touches[index]
            switch keys[held.key] {
            case .character:
                out.actions.append(.type(key: held.key))
                out.records.append(Record(key: held.key, outcome: .rolledOver, eventTime: time))
                if popupOwner == held.id {
                    out.actions.append(.hidePopup)
                    popupOwner = nil
                }
            case .space where !held.dragging:
                out.actions.append(.space)
                out.records.append(Record(key: held.key, outcome: .function, eventTime: time))
            default:
                continue
            }
            touches[index].committed = true
        }

        var touch = Touch(id: id, key: key, startX: x)
        out.actions.append(.keyDown)
        switch keys[key] {
        case .character:
            out.actions.append(.showPopup(key: key))
            popupOwner = id
        case .shift:
            // Like iOS: shift reacts on touch-down.
            touch.committed = true
            out.actions.append(.shift)
            out.records.append(Record(key: key, outcome: .function, eventTime: time))
        case .backspace:
            touch.committed = true
            out.actions += [.press(key: key), .backspace, .startRepeat]
            out.records.append(Record(key: key, outcome: .function, eventTime: time))
        case .space, .newline, .function:
            out.actions.append(.press(key: key))
        }
        touches.append(touch)
    }

    private mutating func moved(id: ObjectIdentifier, key: Int?, x: CGFloat, into out: inout Output) {
        guard let index = touches.firstIndex(where: { $0.id == id }) else { return }
        let touch = touches[index]
        switch keys[touch.key] {
        case .space:
            dragCursor(index, x: x, into: &out)
        case .character where !touch.committed:
            guard let key, key != touch.key, keys[key] == .character else { return }
            touches[index].key = key
            touches[index].slid = true
            out.actions.append(.showPopup(key: key))
        default:
            break
        }
    }

    private mutating func dragCursor(_ index: Int, x: CGFloat, into out: inout Output) {
        let step: CGFloat = 9
        let dx = x - touches[index].startX
        if !touches[index].dragging {
            // A space already typed by a rollover must not start moving the cursor as well.
            guard abs(dx) > 12, !touches[index].committed else { return }
            touches[index].dragging = true
            touches[index].consumed = dx
            out.actions.append(.beginCursorDrag(key: touches[index].key))
        }
        let steps = Int((dx - touches[index].consumed) / step)
        if steps != 0 {
            out.actions.append(.moveCursor(steps))
            touches[index].consumed += CGFloat(steps) * step
        }
    }

    private mutating func ended(id: ObjectIdentifier, time: TimeInterval, into out: inout Output) {
        guard let touch = touches.first(where: { $0.id == id }) else { return }
        if !touch.committed {
            switch keys[touch.key] {
            case .character:
                out.actions.append(.type(key: touch.key))
                out.records.append(Record(key: touch.key, outcome: touch.slid ? .slid : .typed, eventTime: time))
            case .space:
                if !touch.dragging {
                    out.actions.append(.space)
                    out.records.append(Record(key: touch.key, outcome: .function, eventTime: time))
                }
            case .newline:
                out.actions.append(.newline)
                out.records.append(Record(key: touch.key, outcome: .function, eventTime: time))
            case .function:
                out.actions.append(.release(key: touch.key))
                out.records.append(Record(key: touch.key, outcome: .function, eventTime: time))
            case .shift, .backspace:
                break
            }
        }
        finish(touch, into: &out)
    }

    private mutating func cancelled(id: ObjectIdentifier, into out: inout Output) {
        guard let touch = touches.first(where: { $0.id == id }) else { return }
        if !touch.committed, !touch.dragging {
            out.records.append(Record(key: touch.key, outcome: .cancelledBySystem, eventTime: nil))
        }
        finish(touch, into: &out)
    }

    private mutating func willRebuild(into out: inout Output) {
        for touch in touches {
            if !touch.committed, keys[touch.key] == .character {
                out.actions.append(.type(key: touch.key))
                out.records.append(Record(key: touch.key, outcome: .committedOnRebuild, eventTime: nil))
            }
            if keys[touch.key] == .backspace { out.actions.append(.stopRepeat) }
        }
        if popupOwner != nil {
            out.actions.append(.hidePopup)
            popupOwner = nil
        }
        touches.removeAll()
    }

    private mutating func finish(_ touch: Touch, into out: inout Output) {
        switch keys[touch.key] {
        case .character:
            break
        case .backspace:
            out.actions += [.unpress(key: touch.key), .stopRepeat]
        case .space, .newline, .shift, .function:
            out.actions.append(.unpress(key: touch.key))
        }
        if touch.dragging { out.actions.append(.endCursorDrag(key: touch.key)) }
        if popupOwner == touch.id {
            out.actions.append(.hidePopup)
            popupOwner = nil
        }
        touches.removeAll { $0.id == touch.id }
    }
}
```

- [ ] **Step 6: Test o'tishini ko'rish**

Run: TEST
Expected: `TouchTrackerTests` 13 test `passed`, jami 18 test, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/project.yml ios/Shared/TouchOutcome.swift ios/Keyboard/TouchTracker.swift ios/Tests/TouchTrackerTests.swift && git commit -q -F - <<'EOF'
iOS: TouchTracker — teginish mantig'i UIKit'siz, testlar bilan

Oxiri kelmagan teginish keyingisini yutib yubormaydi, rebuild bosib turilgan
harfni yo'qotmaydi, bosib turilgan bo'sh joy keyingi harfdan oldin yoziladi.
Har teginish natijasi (TouchOutcome) diagnostika uchun qaytariladi.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Diagnostika modeli, fayl ombori va test iborasi

**Files:**
- Create: `ios/Shared/DiagnosticsModel.swift`
- Create: `ios/Shared/PhraseDiff.swift`
- Create: `ios/Tests/DiagnosticsModelTests.swift`
- Create: `ios/Tests/PhraseDiffTests.swift`
- Modify: `ios/project.yml` (`AIKeyboardTests.sources`)

**Interfaces:**
- Consumes: `SharedStore.containerURL` (bor).
- Produces:
  - `enum DiagnosticZone: String { case edge, center, bottom }`
  - `struct DiagnosticSession: Codable, Equatable, Identifiable` — maydonlar tartibi bilan: `start: Date, duration: Double, testMode: Bool, touches: Int, typed: Int, outcomes: [String: Int], zones: [String: ZoneCount], upToInsertMs: Latency?, deliveryMs: Latency?, mainBusy: MainBusy, cpu: CPU, memoryMB: Memory, thermal: [Thermal], detail: [Touch]?`; ichki turlar `ZoneCount {touches, lost}`, `Latency {p50, p95, max; init?(samples: [Double])}`, `MainBusy {over50ms, maxMs}`, `CPU {seconds, percent}`, `Memory {start, end, warnings}`, `Thermal {state: String, t: Double}`, `Touch {t, key: [Int], kind: String, outcome: String, deliveryMs: Double?, upToInsertMs: Double?}`; `var lost: Int`.
  - `enum DiagnosticsStore` — `limit = 50`, `fileURL: URL?`, `load(from:) -> [DiagnosticSession]`, `append(_:to:)`, `clear(at:)`.
  - `enum DiagnosticsMarker { static let contentType: String }`
  - `struct PhraseDiff: Equatable { missing, extra, substituted: Int; isPerfect: Bool; static let testPhrase: String; static func compare(expected:typed:) -> PhraseDiff; static func normalize(_:) -> String }`

- [ ] **Step 1: Test manbalari**

`ios/project.yml` da `AIKeyboardTests` → `sources` ga qo'shing:

```yaml
      - Shared/DiagnosticsModel.swift
      - Shared/PhraseDiff.swift
```

- [ ] **Step 2: Failing testlar**

`ios/Tests/DiagnosticsModelTests.swift`:

```swift
import XCTest

final class DiagnosticsModelTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    private func session(duration: Double) -> DiagnosticSession {
        DiagnosticSession(
            start: Date(timeIntervalSince1970: 1_790_000_000), duration: duration, testMode: false,
            touches: 10, typed: 9, outcomes: ["typed": 9, "cancelledBySystem": 1],
            zones: ["center": .init(touches: 10, lost: 1)],
            upToInsertMs: .init(samples: [3, 4, 5]), deliveryMs: nil, mainBusy: .init(),
            cpu: .init(seconds: 1, percent: 2), memoryMB: .init(start: 30, end: 31, warnings: 0),
            thermal: [.init(state: "nominal", t: 0)], detail: nil)
    }

    func testLatencyUsesNearestRankPercentiles() {
        let latency = DiagnosticSession.Latency(samples: (1...100).map(Double.init))
        XCTAssertEqual(latency?.p50, 50)
        XCTAssertEqual(latency?.p95, 95)
        XCTAssertEqual(latency?.max, 100)
        XCTAssertEqual(DiagnosticSession.Latency(samples: [7])?.p95, 7)
    }

    func testLatencyIsNilWithoutSamples() {
        XCTAssertNil(DiagnosticSession.Latency(samples: []))
    }

    func testLostCountsSystemCancellations() {
        XCTAssertEqual(session(duration: 1).lost, 1)
    }

    func testStoreRoundTripsASession() {
        DiagnosticsStore.append(session(duration: 12), to: url)
        XCTAssertEqual(DiagnosticsStore.load(from: url), [session(duration: 12)])
    }

    func testStoreKeepsTheNewestFifty() {
        for index in 0..<52 { DiagnosticsStore.append(session(duration: Double(index)), to: url) }
        let sessions = DiagnosticsStore.load(from: url)
        XCTAssertEqual(sessions.count, 50)
        XCTAssertEqual(sessions.first?.duration, 2)
        XCTAssertEqual(sessions.last?.duration, 51)
    }

    func testClearRemovesEverything() {
        DiagnosticsStore.append(session(duration: 1), to: url)
        DiagnosticsStore.clear(at: url)
        XCTAssertEqual(DiagnosticsStore.load(from: url), [])
    }
}
```

`ios/Tests/PhraseDiffTests.swift`:

```swift
import XCTest

final class PhraseDiffTests: XCTestCase {
    func testIdenticalTextIsPerfect() {
        XCTAssertTrue(PhraseDiff.compare(expected: "salom dunyo", typed: "salom dunyo").isPerfect)
    }

    func testMissingLetterIsCounted() {
        XCTAssertEqual(PhraseDiff.compare(expected: "salom dunyo", typed: "salm dunyo"), PhraseDiff(missing: 1))
    }

    func testExtraLetterIsCounted() {
        XCTAssertEqual(PhraseDiff.compare(expected: "salom", typed: "saloom"), PhraseDiff(extra: 1))
    }

    func testWrongLetterIsCounted() {
        XCTAssertEqual(PhraseDiff.compare(expected: "salom", typed: "salim"), PhraseDiff(substituted: 1))
    }

    func testApostropheVariantsAndCaseDoNotCount() {
        XCTAssertTrue(PhraseDiff.compare(expected: "Do'st", typed: "doʻst").isPerfect)
        XCTAssertTrue(PhraseDiff.compare(expected: "do'st", typed: "do’st ").isPerfect)
    }

    func testEmptyTypedTextMissesEverything() {
        XCTAssertEqual(PhraseDiff.compare(expected: "abc", typed: ""), PhraseDiff(missing: 3))
    }

    func testTestPhraseIsAboutTwoHundredCharacters() {
        XCTAssertTrue((150...230).contains(PhraseDiff.testPhrase.count))
    }
}
```

- [ ] **Step 3: Test yiqilishini ko'rish**

Run: TEST
Expected: `error: cannot find 'DiagnosticSession' in scope`, `cannot find 'PhraseDiff' in scope`, `** TEST FAILED **`.

- [ ] **Step 4: `DiagnosticsModel.swift`**

`ios/Shared/DiagnosticsModel.swift`:

```swift
import Foundation

/// Where on the keys a touch landed. Edges and the bottom row sit next to the system's edge gestures.
enum DiagnosticZone: String {
    case edge, center, bottom
}

/// The app's typing-test field carries this content type; only there does the keyboard keep per-touch detail.
enum DiagnosticsMarker {
    static let contentType = "com.ibrokhim.dmtranslator.diagnostics"
}

/// One keyboard appearance as the diagnostics switch recorded it. Written by the keyboard, read by the app's
/// Diagnostika screen. Never contains typed text.
struct DiagnosticSession: Codable, Equatable, Identifiable {
    struct ZoneCount: Codable, Equatable {
        var touches = 0
        var lost = 0
    }

    struct Latency: Codable, Equatable {
        var p50: Double
        var p95: Double
        var max: Double

        /// Nearest-rank percentiles; nil without samples.
        init?(samples: [Double]) {
            guard !samples.isEmpty else { return nil }
            let sorted = samples.sorted()
            func rank(_ fraction: Double) -> Double {
                sorted[Swift.max(0, Int((fraction * Double(sorted.count)).rounded(.up)) - 1)]
            }
            p50 = rank(0.5)
            p95 = rank(0.95)
            max = sorted[sorted.count - 1]
        }
    }

    struct MainBusy: Codable, Equatable {
        var over50ms = 0
        var maxMs: Double = 0
    }

    struct CPU: Codable, Equatable {
        var seconds: Double
        var percent: Double
    }

    struct Memory: Codable, Equatable {
        var start: Double
        var end: Double
        var warnings: Int
    }

    struct Thermal: Codable, Equatable {
        var state: String
        /// Seconds since the session started.
        var t: Double
    }

    /// Test field only: one touch.
    struct Touch: Codable, Equatable {
        /// Seconds since the session started.
        var t: Double
        /// [row, column]
        var key: [Int]
        var kind: String
        var outcome: String
        var deliveryMs: Double?
        var upToInsertMs: Double?
    }

    var start: Date
    var duration: Double
    var testMode: Bool
    var touches: Int
    var typed: Int
    /// Keyed by `TouchOutcome.rawValue`.
    var outcomes: [String: Int]
    /// Keyed by `DiagnosticZone.rawValue`.
    var zones: [String: ZoneCount]
    /// From the touch event that caused the insert to `insertText` returning.
    var upToInsertMs: Latency?
    /// From the touch event to our handler starting.
    var deliveryMs: Latency?
    var mainBusy: MainBusy
    var cpu: CPU
    var memoryMB: Memory
    var thermal: [Thermal]
    var detail: [Touch]?

    var id: String { "\(start.timeIntervalSinceReferenceDate)|\(duration)" }

    /// Touches the system cancelled — the ones that produced nothing.
    var lost: Int { outcomes[TouchOutcome.cancelledBySystem.rawValue] ?? 0 }
}

/// `diagnostics.json` in the App Group: the last `limit` sessions, oldest first.
enum DiagnosticsStore {
    static let limit = 50

    static var fileURL: URL? { SharedStore.containerURL?.appendingPathComponent("diagnostics.json") }

    private struct File: Codable {
        var sessions: [DiagnosticSession]
    }

    static func load(from url: URL? = fileURL) -> [DiagnosticSession] {
        guard let url, let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(File.self, from: data)
        else { return [] }
        return file.sessions
    }

    /// The keyboard calls this off the main thread when a session ends.
    static func append(_ session: DiagnosticSession, to url: URL? = fileURL) {
        guard let url else { return }
        let sessions = Array((load(from: url) + [session]).suffix(limit))
        guard let data = try? encoder.encode(File(sessions: sessions)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear(at url: URL? = fileURL) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

`DiagnosticsModel.swift` `TouchOutcome` ga tayanadi — test target'da `Shared/TouchOutcome.swift` Task 2'da qo'shilgan.

- [ ] **Step 5: `PhraseDiff.swift`**

`ios/Shared/PhraseDiff.swift`:

```swift
import Foundation

/// The Diagnostika typing test: how the typed text differs from the phrase the user was asked to type.
/// Case and apostrophe style do not count — auto-capitalisation and the oʻ key are not missed taps.
struct PhraseDiff: Equatable {
    var missing = 0
    var extra = 0
    var substituted = 0

    var isPerfect: Bool { missing == 0 && extra == 0 && substituted == 0 }

    /// Everyday Uzbek with punctuation, so the test also switches to the 123 layer and back.
    static let testPhrase = "Salom! Bugun ertalab bozorga bordim va olma, nok, uzum oldim. Kechqurun do'stlarim bilan choyxonada o'tirdik. Ertaga soat to'qqizda universitetga boraman, keyin ishga ketaman."

    /// Levenshtein alignment; the backtrace prefers matches, then missing, then extra characters.
    static func compare(expected: String, typed: String) -> PhraseDiff {
        let a = Array(normalize(expected)), b = Array(normalize(typed))
        var cost = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { cost[i][0] = i }
        for j in 0...b.count { cost[0][j] = j }
        if !a.isEmpty, !b.isEmpty {
            for i in 1...a.count {
                for j in 1...b.count {
                    cost[i][j] = min(
                        cost[i - 1][j] + 1,
                        cost[i][j - 1] + 1,
                        cost[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                }
            }
        }
        var diff = PhraseDiff()
        var i = a.count, j = b.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, cost[i][j] == cost[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1) {
                if a[i - 1] != b[j - 1] { diff.substituted += 1 }
                i -= 1
                j -= 1
            } else if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                diff.missing += 1
                i -= 1
            } else {
                diff.extra += 1
                j -= 1
            }
        }
        return diff
    }

    static func normalize(_ text: String) -> String {
        let apostrophes: Set<Character> = ["ʻ", "ʼ", "’", "‘", "`"]
        return String(text.lowercased().map { apostrophes.contains($0) ? "'" : $0 })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 6: Test o'tishini ko'rish**

Run: TEST
Expected: `DiagnosticsModelTests` (6) va `PhraseDiffTests` (7) `passed`, jami 31, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/project.yml ios/Shared/DiagnosticsModel.swift ios/Shared/PhraseDiff.swift ios/Tests/DiagnosticsModelTests.swift ios/Tests/PhraseDiffTests.swift && git commit -q -F - <<'EOF'
iOS: diagnostika sessiyasi modeli, diagnostics.json va yozish testi

Sessiya xulosasi (teginishlar, natijalar, zonalar, kechikish percentillari,
CPU, xotira, harorat) App Group'da oxirgi 50 tasi saqlanadi. PhraseDiff test
iborasini yozilgan matn bilan solishtiradi.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: `TouchJournal`

**Files:**
- Create: `ios/Keyboard/Diagnostics/TouchJournal.swift`
- Create: `ios/Tests/TouchJournalTests.swift`
- Modify: `ios/project.yml` (`AIKeyboardTests.sources`)

**Interfaces:**
- Consumes: `TouchTracker.Record`, `TouchTracker.KeyKind`, `TouchOutcome` (Task 2); `DiagnosticZone`, `DiagnosticSession.ZoneCount`, `DiagnosticSession.Touch` (Task 3).
- Produces: `struct TouchJournal` — `init(keepsDetail: Bool, start: TimeInterval)`; `let keepsDetail: Bool`; read-only `touches: Int`, `typed: Int`, `outcomes: [String: Int]`, `zones: [String: DiagnosticSession.ZoneCount]`, `upToInsertMs: [Double]`, `deliveryMs: [Double]`, `detail: [DiagnosticSession.Touch]`; `mutating func record(_ record: TouchTracker.Record, at position: KeyPosition, kind: TouchTracker.KeyKind, handledAt: TimeInterval, doneAt: TimeInterval)`; `struct TouchJournal.KeyPosition { row, column, rowLength: Int; isBottomRow: Bool; var zone: DiagnosticZone }`.

- [ ] **Step 1: Test manbasi**

`ios/project.yml` da `AIKeyboardTests` → `sources` ga qo'shing:

```yaml
      - Keyboard/Diagnostics/TouchJournal.swift
```

- [ ] **Step 2: Failing testlar**

`ios/Tests/TouchJournalTests.swift`:

```swift
import XCTest

final class TouchJournalTests: XCTestCase {
    private typealias Position = TouchJournal.KeyPosition

    private let center = Position(row: 0, column: 3, rowLength: 10, isBottomRow: false)
    private let edge = Position(row: 1, column: 0, rowLength: 9, isBottomRow: false)
    private let bottom = Position(row: 3, column: 4, rowLength: 7, isBottomRow: true)

    func testZoneOfPosition() {
        XCTAssertEqual(center.zone, .center)
        XCTAssertEqual(edge.zone, .edge)
        XCTAssertEqual(Position(row: 0, column: 9, rowLength: 10, isBottomRow: false).zone, .edge)
        XCTAssertEqual(bottom.zone, .bottom)
    }

    func testCountsOutcomesZonesAndTypedCharacters() {
        var journal = TouchJournal(keepsDetail: false, start: 0)
        journal.record(.init(key: 3, outcome: .typed, eventTime: 1), at: center, kind: .character, handledAt: 1, doneAt: 1)
        journal.record(.init(key: 10, outcome: .cancelledBySystem, eventTime: nil), at: edge, kind: .character, handledAt: 2, doneAt: 2)
        journal.record(.init(key: 30, outcome: .function, eventTime: 3), at: bottom, kind: .space, handledAt: 3, doneAt: 3)
        XCTAssertEqual(journal.touches, 3)
        XCTAssertEqual(journal.typed, 1)
        XCTAssertEqual(journal.outcomes, ["typed": 1, "cancelledBySystem": 1, "function": 1])
        XCTAssertEqual(journal.zones["center"], DiagnosticSession.ZoneCount(touches: 1, lost: 0))
        XCTAssertEqual(journal.zones["edge"], DiagnosticSession.ZoneCount(touches: 1, lost: 1))
        XCTAssertEqual(journal.zones["bottom"], DiagnosticSession.ZoneCount(touches: 1, lost: 0))
    }

    func testLatencyIsMeasuredFromTheTouchEvent() {
        var journal = TouchJournal(keepsDetail: false, start: 0)
        journal.record(.init(key: 3, outcome: .typed, eventTime: 10), at: center, kind: .character, handledAt: 10.002, doneAt: 10.005)
        XCTAssertEqual(journal.deliveryMs.first ?? -1, 2, accuracy: 0.001)
        XCTAssertEqual(journal.upToInsertMs.first ?? -1, 5, accuracy: 0.001)
    }

    func testRecordsWithoutEventTimeStayOutOfLatency() {
        var journal = TouchJournal(keepsDetail: false, start: 0)
        journal.record(.init(key: 3, outcome: .committedOnRebuild, eventTime: nil), at: center, kind: .character, handledAt: 5, doneAt: 5)
        XCTAssertEqual(journal.typed, 1)
        XCTAssertEqual(journal.upToInsertMs, [])
        XCTAssertEqual(journal.deliveryMs, [])
    }

    func testDetailIsKeptOnlyInTestMode() {
        var chat = TouchJournal(keepsDetail: false, start: 100)
        chat.record(.init(key: 3, outcome: .typed, eventTime: 101), at: center, kind: .character, handledAt: 101, doneAt: 101)
        XCTAssertEqual(chat.detail, [])

        var test = TouchJournal(keepsDetail: true, start: 100)
        test.record(.init(key: 3, outcome: .typed, eventTime: 101), at: center, kind: .character, handledAt: 101.5, doneAt: 101.5)
        XCTAssertEqual(test.detail.count, 1)
        XCTAssertEqual(test.detail.first?.key, [0, 3])
        XCTAssertEqual(test.detail.first?.kind, "character")
        XCTAssertEqual(test.detail.first?.outcome, "typed")
        XCTAssertEqual(test.detail.first?.t ?? -1, 1.5, accuracy: 0.0001)
    }
}
```

- [ ] **Step 3: Test yiqilishini ko'rish**

Run: TEST
Expected: `error: cannot find 'TouchJournal' in scope`, `** TEST FAILED **`.

- [ ] **Step 4: `TouchJournal`**

`ios/Keyboard/Diagnostics/TouchJournal.swift`:

```swift
import Foundation

/// Collects what `TouchTracker` reports during one keyboard session. Outside the diagnostics test field it keeps
/// counters only: a sequence of key positions would spell out what the user typed.
struct TouchJournal {
    struct KeyPosition: Equatable {
        var row: Int
        var column: Int
        var rowLength: Int
        var isBottomRow: Bool

        var zone: DiagnosticZone {
            if isBottomRow { return .bottom }
            return column == 0 || column == rowLength - 1 ? .edge : .center
        }
    }

    let keepsDetail: Bool
    private let start: TimeInterval
    private(set) var touches = 0
    private(set) var typed = 0
    private(set) var outcomes: [String: Int] = [:]
    private(set) var zones: [String: DiagnosticSession.ZoneCount] = [:]
    private(set) var upToInsertMs: [Double] = []
    private(set) var deliveryMs: [Double] = []
    private(set) var detail: [DiagnosticSession.Touch] = []

    /// `start`: session start on the `systemUptime` clock, the one `UITouch.timestamp` uses.
    init(keepsDetail: Bool, start: TimeInterval) {
        self.keepsDetail = keepsDetail
        self.start = start
    }

    /// `handledAt`: when our touch handler started; `doneAt`: when its actions (the insert) had finished.
    mutating func record(
        _ record: TouchTracker.Record, at position: KeyPosition, kind: TouchTracker.KeyKind,
        handledAt: TimeInterval, doneAt: TimeInterval
    ) {
        touches += 1
        if record.outcome.producedCharacter { typed += 1 }
        outcomes[record.outcome.rawValue, default: 0] += 1
        let zone = position.zone.rawValue
        zones[zone, default: .init()].touches += 1
        if record.outcome == .cancelledBySystem { zones[zone, default: .init()].lost += 1 }

        var delivery: Double?
        var upToInsert: Double?
        if let eventTime = record.eventTime {
            let handled = max(0, (handledAt - eventTime) * 1000)
            let done = max(0, (doneAt - eventTime) * 1000)
            deliveryMs.append(handled)
            upToInsertMs.append(done)
            delivery = handled
            upToInsert = done
        }
        guard keepsDetail else { return }
        detail.append(DiagnosticSession.Touch(
            t: handledAt - start, key: [position.row, position.column], kind: kind.rawValue,
            outcome: record.outcome.rawValue, deliveryMs: delivery, upToInsertMs: upToInsert))
    }
}
```

- [ ] **Step 5: Test o'tishini ko'rish**

Run: TEST
Expected: `TouchJournalTests` (5) `passed`, jami 36, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/project.yml ios/Keyboard/Diagnostics/TouchJournal.swift ios/Tests/TouchJournalTests.swift && git commit -q -F - <<'EOF'
iOS: TouchJournal — sessiya teginishlari va kechikishlari

Oddiy chatlarda faqat hisoblagichlar, zonalar va kechikishlar; tugma
pozitsiyalari faqat ilovaning test maydonida saqlanadi.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: Diagnostika sessiyasi va signpost'lar

**Files:**
- Create: `ios/Keyboard/Diagnostics/KeyboardDiagnostics.swift`
- Create: `ios/Shared/Signposts.swift`
- Modify: `ios/Shared/SharedStore.swift` (`AppGroup`, `SharedState`)
- Modify: `ios/Keyboard/KeyboardModel.swift` (`diagnostics` xususiyati, `magic()`)
- Modify: `ios/Keyboard/KeyboardViewController.swift` (butun fayl)
- Modify: `ios/Shared/ChatAnalysisService.swift`, `ios/Shared/Translator.swift`, `ios/Shared/Gemini.swift`

**Interfaces:**
- Consumes: `TouchJournal` (Task 4), `DiagnosticSession`, `DiagnosticsStore`, `DiagnosticsMarker` (Task 3), `KeyboardModel.scheduleRefresh/stopRefresh` (Task 1).
- Produces: `@MainActor final class KeyboardDiagnostics` — `init(testMode: Bool)`, `var journal: TouchJournal`, `func memoryWarning()`, `func finish() -> DiagnosticSession`; `KeyboardModel.diagnostics: KeyboardDiagnostics?`; `SharedState.diagnosticsEnabled: Bool?`; `AppGroup.diagnosticsChanged: String`; `enum Signposts` — `measure(_:_:)`, `measureAsync(_:_:)`.

- [ ] **Step 1: Umumiy holatga diagnostika sozlamasi**

`ios/Shared/SharedStore.swift` — `enum AppGroup` ichiga, `simulatedBackTap` dan oldin qo'shing:

```swift
    /// Darwin notification: the keyboard appended a diagnostics session to `diagnostics.json`.
    static let diagnosticsChanged = "com.ibrokhim.dmtranslator.diagnosticsChanged"
```

`struct SharedState` ichida `var emojiKey: Bool?` dan keyin qo'shing:

```swift
    /// App setting (Diagnostika): the keyboard records a session summary per appearance.
    var diagnosticsEnabled: Bool?
```

- [ ] **Step 2: `Signposts`**

`ios/Shared/Signposts.swift`:

```swift
import os

/// Intervals on Instruments' Points of Interest track: key handling, ✨ and the Back Tap stages. Next to free
/// while nothing is recording, so they stay on in every build.
enum Signposts {
    static let signposter = OSSignposter(subsystem: "com.ibrokhim.dmtranslator", category: .pointsOfInterest)

    static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
    }

    static func measureAsync<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await body()
    }
}
```

- [ ] **Step 3: `KeyboardDiagnostics`**

`ios/Keyboard/Diagnostics/KeyboardDiagnostics.swift`:

```swift
import UIKit

/// One keyboard appearance under the Diagnostika switch. Costs nothing between keystrokes — no timers, no
/// threads: a run loop observer, a notification and two process snapshots. `finish()` builds the summary.
@MainActor
final class KeyboardDiagnostics {
    var journal: TouchJournal
    private let startDate = Date()
    private let startUptime: TimeInterval
    private let startCPU = ProcessStats.cpuSeconds()
    private let startMemory = ProcessStats.memoryMB()
    private var memoryWarnings = 0
    private var thermal: [DiagnosticSession.Thermal] = []
    private var thermalObserver: NSObjectProtocol?
    private let mainThread = MainThreadMonitor()

    init(testMode: Bool) {
        let uptime = ProcessInfo.processInfo.systemUptime
        startUptime = uptime
        journal = TouchJournal(keepsDetail: testMode, start: uptime)
        thermal = [.init(state: ProcessInfo.processInfo.thermalState.name, t: 0)]
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordThermalState() }
        }
        mainThread.start()
    }

    func memoryWarning() {
        memoryWarnings += 1
    }

    func finish() -> DiagnosticSession {
        mainThread.stop()
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        thermalObserver = nil
        let duration = ProcessInfo.processInfo.systemUptime - startUptime
        let cpuSeconds = ProcessStats.cpuSeconds() - startCPU
        return DiagnosticSession(
            start: startDate, duration: duration, testMode: journal.keepsDetail,
            touches: journal.touches, typed: journal.typed, outcomes: journal.outcomes, zones: journal.zones,
            upToInsertMs: .init(samples: journal.upToInsertMs), deliveryMs: .init(samples: journal.deliveryMs),
            mainBusy: mainThread.summary,
            cpu: .init(seconds: cpuSeconds, percent: duration > 0 ? cpuSeconds / duration * 100 : 0),
            memoryMB: .init(start: startMemory, end: ProcessStats.memoryMB(), warnings: memoryWarnings),
            thermal: thermal, detail: journal.keepsDetail ? journal.detail : nil)
    }

    private func recordThermalState() {
        thermal.append(.init(
            state: ProcessInfo.processInfo.thermalState.name,
            t: ProcessInfo.processInfo.systemUptime - startUptime))
    }
}

/// How long the main run loop stays busy between two sleeps. A stretch over 50 ms is what feels like a stuck key.
final class MainThreadMonitor {
    private var observer: CFRunLoopObserver?
    private var wokeAt: TimeInterval?
    private var over50ms = 0
    private var maxMs: Double = 0

    var summary: DiagnosticSession.MainBusy { .init(over50ms: over50ms, maxMs: maxMs) }

    func start() {
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { [weak self] _, activity in
            self?.handle(activity)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    func stop() {
        guard let observer else { return }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = nil
    }

    private func handle(_ activity: CFRunLoopActivity) {
        let now = ProcessInfo.processInfo.systemUptime
        if activity.contains(.afterWaiting) {
            wokeAt = now
        } else if activity.contains(.beforeWaiting), let wokeAt {
            let ms = (now - wokeAt) * 1000
            if ms > 50 { over50ms += 1 }
            maxMs = max(maxMs, ms)
            self.wokeAt = nil
        }
    }
}

/// Process-wide CPU time and memory, read twice per session.
enum ProcessStats {
    /// User + system CPU time of all threads, finished ones included, in seconds.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// The footprint jetsam judges the extension by, in MB.
    static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }
}

extension ProcessInfo.ThermalState {
    var name: String {
        switch self {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
```

- [ ] **Step 4: Model va controller**

`ios/Keyboard/KeyboardModel.swift` — `@ObservationIgnored weak var controller: UIInputViewController?` dan keyin qo'shing:

```swift
    /// Set while the Diagnostika switch records this appearance; `KeysUIView` writes touches into its journal.
    @ObservationIgnored var diagnostics: KeyboardDiagnostics?
```

`magic()` ichidagi so'rovni signpost bilan o'rang — bu qatorlarni:

```swift
                let result = try await Translator.rewrite(
                    draft: draft, context: context, friend: friend, language: language)
```

quyidagiga almashtiring:

```swift
                let result = try await Signposts.measureAsync("rewrite") {
                    try await Translator.rewrite(draft: draft, context: context, friend: friend, language: language)
                }
```

`ios/Keyboard/KeyboardViewController.swift` ni to'liq quyidagiga almashtiring (Task 1 o'zgarishlari saqlangan):

```swift
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var stateObserver: DarwinObserver?
    private var heightConstraint: NSLayoutConstraint?
    private var diagnostics: KeyboardDiagnostics?

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        model.controller = self

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.totalHeight(barExpanded: false))
        height.priority = UILayoutPriority(999)
        heightConstraint = height
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
        host.didMove(toParent: self)

        // Back Tap can fire while the keyboard is already on screen.
        stateObserver = DarwinObserver(name: AppGroup.stateChanged) { [weak self] in
            self?.model.reloadState()
        }
        trackBarHeight()
        #if DEBUG
        simulatedBackTapObserver = DarwinObserver(name: AppGroup.simulatedBackTap) {
            Self.runSimulatedBackTap()
        }
        #endif
    }

    #if DEBUG
    private var simulatedBackTapObserver: DarwinObserver?

    /// The Simulator has no Back Tap and no Shortcuts app. `tools/simulate-back-tap.sh` drops a screenshot
    /// into the App Group and posts `AppGroup.simulatedBackTap`; this runs the same analysis the intent would.
    private static func runSimulatedBackTap() {
        guard let url = SharedStore.containerURL?.appendingPathComponent("simulated-back-tap.jpg"),
              let data = try? Data(contentsOf: url)
        else { return }
        Task { try? await ChatAnalysisService.run(imageData: data, fromShortcut: false) }
    }
    #endif

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        model.showsGlobe = needsInputModeSwitchKey
        model.now = Date()
        model.reloadState()
        model.scheduleRefresh()
        model.confirmFullAccess()
        model.prepareHaptics()
        model.autoCapitalize()
        startDiagnostics()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.stopRefresh()
        finishDiagnostics()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        diagnostics?.memoryWarning()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.autoCapitalize()
    }

    // MARK: Diagnostics

    /// One session per appearance, only while the app's Diagnostika switch is on. Needs Full Access: without it
    /// the keyboard cannot write to the App Group.
    private func startDiagnostics() {
        finishDiagnostics()
        guard hasFullAccess, model.state.diagnosticsEnabled == true else { return }
        let session = KeyboardDiagnostics(testMode: isDiagnosticsTestField)
        diagnostics = session
        model.diagnostics = session
    }

    private func finishDiagnostics() {
        guard let session = diagnostics else { return }
        diagnostics = nil
        model.diagnostics = nil
        let result = session.finish()
        // A keyboard that flashed up and away tells nothing.
        guard result.duration >= 1 else { return }
        DispatchQueue.global(qos: .utility).async {
            DiagnosticsStore.append(result)
            DarwinNotification.post(AppGroup.diagnosticsChanged)
        }
    }

    /// The app's typing-test field marks itself; only there does the journal keep individual touches.
    private var isDiagnosticsTestField: Bool {
        let contentType: UITextContentType? = textDocumentProxy.textContentType ?? nil
        if contentType?.rawValue == DiagnosticsMarker.contentType { return true }
        // In case iOS does not hand a custom content type to the keyboard: a trait pair no chat field uses.
        // Not `.asciiCapable` — iOS keeps keyboards that are not ASCII-capable, like this one, out of such fields.
        return textDocumentProxy.returnKeyType == UIReturnKeyType.continue
            && textDocumentProxy.autocorrectionType == UITextAutocorrectionType.no
    }

    /// The keyboard grows by the chip row only while the row has something in it. SwiftUI cannot
    /// resize an input view itself, so follow `barExpanded` and move the height constraint.
    private func trackBarHeight() {
        let expanded = withObservationTracking {
            model.barExpanded
        } onChange: { [weak self] in
            // Fires before the change is applied; read the new value on the next turn.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.trackBarHeight() } }
        }
        let height = KeyboardMetrics.totalHeight(barExpanded: expanded)
        guard let heightConstraint, heightConstraint.constant != height else { return }
        heightConstraint.constant = height
        guard view.window != nil else { return }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.view.superview?.layoutIfNeeded()
        }
    }
}

/// Opting in to `UIInputViewAudioFeedback` is what lets `UIDevice.playInputClick()` make the system key click.
final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
```

- [ ] **Step 5: Back Tap bosqichlariga signpost**

`ios/Shared/ChatAnalysisService.swift` — `run` ichida:

```swift
            let jpeg = try ScreenshotImage.jpeg(from: imageData)
```

→

```swift
            let jpeg = try Signposts.measure("prepareImage") { try ScreenshotImage.jpeg(from: imageData) }
```

`ios/Shared/Translator.swift` — `analyze` ichida `detailsTask` va `quick` chaqiruvlarini o'rang:

```swift
        let detailsTask = Task {
            try await Signposts.measureAsync("details") {
                try await Gemini.generate(
                    ChatDetails.self, system: Prompts.detailsSystem, parts: [.jpeg(jpeg)], schema: Prompts.detailsSchema)
            }
        }
```

```swift
            quick = try await Signposts.measureAsync("quickRead") {
                try await Gemini.generate(
                    QuickRead.self, system: Prompts.quickSystem, parts: quickParts, schema: Prompts.quickSchema)
            }
```

`ios/Shared/Gemini.swift` — `call` ichida:

```swift
        let (data, response) = try await URLSession.shared.data(for: request)
```

→

```swift
        let (data, response) = try await Signposts.measureAsync("gemini") {
            try await URLSession.shared.data(for: request)
        }
```

- [ ] **Step 6: Build va testlar**

Run: BUILD → Expected: `** BUILD SUCCEEDED **` (klaviatura, ilova).
Run: TEST → Expected: 36 test, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/Keyboard/Diagnostics/KeyboardDiagnostics.swift ios/Shared/Signposts.swift ios/Shared/SharedStore.swift ios/Keyboard/KeyboardModel.swift ios/Keyboard/KeyboardViewController.swift ios/Shared/ChatAnalysisService.swift ios/Shared/Translator.swift ios/Shared/Gemini.swift && git commit -q -F - <<'EOF'
iOS: klaviatura diagnostika sessiyasi va signpost'lar

Diagnostika yoqiq bo'lsa klaviatura har ko'rinishida sessiya yig'adi:
asosiy oqim qotishlari (runloop kuzatuvchisi), harorat holati, CPU vaqti va
xotira; yopilganda diagnostics.json ga yoziladi. Tugma, ✨ va Back Tap
bosqichlari Instruments'ning Points of Interest trekida ko'rinadi.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: `KeysUIView` `TouchTracker` ga o'tadi

**Files:**
- Modify: `ios/Keyboard/KeysUIView.swift:1-357` (`// MARK: - Key cap` dan yuqoridagi hamma narsa; `KeyCapView` va `KeyPopupView` o'zgarmaydi)

**Interfaces:**
- Consumes: `TouchTracker` (Task 2), `TouchJournal.KeyPosition` (Task 4), `KeyboardModel.diagnostics` (Task 5), `Signposts.measure` (Task 5).
- Produces: `KeysUIView.Key.kind: TouchTracker.KeyKind`.

- [ ] **Step 1: Fayl boshini almashtirish**

`ios/Keyboard/KeysUIView.swift` da 1-qatordan `// MARK: - Key cap` qatorigacha (u qator kirmaydi) bo'lgan hamma narsani quyidagiga almashtiring:

```swift
import SwiftUI
import UIKit

/// SwiftUI slot for the UIKit key area. Only the layout inputs are passed in, so typing
/// (which changes none of them) never goes through SwiftUI at all.
struct KeysRepresentable: UIViewRepresentable {
    let model: KeyboardModel
    let config: KeysUIView.Config

    func makeUIView(context: Context) -> KeysUIView { KeysUIView(model: model) }

    func updateUIView(_ view: KeysUIView, context: Context) { view.apply(config) }
}

/// The key area in plain UIKit. SwiftUI gestures added a noticeable delay per press and the key
/// popup often never rendered on a quick tap; here touches arrive in `touchesBegan` directly.
/// What a touch does is decided by `TouchTracker`; this view draws the keys and carries out its actions.
final class KeysUIView: UIView {
    struct Config: Equatable {
        var layer: KeyboardModel.Layer
        var shift: KeyboardModel.Shift
        var alphabet: KeyboardModel.Alphabet
        var showsGlobe: Bool
        /// App setting: an emoji key replaces КИР/LAT.
        var emojiKey: Bool
    }

    enum Key: Equatable {
        case char(String)
        case shift, backspace, globe, space, newline, alphabet, emoji
        case layer(KeyboardModel.Layer, String)

        var kind: TouchTracker.KeyKind {
            switch self {
            case .char: .character
            case .space: .space
            case .newline: .newline
            case .backspace: .backspace
            case .shift: .shift
            case .globe, .alphabet, .emoji, .layer: .function
            }
        }
    }

    private static let latin = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
    /// Uzbek Cyrillic on the ЙЦУКЕН base; ғ and ҳ sit in the bottom row, like oʻ/gʻ in Latin.
    private static let cyrillic = [
        ["й", "ц", "у", "к", "е", "н", "г", "ш", "ў", "з", "х", "ъ"],
        ["ф", "қ", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
        ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"],
    ]
    private static let numbers = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
    ]
    private static let symbols = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
    ]
    private static let punctuation = [".", ",", "?", "!", "'"]

    private let model: KeyboardModel
    private var config: Config?
    private var needsRebuild = true
    private var builtWidth: CGFloat = 0
    private var caps: [KeyCapView] = []
    private var hitFrames: [CGRect] = []
    private var positions: [TouchJournal.KeyPosition] = []
    private var tracker = TouchTracker()
    private let popup = KeyPopupView()
    private var repeatTimer: Timer?

    init(model: KeyboardModel) {
        self.model = model
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ new: Config) {
        let old = config
        guard new != old else { return }
        config = new
        if old?.layer != new.layer || old?.alphabet != new.alphabet || old?.showsGlobe != new.showsGlobe
            || old?.emojiKey != new.emojiKey {
            needsRebuild = true
            setNeedsLayout()
        } else {
            updateLabels()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard config != nil, bounds.width > 0, needsRebuild || builtWidth != bounds.width else { return }
        rebuild()
    }

    // MARK: Layout

    private func rows(width: CGFloat, config: Config) -> [[(Key, CGFloat)]] {
        let gap = KeyboardMetrics.keyGap
        let full = width - KeyboardMetrics.sideInset * 2
        let baseUnit = (full - gap * 9) / 10
        var rows: [[(Key, CGFloat)]] = []

        switch config.layer {
        case .letters:
            let letters = config.alphabet == .latin ? Self.latin : Self.cyrillic
            let columns = CGFloat(letters[0].count)
            let unit = (full - gap * (columns - 1)) / columns
            let bottomLetters = CGFloat(letters[2].count)
            let side = (full - unit * bottomLetters - gap * (bottomLetters + 1)) / 2
            rows.append(letters[0].map { (.char($0), unit) })
            rows.append(letters[1].map { (.char($0), unit) })
            rows.append([(.shift, side)] + letters[2].map { (.char($0), unit) } + [(.backspace, side)])
        case .numbers, .symbols:
            let chars = config.layer == .numbers ? Self.numbers : Self.symbols
            let toggle: Key = config.layer == .numbers ? .layer(.symbols, "#+=") : .layer(.numbers, "123")
            let side = baseUnit * 1.5 + gap / 2
            let punctuationWidth = (full - side * 2 - gap * 6) / 5
            rows.append(chars[0].map { (.char($0), baseUnit) })
            rows.append(chars[1].map { (.char($0), baseUnit) })
            rows.append([(toggle, side)] + Self.punctuation.map { (.char($0), punctuationWidth) } + [(.backspace, side)])
        }

        var bottom: [(Key, CGFloat)] = []
        bottom.append((config.layer == .letters ? .layer(.numbers, "123") : .layer(.letters, "ABC"), baseUnit * 1.25))
        if config.showsGlobe { bottom.append((.globe, baseUnit * 1.1)) }
        if config.layer == .letters {
            bottom.append((config.emojiKey ? .emoji : .alphabet, baseUnit * 1.25))
            let extras = config.alphabet == .latin ? ["oʻ", "gʻ"] : ["ғ", "ҳ"]
            bottom += extras.map { (.char($0), baseUnit) }
        }
        let returnWidth = baseUnit * 2
        let used = bottom.reduce(0) { $0 + $1.1 } + returnWidth + gap * CGFloat(bottom.count + 1)
        bottom.append((.space, max(baseUnit * 2, full - used)))
        bottom.append((.newline, returnWidth))
        rows.append(bottom)
        return rows
    }

    private func rebuild() {
        guard let config else { return }
        // Types what a finger still holds on the old keys before they go away (it used to be dropped).
        run(.willRebuild)
        caps.forEach { $0.removeFromSuperview() }
        caps = []
        hitFrames = []
        positions = []

        let gap = KeyboardMetrics.keyGap
        let rowGap = KeyboardMetrics.rowGap
        let keyHeight = KeyboardMetrics.keyHeight
        let rows = rows(width: bounds.width, config: config)
        var y = KeyboardMetrics.keysTopInset
        for (rowIndex, row) in rows.enumerated() {
            let total = row.reduce(0) { $0 + $1.1 } + gap * CGFloat(row.count - 1)
            var x = (bounds.width - total) / 2
            for (column, (key, width)) in row.enumerated() {
                let cap = KeyCapView(key: key)
                cap.frame = CGRect(x: x, y: y, width: width, height: keyHeight)
                addSubview(cap)
                caps.append(cap)
                // Gaps belong to the nearest key; the outer keys own everything up to the edges.
                let left = column == 0 ? 0 : x - gap / 2
                let right = column == row.count - 1 ? bounds.width : x + width + gap / 2
                let top = rowIndex == 0 ? 0 : y - rowGap / 2
                let bottomEdge = rowIndex == rows.count - 1 ? bounds.height : y + keyHeight + rowGap / 2
                hitFrames.append(CGRect(x: left, y: top, width: right - left, height: bottomEdge - top))
                positions.append(TouchJournal.KeyPosition(
                    row: rowIndex, column: column, rowLength: row.count, isBottomRow: rowIndex == rows.count - 1))
                x += width + gap
            }
            y += keyHeight + rowGap
        }
        tracker.keys = caps.map(\.key.kind)
        builtWidth = bounds.width
        needsRebuild = false
        updateLabels()
    }

    private func updateLabels() {
        guard let config else { return }
        for cap in caps { cap.configure(config) }
    }

    private func keyIndex(at point: CGPoint) -> Int? {
        hitFrames.firstIndex { $0.contains(point) }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let alive = Set((event?.allTouches ?? touches).map { ObjectIdentifier($0) })
        for touch in touches {
            let point = touch.location(in: self)
            guard let key = keyIndex(at: point) else { continue }
            run(.began(id: ObjectIdentifier(touch), key: key, x: point.x, time: touch.timestamp, alive: alive))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            run(.moved(id: ObjectIdentifier(touch), key: keyIndex(at: point), x: point.x))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            run(.ended(id: ObjectIdentifier(touch), time: touch.timestamp))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            run(.cancelled(id: ObjectIdentifier(touch)))
        }
    }

    /// Feeds one event to the tracker and carries out its actions. With Diagnostika on, the outcomes and their
    /// timing go to the session journal (`systemUptime` is the clock `UITouch.timestamp` uses).
    private func run(_ event: TouchTracker.Event) {
        let handledAt = ProcessInfo.processInfo.systemUptime
        let output = Signposts.measure("touch") { () -> TouchTracker.Output in
            let output = tracker.handle(event)
            output.actions.forEach(perform)
            return output
        }
        guard !output.records.isEmpty, let diagnostics = model.diagnostics else { return }
        let doneAt = ProcessInfo.processInfo.systemUptime
        for record in output.records where record.key < positions.count {
            diagnostics.journal.record(
                record, at: positions[record.key], kind: tracker.keys[record.key],
                handledAt: handledAt, doneAt: doneAt)
        }
    }

    private func perform(_ action: TouchTracker.Action) {
        switch action {
        case .keyDown:
            model.keyDown()
        case .type(let key):
            if case .char(let character) = caps[key].key { model.type(character) }
        case .space:
            model.space()
        case .newline:
            model.newline()
        case .backspace:
            model.backspace()
        case .shift:
            model.tapShift()
        case .release(let key):
            release(caps[key].key)
        case .press(let key):
            caps[key].isPressed = true
        case .unpress(let key):
            if key < caps.count { caps[key].isPressed = false }
        case .startRepeat:
            startRepeat()
        case .stopRepeat:
            stopRepeat()
        case .beginCursorDrag(let key):
            caps[key].showDragHint()
        case .endCursorDrag(let key):
            if key < caps.count, let config { caps[key].configure(config) }
        case .moveCursor(let offset):
            model.moveCursor(by: offset)
        case .showPopup(let key):
            showPopup(key)
        case .hidePopup:
            popup.isHidden = true
        }
    }

    private func release(_ key: Key) {
        switch key {
        case .globe: model.switchKeyboard()
        case .alphabet: model.toggleAlphabet()
        case .emoji: model.showsEmoji = true
        case .layer(let layer, _): model.setLayer(layer)
        case .char, .shift, .backspace, .space, .newline: break
        }
    }

    private func startRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.model.backspace() }
                }
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    // MARK: Popup

    /// Drawn in the keyboard's root view so the top row's popup can rise over the suggestion bar.
    private func showPopup(_ key: Int) {
        guard let host = model.controller?.view ?? superview else { return }
        let cap = caps[key]
        popup.show(text: cap.displayText, keyFrame: convert(cap.frame, to: host), in: host)
    }
}

```

- [ ] **Step 2: Build va testlar**

Run: BUILD → Expected: `** BUILD SUCCEEDED **`.
Run: TEST → Expected: 36 test, `** TEST SUCCEEDED **`.

- [ ] **Step 3: Simulator'da yozib ko'rish**

```bash
cd ~/Desktop/side-projects/ai-keyboard/ios && xcrun simctl boot A68FA497-8B43-4D49-949B-92D20087F069 2>/dev/null; xcrun simctl install A68FA497-8B43-4D49-949B-92D20087F069 build/Build/Products/Debug-iphonesimulator/Tarjimon.app && xcrun simctl launch A68FA497-8B43-4D49-949B-92D20087F069 com.ibrokhim.dmtranslator -focusTestField YES
```

iOS Simulator boshqaruvi (`mcp__Claude_Code_iOS_Simulator__control`, `device: A68FA497-8B43-4D49-949B-92D20087F069`): `screenshot` → AI Keyboard ochiqligini tekshiring (bo'lmasa globus bilan almashtiring) → `s`, `a`, `l`, `o`, `m`, bo'sh joy, `1`-qatlamga o'tib `!` bosing → `screenshot`.
Expected: test maydonida `Salom !` (avtomatik bosh harf bilan), `123` → `!` dan keyin bo'sh joy harflar qatlamiga qaytaradi; popup chiqadi va yo'qoladi; ⌫ bosib turilganda takrorlanadi.

- [ ] **Step 4: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/Keyboard/KeysUIView.swift && git commit -q -F - <<'EOF'
iOS: tugmalar maydoni TouchTracker orqali ishlaydi

KeysUIView endi faqat UIKit teginishlarini TouchTracker'ga uzatadi va uning
amallarini bajaradi. Diagnostika yoqiq bo'lsa har teginish natijasi va
kechikishi sessiya jurnaliga yoziladi.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 7: Ilovadagi Diagnostika ekrani

**Files:**
- Create: `ios/App/DiagnosticsView.swift`
- Modify: `ios/App/ContentView.swift` (`body` dagi `Form`, yangi `diagnosticsSection`)

**Interfaces:**
- Consumes: `SharedStateModel` (`ContentView.swift`), `SharedState.diagnosticsEnabled`, `AppGroup.diagnosticsChanged` (Task 5), `DiagnosticsStore`, `DiagnosticSession`, `DiagnosticsMarker`, `PhraseDiff` (Task 3), `DarwinObserver` (bor).
- Produces: `DiagnosticsView(store: SharedStateModel)`, `DiagnosticsLog`.

- [ ] **Step 1: `DiagnosticsView.swift`**

`ios/App/DiagnosticsView.swift`:

```swift
import SwiftUI

/// Sessions the keyboard recorded, live: the keyboard posts `AppGroup.diagnosticsChanged` after writing one.
@MainActor
final class DiagnosticsLog: ObservableObject {
    @Published private(set) var sessions: [DiagnosticSession] = []
    private var observer: DarwinObserver?

    init() {
        observer = DarwinObserver(name: AppGroup.diagnosticsChanged) { [weak self] in self?.reload() }
        reload()
    }

    /// Newest first.
    func reload() {
        sessions = DiagnosticsStore.load().reversed()
    }

    func clear() {
        DiagnosticsStore.clear()
        reload()
    }
}

/// Diagnostika: the keyboard's session recording switch, the typing test and the recorded sessions.
struct DiagnosticsView: View {
    @ObservedObject var store: SharedStateModel
    @StateObject private var log = DiagnosticsLog()
    @State private var typed = ""
    @State private var diff: PhraseDiff?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Diagnostika", isOn: Binding(
                    get: { store.state.diagnosticsEnabled ?? false },
                    set: { on in store.update { $0.diagnosticsEnabled = on } }
                ))
            } footer: {
                Text("Yoqilganda klaviatura har ochilishida qisqa hisobot yozadi: teginishlar, yo'qolganlari, kechikish, CPU, harorat. Yozilgan matn saqlanmaydi. Full Access kerak.")
            }
            testSection
            sessionsSection
        }
        .navigationTitle("Diagnostika")
        .onAppear { log.reload() }
    }

    // MARK: Typing test

    private var testSection: some View {
        Section {
            Text(PhraseDiff.testPhrase).font(.callout)
            TextField("Iborani AI Keyboard bilan shu yerga yozing", text: $typed, axis: .vertical)
                .lineLimit(3...8)
                .focused($fieldFocused)
                .textContentType(UITextContentType(rawValue: DiagnosticsMarker.contentType))
                .submitLabel(.continue)
                .autocorrectionDisabled()
            HStack {
                Button("Tugatish") {
                    fieldFocused = false
                    diff = PhraseDiff.compare(expected: PhraseDiff.testPhrase, typed: typed)
                }
                .disabled(typed.isEmpty)
                .buttonStyle(.borderless)
                Spacer()
                Button("Qaytadan", role: .destructive) {
                    typed = ""
                    diff = nil
                }
                .buttonStyle(.borderless)
            }
            if let diff { testResult(diff) }
        } header: {
            Text("Yozish testi")
        } footer: {
            Text("Diagnostika yoqiq bo'lsin. Iborani odatdagidek yozing, xatolarni tuzatmang, keyin «Tugatish».")
        }
    }

    @ViewBuilder
    private func testResult(_ diff: PhraseDiff) -> some View {
        let session = log.sessions.first { $0.testMode }
        VStack(alignment: .leading, spacing: 4) {
            Text(diff.isPerfect
                ? "Matn to'liq mos"
                : "Tushib qolgan: \(diff.missing) · ortiqcha: \(diff.extra) · almashgan: \(diff.substituted)")
                .font(.headline)
            if let session {
                Text("Klaviatura: \(session.touches) teginish, \(session.typed) harf, bekor qilingan \(session.lost), tiklangan \(session.outcomes[TouchOutcome.recoveredMissingEnd.rawValue] ?? 0)")
                    .font(.footnote)
                if diff.missing > 0 && session.lost == 0 {
                    Text("Harf yo'qolgan, lekin klaviatura hech narsani yo'qotmagan — teginish klaviaturaga yetib kelmagan (tizim darajasi).")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Klaviatura hisoboti hali kelmadi — Diagnostika yoqiqmi?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Sessions

    private var sessionsSection: some View {
        Section {
            if log.sessions.isEmpty {
                Text("Hali sessiya yo'q").foregroundStyle(.secondary)
            }
            ForEach(log.sessions) { session in
                SessionRow(session: session)
            }
            if let url = DiagnosticsStore.fileURL, !log.sessions.isEmpty {
                ShareLink(item: url) {
                    Label("JSON eksport", systemImage: "square.and.arrow.up")
                }
                Button("Tozalash", role: .destructive) { log.clear() }
            }
        } header: {
            Text("Sessiyalar")
        }
    }
}

private struct SessionRow: View {
    let session: DiagnosticSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(session.start, style: .time)
                Text(String(format: "%.0f s", session.duration)).foregroundStyle(.secondary)
                if session.testMode {
                    Text("test")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                Spacer()
                Text(session.thermal.map(\.state).joined(separator: "→"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(session.touches) teginish · yo'qolgan \(session.lost) · p95 \(milliseconds(session.upToInsertMs?.p95)) · CPU \(String(format: "%.1f", session.cpu.percent))% · \(String(format: "%.0f", session.memoryMB.end)) MB")
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.mainBusy.over50ms > 0 {
                Text("Asosiy oqim > 50 ms: \(session.mainBusy.over50ms) marta, eng uzuni \(String(format: "%.0f", session.mainBusy.maxMs)) ms")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func milliseconds(_ value: Double?) -> String {
        value.map { String(format: "%.1f ms", $0) } ?? "—"
    }
}
```

- [ ] **Step 2: `ContentView` ga havola**

`ios/App/ContentView.swift` — `body` dagi `Form` ichida `keyboardSection` dan keyin qo'shing:

```swift
                diagnosticsSection
```

`keyboardSection` xususiyatidan keyin yangi xususiyat:

```swift
    private var diagnosticsSection: some View {
        Section {
            NavigationLink {
                DiagnosticsView(store: store)
            } label: {
                Label("Diagnostika", systemImage: "stethoscope")
            }
        }
    }
```

- [ ] **Step 3: Build va testlar**

Run: BUILD → Expected: `** BUILD SUCCEEDED **`.
Run: TEST → Expected: 36 test, `** TEST SUCCEEDED **`.

- [ ] **Step 4: Simulator'da uchdan-uchga tekshirish**

```bash
cd ~/Desktop/side-projects/ai-keyboard/ios && xcrun simctl install A68FA497-8B43-4D49-949B-92D20087F069 build/Build/Products/Debug-iphonesimulator/Tarjimon.app && xcrun simctl launch --terminate-running-process A68FA497-8B43-4D49-949B-92D20087F069 com.ibrokhim.dmtranslator
```

Simulator boshqaruvi bilan: Diagnostika → tugmani yoqing → test maydoniga bosing → AI Keyboard bilan `salom` yozing → «Tugatish» → `screenshot`.
Expected:
- "Sessiyalar" da yangi qator paydo bo'ladi, unda **`test`** belgisi bor (marker klaviaturaga yetib kelgan). `test` bo'lmasa — `textContentType` ham, zaxira trait juftligi ham yetmagan: STOP, sababni aniqlang (`isDiagnosticsTestField`).
- Qatorda teginishlar soni ≥ 5, `yo'qolgan 0`, p95 qiymati bor.
- Natija: `Tushib qolgan: ...` (ibora to'liq yozilmagani uchun) va "Klaviatura: N teginish ..." qatori.

Faylni to'g'ridan-to'g'ri ko'rish:

```bash
cat "$(xcrun simctl get_app_container A68FA497-8B43-4D49-949B-92D20087F069 com.ibrokhim.dmtranslator group.com.ibrokhim.dmtranslator)/diagnostics.json" | head -60
```

Expected: `"testMode" : true`, `"detail"` massivida `key`, `kind`, `outcome` — **harflar yo'q**.

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add ios/App/DiagnosticsView.swift ios/App/ContentView.swift && git commit -q -F - <<'EOF'
iOS: ilovada Diagnostika ekrani

Diagnostika tugmasi, yozish testi (iborani yozilgan matn bilan solishtirib,
klaviatura jurnali bilan yonma-yon ko'rsatadi), sessiyalar ro'yxati va JSON
eksport.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 8: Hujjatlar va yakuniy tekshiruv

**Files:**
- Modify: `CONTRIBUTING.md` ("Sinash" bo'limi)
- Modify: `.github/pull_request_template.md` ("Tekshiruv" bo'limi)

- [ ] **Step 1: CONTRIBUTING**

`CONTRIBUTING.md` da "## Sinash" bo'limidagi ro'yxat oxiriga (`- Issue va PR'larga **haqiqiy DM skrinshotlarini qo'ymang** ...` bandidan oldin) qo'shing:

```markdown
- **Unit testlar** (teginish mantig'i, muddatlar, diagnostika):
  `cd ios && xcodegen generate && xcodebuild test -project AIKeyboard.xcodeproj -scheme Tarjimon -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AIKeyboardTests`
- **Diagnostika**: ilovada Diagnostika → yoqing. Klaviatura har ochilishida qisqa hisobot yozadi (teginishlar,
  yo'qolganlari, kechikish, CPU, harorat — yozilgan matn saqlanmaydi). «Yozish testi» harf yo'qolishini tekshiradi.
  Instruments'ning Points of Interest trekida tugma, ✨ va Back Tap bosqichlari ko'rinadi.
```

- [ ] **Step 2: PR shabloni**

`.github/pull_request_template.md` da `- [ ] \`ios/\` da \`xcodegen generate\` va Xcode build xatosiz o'tadi` qatoridan keyin qo'shing:

```markdown
- [ ] `ios/` da unit testlar o'tadi (`xcodebuild test ... -only-testing:AIKeyboardTests`)
```

- [ ] **Step 3: Yakuniy tekshiruv**

Run: TEST → Expected: 36 test, `** TEST SUCCEEDED **`.

Release build (Instruments M2'da shu konfiguratsiya bilan o'lchanadi):

```bash
cd ~/Desktop/side-projects/ai-keyboard/ios && xcodebuild -project AIKeyboard.xcodeproj -scheme Tarjimon -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|\*\* BUILD" | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

Sirlar tekshiruvi:

```bash
cd ~/Desktop/side-projects/ai-keyboard && git diff --name-only main...HEAD | grep -iE "secrets\.swift$|local\.properties|keystore|\.jks|xcodeproj" || echo "toza"; git log -p main..HEAD | grep -cE "AIza[0-9A-Za-z_-]{20,}"; git log --format='%ae' main..HEAD | sort -u
```

Expected: `toza`, `0`, faqat `95557944+ibroxiim@users.noreply.github.com`.

- [ ] **Step 4: Commit**

```bash
cd ~/Desktop/side-projects/ai-keyboard && git add CONTRIBUTING.md .github/pull_request_template.md && git commit -q -F - <<'EOF'
Hujjatlar: iOS unit testlar va Diagnostika

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

M1 tugadi. Keyingi qadam — foydalanuvchidan push/PR tasdig'ini olish va M2 o'lchov sessiyasi (spec, "M2 — O'lchov sessiyasi").

---

## Bajarilish paytidagi o'zgarishlar (2026-09-28)

- **Test maydoni belgisi:** `.keyboardType(.asciiCapable)` olib tashlandi — `IsASCIICapable: false` bo'lgan klaviaturani
  iOS bunday maydonlarga qo'ymaydi (Simulator'da Apple klaviaturasi ochildi). Zaxira belgi: `returnKeyType == .continue`
  va `autocorrectionType == .no`. Simulator'da test sessiyasi `testMode: true` bilan yozildi.
- **`PhraseDiff.unfinished`:** iborani oxirigacha yozmaslik "tushib qolgan" deb hisoblanmaydi — yozilgan matn iboraning
  eng mos boshlanishi bilan tekislanadi, qolgani `unfinished`. Test: `testStoppingEarlyIsNotCountedAsMissing`,
  `testEmptyTypedTextIsAllUnfinished` (jami 37 test). Ekrandagi ogohlantirish matni ham aniqlashtirildi.
