import Foundation

/// The Gemini key the user types into the app: pure rules only. Storage lives in `KeyStore`.
enum APIKey {
    /// What gets stored: no spaces or line breaks, which pasted keys often carry. nil when nothing is left.
    static func normalized(_ text: String) -> String? {
        let key = text.filter { !$0.isWhitespace }
        return key.isEmpty ? nil : key
    }

    /// The user's key wins. The key compiled in from Secrets.swift is only a developer fallback.
    static func resolve(user: String?, build: String) -> String {
        user.flatMap(normalized) ?? build
    }

    /// Shows which key is saved without showing the key: four dots and the last four characters.
    static func masked(_ key: String) -> String {
        key.count <= 4 ? String(repeating: "•", count: key.count) : "••••" + String(key.suffix(4))
    }

    /// What one test request with a new key says about it.
    enum CheckOutcome: Equatable {
        /// Google accepted the key.
        case valid
        /// Google refused the key. It is not saved.
        case rejected(String)
        /// Nothing certain (network, quota, server). The key is saved, and the user is told it was not verified.
        case unverified(String)

        var shouldSave: Bool {
            if case .rejected = self { return false }
            return true
        }
    }

    static func outcome(of error: Error?) -> CheckOutcome {
        guard let error else { return .valid }
        switch error {
        case GeminiError.http(let code, _) where [400, 401, 403].contains(code):
            return .rejected("Kalit noto'g'ri yoki faol emas")
        case GeminiError.missingKey:
            return .rejected("Kalit bo'sh")
        default:
            return .unverified(error.localizedDescription)
        }
    }
}
