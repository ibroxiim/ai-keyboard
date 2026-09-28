import Foundation

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

    /// Tried in order. On 2026-09-28 3.5-flash-lite took 14–27 s per call (a screenshot often past the timeout)
    /// and 3.5-flash answered only 503, while 3.6-flash read a screenshot in 3–4 s — so it leads now.
    static let models = ["gemini-3.6-flash", "gemini-3.5-flash-lite", "gemini-3.5-flash"]

    /// Per attempt. Three attempts fit the keyboard's 60 s analysis window.
    static let attemptTimeout: TimeInterval = 20

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
            } catch where GeminiError.triesNextModel(after: error) {
                lastError = error
            }
        }
        throw lastError
    }

    private static func call(model: String, payload: Data) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url, timeoutInterval: attemptTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = payload

        let (data, response) = try await Signposts.measureAsync("gemini") {
            try await URLSession.shared.data(for: request)
        }
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
