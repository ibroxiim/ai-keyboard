import XCTest

final class HedgeTests: XCTestCase {
    private struct Retriable: Error {}
    private struct Fatal: Error {}

    /// Which options were started and which got cancelled, from the attempts' own tasks.
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var _started: [String] = []
        private var _cancelled: [String] = []
        var started: [String] { lock.withLock { _started } }
        var cancelled: [String] { lock.withLock { _cancelled } }
        func start(_ option: String) { lock.withLock { _started.append(option) } }
        func cancel(_ option: String) { lock.withLock { _cancelled.append(option) } }
    }

    private enum Plan {
        case answer(after: Duration)
        case fail(Error, after: Duration)
    }

    private func run(_ plans: [String: Plan], order: [String], hedgeAfter: Duration, log: Log) async throws -> String {
        try await Hedge.first(order, after: hedgeAfter, isRetriable: { $0 is Retriable }) { option in
            log.start(option)
            do {
                switch plans[option]! {
                case .answer(let delay):
                    try await Task.sleep(for: delay)
                    return option
                case .fail(let error, let delay):
                    try await Task.sleep(for: delay)
                    throw error
                }
            } catch is CancellationError {
                log.cancel(option)
                throw CancellationError()
            }
        }
    }

    func testFastFirstAnswerStartsNothingElse() async throws {
        let log = Log()
        let result = try await run(["a": .answer(after: .milliseconds(10)), "b": .answer(after: .milliseconds(10))],
                                   order: ["a", "b"], hedgeAfter: .milliseconds(500), log: log)
        XCTAssertEqual(result, "a")
        XCTAssertEqual(log.started, ["a"])
    }

    func testSlowFirstStartsTheNextInParallelAndTheWinnerCancelsIt() async throws {
        let log = Log()
        let result = try await run(["a": .answer(after: .seconds(2)), "b": .answer(after: .milliseconds(10))],
                                   order: ["a", "b"], hedgeAfter: .milliseconds(100), log: log)
        XCTAssertEqual(result, "b")
        XCTAssertEqual(log.started, ["a", "b"])
        XCTAssertEqual(log.cancelled, ["a"])
    }

    func testRetriableFailureStartsTheNextRightAway() async throws {
        let log = Log()
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await run(["a": .fail(Retriable(), after: .milliseconds(10)), "b": .answer(after: .milliseconds(10))],
                                   order: ["a", "b"], hedgeAfter: .seconds(2), log: log)
        XCTAssertEqual(result, "b")
        XCTAssertLessThan(clock.now - start, .seconds(1))
    }

    func testFatalFailureWithNothingElseRunningThrowsIt() async {
        let log = Log()
        do {
            _ = try await run(["a": .fail(Fatal(), after: .milliseconds(10)), "b": .answer(after: .milliseconds(10))],
                              order: ["a", "b"], hedgeAfter: .seconds(2), log: log)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is Fatal)
            XCTAssertEqual(log.started, ["a"])
        }
    }

    func testWhenEveryOptionFailsTheLastErrorIsThrown() async {
        let log = Log()
        do {
            _ = try await run(["a": .fail(Retriable(), after: .milliseconds(10)), "b": .fail(Fatal(), after: .milliseconds(10))],
                              order: ["a", "b"], hedgeAfter: .seconds(2), log: log)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is Fatal)
            XCTAssertEqual(log.started, ["a", "b"])
        }
    }

    func testAStaleTimerDoesNotStartAnExtraOption() async throws {
        // a fails at 150 ms → b starts at once and has until 350 ms. a's own timer still fires at 200 ms, while b
        // runs; it must not start c too.
        let log = Log()
        let result = try await run(
            ["a": .fail(Retriable(), after: .milliseconds(150)), "b": .answer(after: .milliseconds(100)),
             "c": .answer(after: .milliseconds(10))],
            order: ["a", "b", "c"], hedgeAfter: .milliseconds(200), log: log)
        XCTAssertEqual(result, "b")
        XCTAssertEqual(log.started, ["a", "b"])
    }
}
