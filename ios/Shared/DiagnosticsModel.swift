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
