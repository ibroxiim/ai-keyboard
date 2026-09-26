import Foundation

struct Suggestion: Codable, Hashable, Identifiable {
    var text: String
    /// What `text` means in Uzbek, so the user knows exactly what they send.
    var uz: String
    var id: String { text }
}

/// What the model read from a DM screenshot. Built from two parallel Gemini calls
/// (`QuickRead` + `ChatDetails`); either half may be missing while it is in flight or if it failed.
struct ChatAnalysis: Codable, Equatable {
    struct Line: Codable, Equatable {
        var from: String // "me" | "them"
        var text: String
    }

    var partner: String
    var language: String
    var tone: String
    var lastIncomingUz: String
    var summaryUz: String
    var transcript: [Line]
    var suggestions: [Suggestion]

    /// The trailing run of messages from "them" — the thing the user is replying to.
    var lastIncoming: String {
        transcript.reversed().prefix { $0.from == "them" }.reversed().map(\.text).joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case partner, language, tone, transcript, suggestions
        case summaryUz = "summary_uz"
        case lastIncomingUz = "last_incoming_uz"
    }

    init(quick: QuickRead?, details: ChatDetails?) {
        // Instagram truncates long names in the chat header ("Christi...") and the model copies that.
        partner = (quick?.partner ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " .…"))
        language = quick?.language ?? ""
        tone = quick?.tone ?? ""
        lastIncomingUz = quick?.lastIncomingUz ?? ""
        summaryUz = details?.summaryUz ?? ""
        transcript = details?.transcript ?? []
        suggestions = details?.suggestions ?? []
    }
}

/// Small, fast half: who, which language, what the last message means. Shown first.
struct QuickRead: Decodable {
    var partner: String
    var language: String
    var tone: String
    var lastIncomingUz: String

    enum CodingKeys: String, CodingKey {
        case partner, language, tone
        case lastIncomingUz = "last_incoming_uz"
    }
}

/// Slower half: reply suggestions and the transcript ✨ uses as context.
struct ChatDetails: Decodable {
    var summaryUz: String
    var transcript: [ChatAnalysis.Line]
    var suggestions: [Suggestion]

    enum CodingKeys: String, CodingKey {
        case transcript, suggestions
        case summaryUz = "summary_uz"
    }
}

struct AppError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
