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
