import Foundation

/// One GIF from Tenor: a small animated preview for the strip and the full file to share.
struct Gif: Identifiable, Equatable {
    let id: String
    let description: String
    /// `tinygif` — ~220 px wide, light enough to animate several at once in a keyboard extension.
    let preview: URL
    let previewSize: CGSize
    /// `gif` — what goes to the pasteboard.
    let full: URL
}

/// Tenor v2 (Google's GIF service, the one Gboard uses). The key lives in `Secrets.tenorAPIKey`.
enum Tenor {
    static let clientKey = "aikeyboard"
    static let limit = 20

    /// Empty query → trending (`featured`), like the first screen of any GIF picker.
    static func url(query: String, key: String) -> URL {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "https://tenor.googleapis.com/v2/" + (trimmed.isEmpty ? "featured" : "search"))!
        var items = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "client_key", value: clientKey),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "media_filter", value: "tinygif,gif"),
            URLQueryItem(name: "contentfilter", value: "medium"),
        ]
        if !trimmed.isEmpty { items.insert(URLQueryItem(name: "q", value: trimmed), at: 0) }
        components.queryItems = items
        return components.url!
    }

    /// The GIFs in a v2 `search`/`featured` response; results missing either format are skipped.
    static func parse(_ data: Data) throws -> [Gif] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.results.compactMap { result in
            guard let tiny = result.media_formats["tinygif"], let full = result.media_formats["gif"],
                  let preview = URL(string: tiny.url), let fullURL = URL(string: full.url),
                  tiny.dims.count == 2, tiny.dims[0] > 0, tiny.dims[1] > 0
            else { return nil }
            return Gif(
                id: result.id, description: result.content_description ?? "", preview: preview,
                previewSize: CGSize(width: tiny.dims[0], height: tiny.dims[1]), full: fullURL)
        }
    }

    static func search(_ query: String, key: String) async throws -> [Gif] {
        guard !key.isEmpty else { throw TenorError.missingKey }
        var request = URLRequest(url: url(query: query, key: key), timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw TenorError.http(status) }
        return try parse(data)
    }

    static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, !data.isEmpty else { throw TenorError.http(status) }
        return data
    }

    private struct Response: Decodable {
        struct Result: Decodable {
            struct Format: Decodable {
                let url: String
                let dims: [Int]
            }
            let id: String
            let content_description: String?
            let media_formats: [String: Format]
        }
        let results: [Result]
    }
}

enum TenorError: LocalizedError, Equatable {
    case missingKey
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .missingKey: "GIF uchun Tenor kaliti kiritilmagan (Secrets.swift)"
        case .http(let code): "GIF xizmati javob bermadi (\(code))"
        }
    }
}
