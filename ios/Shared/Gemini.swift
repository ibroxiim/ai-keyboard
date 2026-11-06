import Foundation

enum Gemini {
    typealias Part = GeminiPart

    static func generate<T: Decodable>(
        _ type: T.Type, system: String, parts: [Part], schema: [String: Any], quality: GeminiQuality = .fast
    ) async throws -> T {
        let key = KeyStore.effectiveKey
        guard !key.isEmpty else { throw GeminiError.missingKey }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": parts.map(\.json)]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schema,
                "thinkingConfig": ["thinkingLevel": quality.thinkingLevel],
            ],
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)

        return try await Hedge.first(
            quality.models, after: quality.hedgeDelay(media: parts.contains(where: \.isMedia)),
            isRetriable: GeminiError.triesNextModel(after:)
        ) { model in
            let text = try await call(model: model, key: key, payload: payload, timeout: quality.attemptTimeout)
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        }
    }

    /// One small request with a key the user is about to save. Listing models costs no quota, and Google answers
    /// an unknown key with 400.
    static func check(key: String) async -> APIKey.CheckOutcome {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
                return APIKey.outcome(of: GeminiError.http(status, message))
            }
            return .valid
        } catch {
            return APIKey.outcome(of: error)
        }
    }

    private static func call(model: String, key: String, payload: Data, timeout: TimeInterval) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
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
