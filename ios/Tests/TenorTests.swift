import XCTest

final class TenorTests: XCTestCase {
    private let sample = """
    {"results":[
      {"id":"1","content_description":"cat wave","media_formats":{
        "tinygif":{"url":"https://media.tenor.com/a/tiny.gif","dims":[220,124],"size":10},
        "gif":{"url":"https://media.tenor.com/a/full.gif","dims":[498,280],"size":900}}},
      {"id":"2","content_description":"no tiny","media_formats":{
        "gif":{"url":"https://media.tenor.com/b/full.gif","dims":[498,280],"size":900}}},
      {"id":"3","media_formats":{
        "tinygif":{"url":"https://media.tenor.com/c/tiny.gif","dims":[220,220],"size":10},
        "gif":{"url":"https://media.tenor.com/c/full.gif","dims":[400,400],"size":900}}}
    ],"next":"x"}
    """

    func testParsesWhatCanBeShownAndShared() throws {
        let gifs = try Tenor.parse(Data(sample.utf8))
        XCTAssertEqual(gifs.map(\.id), ["1", "3"])
        XCTAssertEqual(gifs[0].description, "cat wave")
        XCTAssertEqual(gifs[0].preview.absoluteString, "https://media.tenor.com/a/tiny.gif")
        XCTAssertEqual(gifs[0].full.absoluteString, "https://media.tenor.com/a/full.gif")
        XCTAssertEqual(gifs[0].previewSize, CGSize(width: 220, height: 124))
        XCTAssertEqual(gifs[1].description, "")
    }

    func testEmptyAndBrokenResponses() throws {
        XCTAssertEqual(try Tenor.parse(Data(#"{"results":[]}"#.utf8)), [])
        XCTAssertThrowsError(try Tenor.parse(Data("not json".utf8)))
    }

    func testSearchURLCarriesTheQueryAndTrendingNeedsNone() throws {
        let search = Tenor.url(query: "  salom dunyo ", key: "K")
        XCTAssertEqual(search.host, "tenor.googleapis.com")
        XCTAssertEqual(search.path, "/v2/search")
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: search, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value) })
        XCTAssertEqual(items["q"], "salom dunyo")
        XCTAssertEqual(items["key"], "K")
        XCTAssertEqual(items["media_filter"], "tinygif,gif")
        XCTAssertEqual(items["contentfilter"], "medium")
        let featured = Tenor.url(query: "   ", key: "K")
        XCTAssertEqual(featured.path, "/v2/featured")
        XCTAssertFalse(featured.absoluteString.contains("q="))
    }

    func testMissingKeyHasAnUzbekMessage() {
        XCTAssertTrue(TenorError.missingKey.localizedDescription.contains("Tenor"))
    }
}

final class BarModeTests: XCTestCase {
    func testTheGifBarIsTheTallest() {
        XCTAssertGreaterThan(KeyboardMetrics.barHeight(for: .gif), KeyboardMetrics.barHeight(for: .expanded))
        XCTAssertGreaterThan(KeyboardMetrics.barHeight(for: .expanded), KeyboardMetrics.barHeight(for: .compact))
        XCTAssertEqual(KeyboardMetrics.totalHeight(barExpanded: true), KeyboardMetrics.totalHeight(bar: .expanded))
    }
}
