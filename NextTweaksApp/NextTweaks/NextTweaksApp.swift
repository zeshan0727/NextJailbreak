import SwiftUI
import UIKit

struct TweakPackage: Identifiable, Hashable {
    let packageID: String
    let name: String
    let version: String
    let description: String
    let iconURL: URL?
    let filename: String?
    let depictionURL: URL?
    let section: String

    var id: String { packageID }

    var debURL: URL? {
        guard let filename, !filename.isEmpty else { return nil }
        if let absolute = URL(string: filename), absolute.scheme != nil { return absolute }
        let clean = filename.hasPrefix("./") ? String(filename.dropFirst(2)) : filename
        return URL(string: "https://nextjailbreak.com/\(clean)")
    }
}

enum PackagesParser {
    static func parse(_ text: String) -> [TweakPackage] {
        text
            .components(separatedBy: "\n\n")
            .compactMap(parseBlock)
    }

    private static func parseBlock(_ block: String) -> TweakPackage? {
        var fields: [String: String] = [:]
        var lastKey: String?

        for rawLine in block.components(separatedBy: .newlines) {
            if rawLine.hasPrefix(" "), let key = lastKey {
                fields[key, default: ""] += " " + rawLine.trimmingCharacters(in: .whitespaces)
                continue
            }

            guard let colon = rawLine.firstIndex(of: ":") else { continue }
            let key = String(rawLine[..<colon])
            let value = String(rawLine[rawLine.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            fields[key] = value
            lastKey = key
        }

        guard
            let packageID = fields["Package"], !packageID.isEmpty,
            let name = fields["Name"], !name.isEmpty
        else { return nil }

        let section = fields["Section"] ?? ""
        guard section.caseInsensitiveCompare("Tweaks") == .orderedSame else { return nil }

        return TweakPackage(
            packageID: packageID,
            name: name,
            version: fields["Version"] ?? "",
            description: fields["Description"] ?? "Jailbreak tweak from Next Jailbreak.",
            iconURL: makeURL(fields["Icon"]) ?? URL(string: "https://nextjailbreak.com/CydiaIcon.png"),
            filename: fields["Filename"],
            depictionURL: makeURL(fields["Depiction"]),
            section: section
        )
    }

    private static func makeURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil { return url }
        let clean = value.hasPrefix("/") ? String(value.dropFirst()) : value
        return URL(string: "https://nextjailbreak.com/\(clean)")
    }
}

@MainActor
final class TweaksStore: ObservableObject {
    @Published var tweaks: [TweakPackage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let feedURL = URL(string: "https://nextjailbreak.com/Packages")!

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var request = URLRequest(url: feedURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            request.setValue("NextTweaks/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }

            let parsed = PackagesParser.parse(text)
            var bestByID: [String: TweakPackage] = [:]

            for tweak in parsed {
                if let existing = bestByID[tweak.packageID] {
                    if tweak.version.localizedStandardCompare(existing.version) == .orderedDescending {
                        bestByID[tweak.packageID] = tweak
                    } else if tweak.version == existing.version,
                              existing.iconURL?.absoluteString.contains("CydiaIcon.png") == true,
                              tweak.iconURL?.absoluteString.contains("CydiaIcon.png") == false {
                        bestByID[tweak.packageID] = tweak
                    }
                } else {
                    bestByID[tweak.packageID] = tweak
                }
            }

            tweaks = bestByID.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            if tweaks.isEmpty {
                errorMessage = "No tweaks were found in the live repository."
            }
        } catch {
            errorMessage = "Couldn’t load the live tweak feed. Pull down to retry."
        }
    }
}

enum PackageInstaller {
    static func install(_ tweak: TweakPackage) {
        let encodedID = tweak.packageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tweak.packageID

        let candidates = [
            "sileo://package/\(encodedID)",
            "zbra://packages/\(encodedID)",
            "cydia://package/\(encodedID)"
        ].compactMap(URL.init(string:))

        for url in candidates where UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }

        if let deb = tweak.debURL {
            UIApplication.shared.open(deb)
        } else {
            UIApplication.shared.open(URL(string: "https://nextjailbreak.com/")!)
        }
    }
}

@main
struct NextTweaksApp: App {
    var body: some Scene {
        WindowGroup {
            TweaksHomeView()
                .preferredColorScheme(.dark)
        }
    }
}

struct TweaksHomeView: View {
    @StateObject private var store = TweaksStore()

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    header
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    if let error = store.errorMessage {
                        statusCard(icon: "wifi.exclamationmark", text: error)
                    } else if store.isLoading && store.tweaks.isEmpty {
                        loadingCard
                    }

                    ForEach(store.tweaks) { tweak in
                        TweakCard(tweak: tweak)
                    }

                    if !store.tweaks.isEmpty {
                        Text("Live from nextjailbreak.com")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.38))
                            .padding(.top, 8)
                            .padding(.bottom, 28)
                    }
                }
                .padding(.horizontal, 16)
            }
            .refreshable {
                await store.load()
            }
        }
        .task {
            if store.tweaks.isEmpty {
                await store.load()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                    )
                Image(systemName: "sparkles")
                    .font(.system(size: 25, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .shadow(color: .black.opacity(0.22), radius: 18, y: 9)

            VStack(alignment: .leading, spacing: 3) {
                Text("Next Tweaks")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(store.tweaks.isEmpty ? "Live jailbreak collection" : "\(store.tweaks.count) live tweaks")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            if store.isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.9)
            }
        }
        .padding(.vertical, 12)
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Loading live tweaks…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
            Spacer()
        }
        .padding(16)
        .glassPanel(cornerRadius: 20)
    }

    private func statusCard(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.9))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
            Spacer()
        }
        .padding(16)
        .glassPanel(cornerRadius: 20)
    }
}

struct TweakCard: View {
    let tweak: TweakPackage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                icon

                VStack(alignment: .leading, spacing: 4) {
                    Text(tweak.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        if !tweak.version.isEmpty {
                            Text("v\(tweak.version)")
                        }
                        Text("•")
                        Text("Next Jailbreak")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button {
                    PackageInstaller.install(tweak)
                } label: {
                    Text("Install")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.38, green: 0.56, blue: 1.0),
                                            Color(red: 0.64, green: 0.36, blue: 1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.34), lineWidth: 0.8)
                        )
                        .shadow(color: Color.purple.opacity(0.28), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
            }

            Text(tweak.description)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(tweak.packageID)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.32))
                .lineLimit(1)
        }
        .padding(16)
        .glassPanel(cornerRadius: 24)
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.10))

            if let url = tweak.iconURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(7)
                    default:
                        Image(systemName: "puzzlepiece.extension.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                }
            } else {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
            }
        }
        .frame(width: 54, height: 54)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.8)
        )
    }
}

struct GlassBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.025, green: 0.03, blue: 0.07),
                        Color(red: 0.06, green: 0.04, blue: 0.13),
                        Color(red: 0.025, green: 0.055, blue: 0.11)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.blue.opacity(0.32))
                    .frame(width: proxy.size.width * 0.9)
                    .blur(radius: 80)
                    .offset(x: -proxy.size.width * 0.38, y: -proxy.size.height * 0.31)

                Circle()
                    .fill(Color.purple.opacity(0.30))
                    .frame(width: proxy.size.width * 0.82)
                    .blur(radius: 90)
                    .offset(x: proxy.size.width * 0.36, y: proxy.size.height * 0.08)

                Circle()
                    .fill(Color.cyan.opacity(0.16))
                    .frame(width: proxy.size.width * 0.75)
                    .blur(radius: 95)
                    .offset(x: proxy.size.width * 0.25, y: proxy.size.height * 0.55)

                Rectangle()
                    .fill(.ultraThinMaterial.opacity(0.18))
            }
            .ignoresSafeArea()
        }
    }
}

private extension View {
    func glassPanel(cornerRadius: CGFloat) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.10),
                                    .white.opacity(0.025),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.28),
                                .white.opacity(0.08),
                                .white.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
    }
}
