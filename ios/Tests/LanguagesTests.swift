import XCTest

final class LanguagesTests: XCTestCase {
    func testUntouchedListIsTheDefaults() {
        XCTAssertEqual(SharedState().languageList, Languages.defaults)
    }

    func testOwnListReplacesTheDefaults() {
        var state = SharedState()
        state.languages = ["Thai", "Korean"]
        XCTAssertEqual(state.languageList, ["Thai", "Korean"])
    }

    func testEmptyOwnListStaysEmpty() {
        var state = SharedState()
        state.languages = []
        XCTAssertEqual(state.languageList, [])
    }

    func testStateWrittenByAnOlderBuildStillLoads() throws {
        let state = try JSONDecoder().decode(SharedState.self, from: Data(#"{"targetLanguage":"Korean"}"#.utf8))
        XCTAssertNil(state.languages)
        XCTAssertEqual(state.languageList, Languages.defaults)
    }

    func testNormalizedTrimsAndCapitalises() {
        XCTAssertEqual(Languages.normalized("  swahili "), "Swahili")
        XCTAssertEqual(Languages.normalized("old   english"), "Old English")
    }

    func testNormalizedKeepsTheRestOfTheWordAsTyped() {
        XCTAssertEqual(Languages.normalized("swiss GERMAN"), "Swiss GERMAN")
    }

    func testNormalizedUsesTheCatalogSpelling() {
        XCTAssertEqual(Languages.normalized("KOREAN"), "Korean")
        XCTAssertEqual(Languages.normalized(" korean "), "Korean")
    }

    func testNormalizedRejectsNothingAndHugeInput() {
        XCTAssertNil(Languages.normalized(""))
        XCTAssertNil(Languages.normalized("  \n "))
        XCTAssertNil(Languages.normalized(String(repeating: "a", count: 31)))
    }

    func testAddingAppendsAtTheEnd() {
        XCTAssertEqual(Languages.adding("thai", to: ["English", "Korean"]), ["English", "Korean", "Thai"])
    }

    func testAddingKeepsALanguageOnlyOnce() {
        XCTAssertEqual(Languages.adding("korean", to: ["English", "Korean"]), ["English", "Korean"])
    }

    func testAddingBlankChangesNothing() {
        XCTAssertEqual(Languages.adding("   ", to: ["English"]), ["English"])
    }

    func testAddableLeavesOutWhatIsListedAndKeepsCatalogOrder() {
        let addable = Languages.addable(to: ["English", "korean"]).map(\.name)
        XCTAssertFalse(addable.contains("English"))
        XCTAssertFalse(addable.contains("Korean"))
        XCTAssertEqual(addable.first, "Russian")
    }

    func testFlags() {
        XCTAssertEqual(Languages.flag("Korean"), "🇰🇷")
        XCTAssertEqual(Languages.flag("korean"), "🇰🇷")
        XCTAssertEqual(Languages.flag("Klingon"), "🌐")
    }

    func testCatalogIsConsistent() {
        let names = Languages.catalog.map { $0.name.lowercased() }
        XCTAssertEqual(Set(names).count, names.count, "duplicate catalog entry")
        for language in Languages.defaults {
            XCTAssertTrue(names.contains(language.lowercased()), "\(language) is a default but not in the catalog")
        }
    }
}
