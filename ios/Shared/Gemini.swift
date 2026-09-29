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

    /// Raced by `Hedge`, in this order. Which one is up changes day to day: on 2026-09-28 3.5-flash-lite took
    /// 14–27 s and 3.6-flash answered in 2–4 s; on 2026-09-29 3.6-flash returned 503 and lite answered in 2–3 s.
    /// All of them take `thinkingLevel: minimal` (3.7/3.8-flash do not).
    static let models = ["gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.1-flash-lite", "gemini-3.5-flash"]

    /// Per attempt.
    static let attemptTimeout: TimeInterval = 20

    /// How long a model may stay quiet before the next one is started alongside it. A screenshot takes longer
    /// to read than a rewrite, so it gets more time before paying for a second request.
    static func hedgeDelay(for parts: [Part]) -> Duration {
        parts.contains { if case .jpeg = $0 { true } else { false } } ? .seconds(6) : .seconds(4)
    }

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

        return try await Hedge.first(
            models, after: hedgeDelay(for: parts), isRetriable: GeminiError.triesNextModel(after:)
        ) { model in
            let text = try await call(model: model, payload: payload)
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        }
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
