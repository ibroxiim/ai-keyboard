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
