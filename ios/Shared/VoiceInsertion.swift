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
        /// The session failed ("Ovoz eshitilmadi", no microphone): tell the user once, then forget the session,
        /// or the bar would show the error instead of the target pill for as long as the session lived.
        case failed(String)
    }

    static func decision(voice: VoiceState?, pendingID: String?, now: Date) -> Decision {
        guard let voice, voice.isLive(at: now) else { return .none }
        switch voice.phase {
        case .failed:
            return .failed(voice.error ?? "Ovozdan matn: xato")
        case .done:
            guard let text = voice.text, !text.isEmpty else { return .none }
            return voice.id == pendingID ? .insert(text) : .offer(text)
        case .recording, .transcribing:
            return .none
        }
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
