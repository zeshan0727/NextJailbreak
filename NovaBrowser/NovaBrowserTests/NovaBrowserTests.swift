import XCTest
@testable import NovaBrowser

final class NovaBrowserTests: XCTestCase {
    func testSmartURLParsing() {
        XCTAssertEqual(NavigationRouter.resolve("example.org/path", searchEngine: .duckDuckGo)?.absoluteString, "https://example.org/path")
        XCTAssertEqual(NavigationRouter.resolve("https://apple.com", searchEngine: .google)?.host, "apple.com")
        XCTAssertTrue(NavigationRouter.resolve("two search words", searchEngine: .bing)?.absoluteString.contains("two%20search%20words") == true)
    }

    func testSiteSettingsOverridePrecedence() {
        let global = GlobalSiteSettings(userAgentPreset: .system, desktopMode: false, javaScriptEnabled: true, popupMode: .block)
        let sites = [SiteSettings(host: "EXAMPLE.ORG", userAgentPreset: .windowsChrome,
                                  desktopMode: true, javaScriptEnabled: false, popupMode: .allow)]
        let resolved = SiteSettingsResolver.resolve(host: "example.org", global: global, sites: sites)
        XCTAssertEqual(resolved.userAgentPreset, .windowsChrome)
        XCTAssertTrue(resolved.desktopMode)
        XCTAssertFalse(resolved.javaScriptEnabled)
        XCTAssertEqual(resolved.popupMode, .allow)
        let fallback = SiteSettingsResolver.resolve(host: "other.org", global: global, sites: sites)
        XCTAssertEqual(fallback.popupMode, .block)
        XCTAssertTrue(fallback.javaScriptEnabled)
    }

    func testPopupPolicyMilestone1AllowsAll() {
        let settings = ResolvedSiteSettings(userAgentPreset: .system, desktopMode: false,
                                            javaScriptEnabled: true, popupMode: .block)
        let request = PopupRequest(sourceHost: "example.org", targetURL: URL(string: "https://other.org"), isUserInitiated: false)
        XCTAssertEqual(PopupPolicy.decide(request, settings: settings), .allow)
    }

    func testSnapshotRoundTrip() throws {
        let snapshot = BrowserSnapshot(bookmarks: [Bookmark(title: "Test", address: "https://example.org")])
        let data = try JSONEncoder().encode(snapshot)
        let read = try JSONDecoder().decode(BrowserSnapshot.self, from: data)
        XCTAssertEqual(read.bookmarks.first?.address, "https://example.org")
    }
}
