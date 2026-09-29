import Foundation

enum GeminiError: LocalizedError {
    case missingKey
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingKey: "Gemini API kaliti yo'q (Shared/Secrets.swift)"
        case .http(let code, let message): "Gemini \(code): \(message)"
        case .empty: "Gemini bo'sh javob qaytardi"
        }
    }

    /// Overload, quota and server errors say nothing about the next model; a bad request or a missing key does.
    var triesNextModel: Bool {
        switch self {
        case .http(let code, _): code == 429 || (500...599).contains(code)
        case .empty: true
        case .missingKey: false
        }
    }

    /// A timeout or a dropped connection is how an overloaded model often shows up, and a reply cut off mid-JSON
    /// is worth another model too. No connection at all, or a cancelled request, would fail the same way again.
    static func triesNextModel(after error: Error) -> Bool {
        if let error = error as? GeminiError { return error.triesNextModel }
        if error is DecodingError { return true }
        if let error = error as? URLError { return [.timedOut, .networkConnectionLost].contains(error.code) }
        return false
    }
}
