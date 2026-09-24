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
}

enum Gemini {
    enum Part {
        case text(String)
        case jpeg(Data)

        var json: [String: Any] {
            switch self {
            case .text(let text): ["text": text]
            case .jpeg(let data): ["inlineData": ["mimeType": "image/jpeg", "data": data.base64EncodedString()]]
            }
        }
    }

    /// Lite answers a rewrite in ~1.5s with the same quality; the bigger model is only a fallback
    /// for when lite is overloaded (429/503 happen on the free tier).
    static let models = ["gemini-3.5-flash-lite", "gemini-3.5-flash"]

    static func generate<T: Decodable>(
        _ type: T.Type, system: String, parts: [Part], schema: [String: Any]
    ) async throws -> T {
        guard !Secrets.geminiAPIKey.isEmpty else { throw GeminiError.missingKey }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": parts.map(\.json)]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schema,
                "thinkingConfig": ["thinkingLevel": "minimal"],
            ],
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)

        var lastError: Error = GeminiError.empty
        for model in models {
            do {
                let text = try await call(model: model, payload: payload)
                return try JSONDecoder().decode(T.self, from: Data(text.utf8))
            } catch GeminiError.http(let code, let message) where [429, 500, 503].contains(code) {
                lastError = GeminiError.http(code, message)
            }
        }
        throw lastError
    }

    private static func call(model: String, payload: Data) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = payload

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            throw GeminiError.http(status, message)
        }
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.compactMap({ $0["text"] as? String }).first
        else { throw GeminiError.empty }
        return text
    }
}
