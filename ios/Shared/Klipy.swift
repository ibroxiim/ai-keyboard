import Foundation

/// One GIF from KLIPY: a small animated preview for the strip and the full file to share.
struct Gif: Identifiable, Equatable {
    /// KLIPY's slug, e.g. "hello-hi-662".
    let id: String
    let title: String
    /// `file.sm.gif` — ~220 px, light enough to animate several at once in a keyboard extension.
    let preview: URL
    let previewSize: CGSize
    /// `file.md.gif` — what goes to the pasteboard (same size as hd, smaller file).
    let full: URL
}

/// KLIPY GIF API v1 — the Tenor replacement (Google's Tenor API ended on 2026-06-30). The key lives in
/// `Secrets.klipyAPIKey`; a test key allows 100 requests an hour, production is unlocked in the Partner Panel.
/// Integration rules: media is loaded straight from KLIPY's URLs (no re-hosting), results are shown in the order
/// given, and the KLIPY name is shown next to them.
enum Klipy {
    static let perPage = 20

    /// Empty query → `trending`, like the first screen of any GIF picker.
    static func url(query: String, key: String) -> URL {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "https://api.klipy.com/api/v1/\(key)/gifs/" + (trimmed.isEmpty ? "trending" : "search"))!
        var items = [
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "content_filter", value: "medium"),
            URLQueryItem(name: "format_filter", value: "gif"),
        ]
        if !trimmed.isEmpty { items.insert(URLQueryItem(name: "q", value: trimmed), at: 0) }
        components.queryItems = items
        return components.url!
    }

    /// The GIFs in a `search`/`trending` response, in KLIPY's order; items missing the needed sizes are skipped.
    static func parse(_ data: Data) throws -> [Gif] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.result else { throw KlipyError.http(0) }
        return response.data.data.compactMap { item in
            guard let small = item.file["sm"]?["gif"], let preview = URL(string: small.url),
                  let fullFormat = item.file["md"]?["gif"] ?? item.file["hd"]?["gif"], let full = URL(string: fullFormat.url),
                  small.width > 0, small.height > 0
            else { return nil }
            return Gif(
                id: item.slug, title: item.title ?? "", preview: preview,
                previewSize: CGSize(width: small.width, height: small.height), full: full)
        }
    }

    static func search(_ query: String, key: String) async throws -> [Gif] {
        guard !key.isEmpty else { throw KlipyError.missingKey }
        var request = URLRequest(url: url(query: query, key: key), timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw KlipyError.http(status) }
        return try parse(data)
    }

    static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, !data.isEmpty else { throw KlipyError.http(status) }
        return data
    }

    private struct Response: Decodable {
        struct Page: Decodable {
            let data: [Item]
        }
        struct Item: Decodable {
            struct Format: Decodable {
                let url: String
                let width: Int
                let height: Int
            }
            let slug: String
            let title: String?
            /// size ("hd", "md", "sm", "xs") → format ("gif", "webp", "mp4"…) → file.
            let file: [String: [String: Format]]
        }
        let result: Bool
        let data: Page
    }
}

enum KlipyError: LocalizedError, Equatable {
    case missingKey
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .missingKey: "GIF uchun KLIPY kaliti kiritilmagan (Secrets.swift)"
        case .http(let code): "GIF xizmati javob bermadi (\(code))"
        }
    }
}
