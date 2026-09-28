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
