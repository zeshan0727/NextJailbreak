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
    let downloadURL: String?
    let sha256: String?
    let sizeBytes: Int?
}

struct NextAppCatalog: Codable {
    let apps: [NextAppItem]
    let catalog: String?
    let updated: String?
}

@MainActor
final class AppCatalogStore: ObservableObject {
    @Published private(set) var apps: [NextAppItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let catalogURL = URL(string: "https://nextjailbreak.com/install/apps.json")!

    func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        defer {
            if showSpinner { isLoading = false }
        }

        do {
            var components = URLComponents(url: catalogURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970)))
            ]

            var request = URLRequest(url: components.url!)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 20
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("NextApp/1.0.2", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let catalog = try JSONDecoder().decode(NextAppCatalog.self, from: data)

            if catalog.apps != apps {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    apps = catalog.apps
                }
            }

            errorMessage = catalog.apps.isEmpty ? "No apps are published yet." : nil
        } catch {
            if apps.isEmpty {
                errorMessage = "Unable to load the app catalog."
            }
        }
    }

    func startLiveRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
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

    static func install(_ app: NextAppItem, completion: @escaping (Bool) -> Void) {
        guard app.available else {
            completion(false)
            return
        }

        guard let manifestURL = URL(string: app.manifest, relativeTo: baseURL)?.absoluteURL else {
            completion(false)
            return
        }

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        guard let encodedManifest = manifestURL.absoluteString
            .addingPercentEncoding(withAllowedCharacters: allowed),
              let installURL = URL(
                string: "itms-services://?action=download-manifest&url=\(encodedManifest)"
              ) else {
            completion(false)
            return
        }

        UIApplication.shared.open(
            installURL,
            options: [:],
            completionHandler: completion
        )
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
            FastGlassBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
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
                            .equatable()
                    }

                    if !store.apps.isEmpty {
                        VStack(spacing: 4) {
                            Text("Live from nextjailbreak.com/install")
                                .font(.caption2.weight(.semibold))
                            Text("New apps appear automatically")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.immediately)
            .transaction { transaction in
                transaction.animation = nil
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
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.18),
                                .white.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.20), lineWidth: 0.8)
                    )

                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)

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
                .foregroundStyle(.white.opacity(0.80))
            Spacer()
        }
        .padding(16)
        .fastGlassPanel(cornerRadius: 20)
    }

    private func statusCard(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.9))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.80))
            Spacer()
        }
        .padding(16)
        .fastGlassPanel(cornerRadius: 20)
    }
}

struct AppCard: View, Equatable {
    let app: NextAppItem

    @State private var alertMessage: String?
    @State private var showMore = false
    @State private var askDuplicateCount = false
    @State private var duplicateCountText = "1"
    @State private var isDuplicating = false
    @State private var duplicateStatus = ""
    @State private var duplicateResults: [DuplicateAppResult] = []

    static func == (lhs: AppCard, rhs: AppCard) -> Bool {
        lhs.app == rhs.app
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 13) {
                appIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("Version \(app.version) · Build \(app.build)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)

                    Text("\(app.platform) · \(app.minimumOS)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.44))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(spacing: 6) {
                    installButton
                    moreButton
                }
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(app.available ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)

                Text(app.available ? "Ready to install" : (app.status ?? "Not available"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(app.available ? .green.opacity(0.92) : .orange.opacity(0.92))
            }

            Text(app.bundleId)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.32))
                .lineLimit(1)

            if isDuplicating {
                duplicationProgress
            }

            if !duplicateResults.isEmpty {
                duplicateInstallList
            }
        }
        .padding(15)
        .fastGlassPanel(cornerRadius: 23)
        .alert(
            "Next App",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                alertMessage = nil
            }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var installButton: some View {
        Button {
            AppInstaller.install(app) { success in
                if !success {
                    DispatchQueue.main.async {
                        alertMessage = "iOS did not accept the OTA install request for this app."
                    }
                }
            }
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
                                    Color(red: 0.31, green: 0.60, blue: 1.0),
                                    Color(red: 0.62, green: 0.33, blue: 1.0)
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
                        .stroke(.white.opacity(app.available ? 0.30 : 0.14), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .disabled(!app.available || isDuplicating)
    }

    private var moreButton: some View {
        Button {
            showMore = true
        } label: {
            HStack(spacing: 5) {
                Text("More")
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(app.available ? 0.78 : 0.42))
            .padding(.horizontal, 14)
            .frame(height: 31)
            .background(
                Capsule()
                    .fill(.white.opacity(0.075))
            )
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.13), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .disabled(!app.available || isDuplicating)
        .confirmationDialog(
            "More",
            isPresented: $showMore,
            titleVisibility: .visible
        ) {
            Button("Duplicate App") {
                duplicateCountText = "1"
                askDuplicateCount = true
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Additional actions for \(app.name)")
        }
        .alert(
            "Duplicate \(app.name)",
            isPresented: $askDuplicateCount
        ) {
            TextField("Number of copies", text: $duplicateCountText)
                .keyboardType(.numberPad)

            Button("Cancel", role: .cancel) {}

            Button("Create") {
                startDuplication()
            }
        } message: {
            Text("Enter how many duplicate apps to create. Maximum 10.")
        }
    }

    private var duplicationProgress: some View {
        HStack(spacing: 11) {
            ProgressView()
                .tint(.white)

            VStack(alignment: .leading, spacing: 3) {
                Text("Duplicating app")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.90))

                Text(duplicateStatus.isEmpty ? "Preparing…" : duplicateStatus)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.8)
        )
    }

    private var duplicateInstallList: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Duplicate Apps", systemImage: "square.on.square.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.84))

                Spacer()

                Text("\(duplicateResults.count) ready")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.green.opacity(0.88))
            }

            ForEach(duplicateResults) { result in
                duplicateRow(result)
            }

            Text("Install uses TrollStore's URL scheme. If TrollStore does not open, use Share and choose TrollStore.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.8)
        )
    }

    private func duplicateRow(_ result: DuplicateAppResult) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.08))

                Image(systemName: "square.on.square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.84))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(result.bundleId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.33))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                DuplicateIPAInstallBridge.shared.install(
                    fileURL: result.fileURL
                ) { outcome in
                    if case .failure(let error) = outcome {
                        DispatchQueue.main.async {
                            alertMessage = error.localizedDescription
                        }
                    }
                }
            } label: {
                Text("Install")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.31, green: 0.60, blue: 1.0),
                                        Color(red: 0.62, green: 0.33, blue: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)

            ShareLink(item: result.fileURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.76))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.075))
                    )
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.11), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func startDuplication() {
        guard let count = Int(duplicateCountText),
              (1...10).contains(count) else {
            alertMessage = "Enter a number from 1 to 10."
            return
        }

        duplicateResults = []
        duplicateStatus = "Preparing…"
        isDuplicating = true

        Task {
            do {
                let results = try await DuplicateAppEngine.createCopies(
                    of: app,
                    count: count
                ) { status in
                    DispatchQueue.main.async {
                        duplicateStatus = status
                    }
                }

                await MainActor.run {
                    duplicateResults = results
                    duplicateStatus = "Ready to install"
                    isDuplicating = false
                }
            } catch {
                await MainActor.run {
                    isDuplicating = false
                    duplicateStatus = ""
                    alertMessage = "Duplicate failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.10))

            if let url = AppInstaller.iconURL(for: app) {
                AsyncImage(
                    url: url,
                    transaction: Transaction(animation: nil)
                ) { phase in
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
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        )
    }

    private var placeholderIcon: some View {
        Image(systemName: "app.fill")
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
    }
}

struct FastGlassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.025, blue: 0.075),
                    Color(red: 0.055, green: 0.035, blue: 0.13),
                    Color(red: 0.018, green: 0.07, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.blue.opacity(0.22),
                    .clear
                ],
                center: .topLeading,
                startRadius: 10,
                endRadius: 330
            )

            RadialGradient(
                colors: [
                    Color.purple.opacity(0.20),
                    .clear
                ],
                center: .trailing,
                startRadius: 20,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

private extension View {
    func fastGlassPanel(cornerRadius: CGFloat) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.115),
                                Color.white.opacity(0.055)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.24),
                                .white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
    }
}
