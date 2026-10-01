import SwiftUI
import UIKit

struct NextAppItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let build: String
    let platform: String
    let minimumOS: String
    let bundleId: String
    let icon: String
    let manifest: String
    let available: Bool
    let status: String?
}

struct NextAppCatalog: Codable {
    let apps: [NextAppItem]
    let catalog: String?
    let updated: String?
}

@MainActor
final class AppCatalogStore: ObservableObject {
    @Published var apps: [NextAppItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    private let catalogURL = URL(string: "https://nextjailbreak.com/install/apps.json")!

    func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }

        do {
            var components = URLComponents(url: catalogURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970)))]

            var request = URLRequest(url: components.url!)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 20
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("NextApp/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let catalog = try JSONDecoder().decode(NextAppCatalog.self, from: data)
            apps = catalog.apps
            lastUpdated = Date()

            if apps.isEmpty {
                errorMessage = "No apps are published yet."
            }
        } catch {
            if apps.isEmpty {
                errorMessage = "Unable to load the app catalog."
            }
        }
    }

    func startLiveRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await load(showSpinner: false)
        }
    }
}

enum AppInstaller {
    static let baseURL = URL(string: "https://nextjailbreak.com")!

    static func iconURL(for app: NextAppItem) -> URL? {
        if let direct = URL(string: app.icon), direct.scheme != nil {
            return direct
        }
        return URL(string: app.icon, relativeTo: baseURL)?.absoluteURL
    }

    static func install(_ app: NextAppItem) {
        guard app.available else { return }
        guard let manifestURL = URL(string: app.manifest, relativeTo: baseURL)?.absoluteURL else { return }

        var components = URLComponents()
        components.scheme = "itms-services"
        components.path = ""
        components.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: manifestURL.absoluteString)
        ]

        guard let installURL = components.url else { return }
        UIApplication.shared.open(installURL)
    }
}

@main
struct NextApp: App {
    var body: some Scene {
        WindowGroup {
            AppsHomeView()
                .preferredColorScheme(.dark)
        }
    }
}

struct AppsHomeView: View {
    @StateObject private var store = AppCatalogStore()
    @Environment(\.scenePhase) private var scenePhase

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
                    } else if store.isLoading && store.apps.isEmpty {
                        loadingCard
                    }

                    ForEach(store.apps) { app in
                        AppCard(app: app)
                    }

                    if !store.apps.isEmpty {
                        VStack(spacing: 5) {
                            Text("Live from nextjailbreak.com/install")
                                .font(.caption2.weight(.semibold))
                            Text("New apps appear automatically")
                                .font(.caption2)
                        }
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
            await store.load()
        }
        .task {
            await store.startLiveRefresh()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await store.load(showSpinner: false) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    )

                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .shadow(color: .black.opacity(0.24), radius: 18, y: 9)

            VStack(alignment: .leading, spacing: 3) {
                Text("Next App")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(store.apps.isEmpty ? "Your private app library" : "\(store.apps.count) apps available")
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
            Text("Loading apps…")
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

struct AppCard: View {
    let app: NextAppItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                appIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("Version \(app.version) · Build \(app.build)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)

                    Text("\(app.platform) · \(app.minimumOS)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                installButton
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(app.available ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)

                Text(app.available ? "Ready to install" : (app.status ?? "Not available"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(app.available ? .green.opacity(0.9) : .orange.opacity(0.9))
            }

            Text(app.bundleId)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.30))
                .lineLimit(1)
        }
        .padding(16)
        .glassPanel(cornerRadius: 24)
    }

    private var installButton: some View {
        Button {
            AppInstaller.install(app)
        } label: {
            Text(app.available ? "Install" : "Unavailable")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(app.available ? 1 : 0.6))
                .padding(.horizontal, app.available ? 18 : 12)
                .frame(height: 39)
                .background(
                    Capsule()
                        .fill(
                            app.available
                            ? LinearGradient(
                                colors: [
                                    Color(red: 0.33, green: 0.62, blue: 1.0),
                                    Color(red: 0.63, green: 0.34, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [.white.opacity(0.13), .white.opacity(0.07)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(app.available ? 0.34 : 0.14), lineWidth: 0.8)
                )
                .shadow(color: app.available ? Color.purple.opacity(0.28) : .clear, radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!app.available)
    }

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(.white.opacity(0.10))

            if let url = AppInstaller.iconURL(for: app) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
    }

    private var placeholderIcon: some View {
        Image(systemName: "app.fill")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white.opacity(0.84))
    }
}

struct GlassBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.025, blue: 0.07),
                        Color(red: 0.055, green: 0.035, blue: 0.13),
                        Color(red: 0.02, green: 0.06, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.blue.opacity(0.32))
                    .frame(width: proxy.size.width * 0.95)
                    .blur(radius: 82)
                    .offset(x: -proxy.size.width * 0.38, y: -proxy.size.height * 0.31)

                Circle()
                    .fill(Color.purple.opacity(0.30))
                    .frame(width: proxy.size.width * 0.86)
                    .blur(radius: 92)
                    .offset(x: proxy.size.width * 0.38, y: proxy.size.height * 0.08)

                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: proxy.size.width * 0.78)
                    .blur(radius: 96)
                    .offset(x: proxy.size.width * 0.25, y: proxy.size.height * 0.57)

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.18)
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
                                    .white.opacity(0.11),
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
                                .white.opacity(0.30),
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
