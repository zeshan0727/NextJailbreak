import Foundation

enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case google, duckDuckGo, bing, brave
    var id: String { rawValue }
    var title: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .brave: return "Brave"
        }
    }
    var baseURL: String {
        switch self {
        case .google: return "https://www.google.com/search"
        case .duckDuckGo: return "https://duckduckgo.com/"
        case .bing: return "https://www.bing.com/search"
        case .brave: return "https://search.brave.com/search"
        }
    }
}

enum AddressError: LocalizedError, Equatable {
    case empty, unsupportedScheme, invalidURL, embeddedCredentials
    var errorDescription: String? {
        switch self {
        case .empty: return "Enter a website address or a search."
        case .unsupportedScheme: return "Only HTTP and HTTPS addresses can be opened from the address bar."
        case .invalidURL: return "This address is not a valid website URL."
        case .embeddedCredentials: return "URLs containing a username or password are not allowed. Open the site and sign in there."
        }
    }
}

enum URLResolver {
    static func resolve(_ input: String, engine: SearchEngine, httpsFirst: Bool = true) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AddressError.empty }
        let authority = String(text.split(separator: "/", maxSplits: 1).first ?? "")
        let isLocalWithPort = authority.range(of: #"^(localhost|[a-zA-Z0-9.-]+\.[a-zA-Z0-9-]+|\[[0-9a-fA-F:]+\]):[0-9]+$"#, options: .regularExpression) != nil
        let hasScheme = text.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*:"#, options: .regularExpression) != nil
        if hasScheme && !isLocalWithPort {
            guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                throw AddressError.unsupportedScheme
            }
            return try validated(components, upgrade: httpsFirst)
        }
        if !text.contains(where: { $0.isWhitespace }), isAddress(authority) {
            guard let components = URLComponents(string: "\(httpsFirst ? "https" : "http")://\(text)") else { throw AddressError.invalidURL }
            return try validated(components, upgrade: false)
        }
        var components = URLComponents(string: engine.baseURL)!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        guard let url = components.url else { throw AddressError.invalidURL }
        return url
    }

    private static func isAddress(_ authority: String) -> Bool {
        let host = authority.lowercased()
        return host == "localhost" || host.hasPrefix("localhost:") || host.contains(".") || host.hasPrefix("[")
    }

    private static func validated(_ input: URLComponents, upgrade: Bool) throws -> URL {
        var components = input
        guard components.user == nil, components.password == nil else { throw AddressError.embeddedCredentials }
        guard let host = components.host, !host.isEmpty, !host.contains(where: { $0.isWhitespace }) else { throw AddressError.invalidURL }
        if let port = components.port, !(1...65535).contains(port) { throw AddressError.invalidURL }
        if upgrade && components.scheme?.lowercased() == "http" { components.scheme = "https" }
        guard let url = components.url else { throw AddressError.invalidURL }
        return url
    }
}
