import XCTest
@testable import NovaBrowser

final class URLResolverTests: XCTestCase {
    func testBareDomainUsesHTTPS() throws {
        XCTAssertEqual(try URLResolver.resolve(" example.com/path?q=1 ", engine: .google).absoluteString, "https://example.com/path?q=1")
    }
    func testSearchPreservesQueryExactly() throws {
        let query = "a+b & café / iOS 16"
        let url = try URLResolver.resolve(query, engine: .duckDuckGo)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, query)
        XCTAssertEqual(url.host, "duckduckgo.com")
    }
    func testAllSearchEnginesUseHTTPSAndQueryItem() throws {
        for engine in SearchEngine.allCases {
            let url = try URLResolver.resolve("search words", engine: engine)
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "q")
        }
    }
    func testExplicitHTTPUpgradeCanBeDisabled() throws {
        XCTAssertEqual(try URLResolver.resolve("http://example.com", engine: .google).scheme, "https")
        XCTAssertEqual(try URLResolver.resolve("http://example.com", engine: .google, httpsFirst: false).scheme, "http")
    }
    func testLocalDeviceAndPort() throws {
        let url = try URLResolver.resolve("192.168.1.2:8080/admin", engine: .google, httpsFirst: false)
        XCTAssertEqual(url.host, "192.168.1.2")
        XCTAssertEqual(url.port, 8080)
        XCTAssertEqual(url.path, "/admin")
        XCTAssertEqual(try URLResolver.resolve("localhost:3000", engine: .google, httpsFirst: false).port, 3000)
    }
    func testIPv6Address() throws {
        let url = try URLResolver.resolve("[::1]:8080", engine: .google, httpsFirst: false)
        XCTAssertEqual(url.port, 8080)
    }
    func testExecutableAndUnsupportedSchemesAreRejected() {
        for value in ["javascript:alert(1)", "data:text/html,hello", "file:///etc/passwd", "tel:123", "ftp://example.com"] {
            XCTAssertThrowsError(try URLResolver.resolve(value, engine: .google)) { XCTAssertEqual($0 as? AddressError, .unsupportedScheme) }
        }
    }
    func testCredentialURLIsRejected() {
        XCTAssertThrowsError(try URLResolver.resolve("https://admin:secret@example.com", engine: .google)) { XCTAssertEqual($0 as? AddressError, .embeddedCredentials) }
    }
    func testBlankInputAndMissingHostAreRejected() {
        XCTAssertThrowsError(try URLResolver.resolve(" \n ", engine: .google))
        XCTAssertThrowsError(try URLResolver.resolve("https:///", engine: .google))
    }
}
