import XCTest

final class KlipyTests: XCTestCase {
    private func item(_ slug: String, title: String? = "Hello", sizes: [String] = ["hd", "md", "sm", "xs"]) -> String {
        let file = sizes.map { size in
            let dim = ["hd": 498, "md": 498, "sm": 220, "xs": 90][size]!
            return "\"\(size)\":{\"gif\":{\"url\":\"https://static.klipy.com/\(slug)/\(size).gif\",\"width\":\(dim),\"height\":\(dim / 2),\"size\":1},\"mp4\":{\"url\":\"https://static.klipy.com/\(slug)/\(size).mp4\",\"width\":\(dim),\"height\":\(dim),\"size\":1}}"
        }.joined(separator: ",")
        let titleJSON = title.map { "\"title\":\"\($0)\"," } ?? ""
        return "{\"id\":8041071659142944,\"slug\":\"\(slug)\",\(titleJSON)\"file\":{\(file)},\"tags\":[],\"type\":\"gif\"}"
    }

    private func response(_ items: [String], result: Bool = true) -> Data {
        Data("{\"result\":\(result),\"data\":{\"data\":[\(items.joined(separator: ","))],\"current_page\":1,\"per_page\":24,\"has_next\":true}}".utf8)
    }

    func testParsesPreviewAndFullFilesInKlipysOrder() throws {
        let gifs = try Klipy.parse(response([item("hello-hi-662"), item("bye-1", title: nil, sizes: ["hd", "sm"])]))
        XCTAssertEqual(gifs.map(\.id), ["hello-hi-662", "bye-1"])
        XCTAssertEqual(gifs[0].title, "Hello")
        XCTAssertEqual(gifs[0].preview.absoluteString, "https://static.klipy.com/hello-hi-662/sm.gif")
        XCTAssertEqual(gifs[0].previewSize, CGSize(width: 220, height: 110))
        XCTAssertEqual(gifs[0].full.absoluteString, "https://static.klipy.com/hello-hi-662/md.gif")
        // No md: hd stands in; no title: empty.
        XCTAssertEqual(gifs[1].full.absoluteString, "https://static.klipy.com/bye-1/hd.gif")
        XCTAssertEqual(gifs[1].title, "")
    }

    func testItemsWithoutASmallGifAreSkippedAndFailuresThrow() throws {
        XCTAssertEqual(try Klipy.parse(response([item("x", sizes: ["hd"])])), [])
        XCTAssertEqual(try Klipy.parse(response([])), [])
        XCTAssertThrowsError(try Klipy.parse(response([], result: false)))
        XCTAssertThrowsError(try Klipy.parse(Data("not json".utf8)))
    }

    func testTheKeyIsInThePathAndTrendingNeedsNoQuery() throws {
        let search = Klipy.url(query: "  salom dunyo ", key: "KEY123")
        XCTAssertEqual(search.host, "api.klipy.com")
        XCTAssertEqual(search.path, "/api/v1/KEY123/gifs/search")
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: search, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value) })
        XCTAssertEqual(items["q"], "salom dunyo")
        XCTAssertEqual(items["per_page"], "20")
        XCTAssertEqual(items["content_filter"], "medium")
        XCTAssertEqual(items["format_filter"], "gif")
        let trending = Klipy.url(query: "   ", key: "KEY123")
        XCTAssertEqual(trending.path, "/api/v1/KEY123/gifs/trending")
        XCTAssertFalse(trending.absoluteString.contains("q="))
    }

    func testMissingKeyHasAnUzbekMessage() {
        XCTAssertTrue(KlipyError.missingKey.localizedDescription.contains("KLIPY"))
    }
}

final class BarModeTests: XCTestCase {
    func testTheGifBarIsTheTallest() {
        XCTAssertGreaterThan(KeyboardMetrics.barHeight(for: .gif), KeyboardMetrics.barHeight(for: .expanded))
        XCTAssertGreaterThan(KeyboardMetrics.barHeight(for: .expanded), KeyboardMetrics.barHeight(for: .compact))
        XCTAssertEqual(KeyboardMetrics.totalHeight(barExpanded: true), KeyboardMetrics.totalHeight(bar: .expanded))
    }
}
