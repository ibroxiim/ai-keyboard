import Foundation

/// How a Gemini request trades time for care. `fast` is for the keyboard's everyday use; `careful` is the app's
/// "Sifatli tarjima" setting, for translations only (voice dictation stays fast).
enum GeminiQuality: Equatable {
    case fast, careful

    /// Raced by `Hedge`, in this order. Which one is up changes day to day: on 2026-09-28 3.5-flash-lite took
    /// 14–27 s and 3.6-flash answered in 2–4 s; on 2026-09-29 3.6-flash returned 503 and lite answered in 2–3 s.
    /// All of them take `thinkingLevel: minimal` and `low` (3.7/3.8-flash do not).
    var models: [String] {
        switch self {
        case .fast: ["gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.1-flash-lite", "gemini-3.5-flash"]
        case .careful: ["gemini-3.6-flash", "gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite"]
        }
    }

    /// On Flash-Lite `low` did not read better than `minimal` (it made up slang), so it is only for `careful`,
    /// which starts with the larger models.
    var thinkingLevel: String {
        switch self {
        case .fast: "minimal"
        case .careful: "low"
        }
    }

    /// Per attempt.
    var attemptTimeout: TimeInterval {
        switch self {
        case .fast: 20
        case .careful: 30
        }
    }

    /// How long a model may stay quiet before the next one is started alongside it. A screenshot or a voice
    /// message takes longer to read than a rewrite, so it gets more time before paying for a second request.
    func hedgeDelay(media: Bool) -> Duration {
        let seconds: Int64 = media ? 6 : 4
        return .seconds(self == .careful ? seconds * 2 : seconds)
    }
}

extension SharedState {
    /// The user's "Sifatli tarjima" setting.
    var quality: GeminiQuality { qualityMode == true ? .careful : .fast }
}
