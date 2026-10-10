import Foundation

/// One piece of a Gemini request. A top-level type (not nested in `Gemini`) so it compiles, and is tested, without
/// the networking and key code.
enum GeminiPart {
    case text(String)
    case jpeg(Data)
    case audio(Data, mimeType: String)

    var json: [String: Any] {
        switch self {
        case .text(let text): ["text": text]
        case .jpeg(let data): ["inlineData": ["mimeType": "image/jpeg", "data": data.base64EncodedString()]]
        case .audio(let data, let mimeType): ["inlineData": ["mimeType": mimeType, "data": data.base64EncodedString()]]
        }
    }

    /// Images and audio take longer to read than text.
    var isMedia: Bool {
        if case .text = self { return false }
        return true
    }
}
