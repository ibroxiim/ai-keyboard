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
