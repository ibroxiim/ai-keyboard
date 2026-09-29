import Foundation

/// "Whichever answers first": starts `attempt` for the first option and, while nothing has succeeded, for the
/// next one whenever the newest attempt stays quiet for `delay` or an attempt fails with an error `isRetriable`
/// accepts. The first success wins and the others are cancelled. A non-retriable failure with nothing else in
/// flight ends it at once — the next option would fail the same way.
enum Hedge {
    private enum Event<T> {
        case success(T)
        case failure(Error)
        /// The timer armed when option `index` was started.
        case timer(index: Int)
    }

    static func first<Option, T>(
        _ options: [Option], after delay: Duration, isRetriable: @escaping (Error) -> Bool,
        attempt: @escaping (Option) async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: Event<T>.self) { group in
            var started = 0
            var running = 0
            var lastError: Error = CancellationError()

            func startNext() {
                let index = started
                let option = options[index]
                started += 1
                running += 1
                group.addTask {
                    do { return .success(try await attempt(option)) } catch { return .failure(error) }
                }
                if started < options.count {
                    group.addTask {
                        try? await Task.sleep(for: delay)
                        return .timer(index: index)
                    }
                }
            }

            guard !options.isEmpty else { throw lastError }
            startNext()
            while let event = try await group.next() {
                switch event {
                case .success(let value):
                    group.cancelAll()
                    return value
                case .failure(let error):
                    running -= 1
                    lastError = error
                    if error is CancellationError { throw error }
                    if isRetriable(error), started < options.count {
                        startNext()
                    } else if running == 0 {
                        throw error
                    }
                case .timer(let index):
                    // Only the newest attempt's timer counts; an older one can fire after a retry already moved on.
                    if index == started - 1, started < options.count, running > 0 {
                        startNext()
                    }
                }
            }
            throw lastError
        }
    }
}
