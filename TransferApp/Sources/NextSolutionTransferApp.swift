import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Security

let transferFeedURLString = "https://nextjailbreak.com/transfer/index.json"
let transferGitHubRepo = "zeshan0727/NextJailbreak"

struct TransferFeed: Codable {
    let version: Int
    let updatedAt: String
    let files: [TransferItem]
}

struct TransferItem: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let fileName: String
    let type: String
    let platform: String
    let version: String
    let url: String
    let sha256: String?
    let sizeBytes: Int?
    let notes: String?
}

enum SecureTokenStore {
    private static let service = "com.nextsolution.transfer"
    private static let account = "github-upload-token"

    static func save(_ token: String) {
        delete()
        guard !token.isEmpty, let data = token.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return ""
        }
        return token
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class TransferStore: ObservableObject {
    @Published private(set) var items: [TransferItem] = []
    @Published private(set) var updatedAt = ""
    @Published private(set) var isRefreshing = false
    @Published private(set) var downloadingIDs: Set<String> = []
    @Published private(set) var deletingRootIDs: Set<String> = []
    @Published private(set) var downloaded: [String: URL] = [:]
    @Published var errorMessage: String?

    private struct GitHubContent: Decodable {
        let sha: String
        let content: String?
    }

    var downloadsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            guard var components = URLComponents(string: transferFeedURLString) else {
                throw URLError(.badURL)
            }
            components.queryItems = [
                URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
            ]
            guard let url = components.url else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 20
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("NS-Transfers/1.1.7", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let feed = try JSONDecoder().decode(TransferFeed.self, from: data)

            if feed.files != items || feed.updatedAt != updatedAt {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    items = feed.files
                    updatedAt = feed.updatedAt
                }
            }

            try? FileManager.default.createDirectory(
                at: downloadsDirectory,
                withIntermediateDirectories: true
            )

            var rebuilt: [String: URL] = [:]
            for item in feed.files {
                let local = downloadsDirectory.appendingPathComponent(item.fileName)
                if FileManager.default.fileExists(atPath: local.path) {
                    rebuilt[item.id] = local
                }
            }

            if rebuilt != downloaded {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    downloaded = rebuilt
                }
            }

            errorMessage = nil
        } catch {
            errorMessage = "Could not load NS Transfer feed: \(error.localizedDescription)"
        }
    }

    func download(_ item: TransferItem) async {
        guard !downloadingIDs.contains(item.id) else { return }
        downloadingIDs.insert(item.id)
        defer { downloadingIDs.remove(item.id) }

        do {
            guard let remote = URL(string: item.url) else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: remote)
            request.timeoutInterval = 300
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("NS-Transfers/1.1.7", forHTTPHeaderField: "User-Agent")

            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            try FileManager.default.createDirectory(
                at: downloadsDirectory,
                withIntermediateDirectories: true
            )

            let local = downloadsDirectory.appendingPathComponent(item.fileName)
            try? FileManager.default.removeItem(at: local)

            do {
                try FileManager.default.moveItem(at: temporaryURL, to: local)
            } catch {
                try FileManager.default.copyItem(at: temporaryURL, to: local)
            }

            downloaded[item.id] = local
            errorMessage = nil
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    func removeDeviceCopy(_ item: TransferItem) {
        if let url = downloaded[item.id] {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                errorMessage = "Could not delete the device copy: \(error.localizedDescription)"
                return
            }
        }

        downloaded.removeValue(forKey: item.id)
        errorMessage = nil
    }

    func deleteFromRoot(_ item: TransferItem) async {
        guard !deletingRootIDs.contains(item.id) else { return }

        let token = SecureTokenStore.load().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "GitHub token is not configured. Add a token with Contents: Read and write in Settings."
            return
        }

        deletingRootIDs.insert(item.id)
        defer { deletingRootIDs.remove(item.id) }

        do {
            let rootPath = try rootRepositoryPath(for: item)

            let rootContent = try await fetchGitHubContent(path: rootPath, token: token)
            let indexContent = try await fetchGitHubContent(path: "transfer/index.json", token: token)

            guard let encodedFeed = indexContent.content,
                  let feedData = Data(
                    base64Encoded: encodedFeed,
                    options: .ignoreUnknownCharacters
                  ) else {
                throw rootError("Could not read the root transfer index from GitHub.")
            }

            let currentFeed = try JSONDecoder().decode(TransferFeed.self, from: feedData)
            guard currentFeed.files.contains(where: { $0.id == item.id }) else {
                throw rootError("This item is no longer in the NS Transfer index. Refresh and try again.")
            }

            try await deleteGitHubFile(path: rootPath, sha: rootContent.sha, token: token)

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let revisedFeed = TransferFeed(
                version: currentFeed.version,
                updatedAt: timestamp,
                files: currentFeed.files.filter { $0.id != item.id }
            )
            try await updateRootFeed(revisedFeed, sha: indexContent.sha, token: token)

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                items.removeAll { $0.id == item.id }
                updatedAt = timestamp
            }
            errorMessage = nil
        } catch {
            errorMessage = "Root delete failed: \(error.localizedDescription)"
        }
    }

    private func rootRepositoryPath(for item: TransferItem) throws -> String {
        guard let url = URL(string: item.url),
              let host = url.host?.lowercased(),
              ["nextjailbreak.com", "www.nextjailbreak.com", "nextsolution.cc", "www.nextsolution.cc"].contains(host) else {
            throw rootError("For safety, root delete only supports files hosted by the NS Transfer website.")
        }

        let decodedPath = url.path.removingPercentEncoding ?? url.path
        guard decodedPath.hasPrefix("/transfer/files/") else {
            throw rootError("For safety, this item is outside transfer/files.")
        }

        return String(decodedPath.dropFirst())
    }

    private func fetchGitHubContent(path: String, token: String) async throws -> GitHubContent {
        var components = URLComponents(string: githubContentsURL(path: path))
        components?.queryItems = [URLQueryItem(name: "ref", value: "main")]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = githubRequest(url: url, token: token, method: "GET")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateGitHubResponse(data: data, response: response)
        return try JSONDecoder().decode(GitHubContent.self, from: data)
    }

    private func deleteGitHubFile(path: String, sha: String, token: String) async throws {
        guard let url = URL(string: githubContentsURL(path: path)) else {
            throw URLError(.badURL)
        }

        let body: [String: Any] = [
            "message": "Delete \(path) from NS Transfers",
            "sha": sha,
            "branch": "main"
        ]

        var request = githubRequest(url: url, token: token, method: "DELETE")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateGitHubResponse(data: data, response: response)
    }

    private func updateRootFeed(_ feed: TransferFeed, sha: String, token: String) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        var feedData = try encoder.encode(feed)
        feedData.append(0x0A)

        guard let url = URL(string: githubContentsURL(path: "transfer/index.json")) else {
            throw URLError(.badURL)
        }

        let body: [String: Any] = [
            "message": "Remove root transfer item from NS Transfers",
            "content": feedData.base64EncodedString(),
            "sha": sha,
            "branch": "main"
        ]

        var request = githubRequest(url: url, token: token, method: "PUT")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateGitHubResponse(data: data, response: response)
    }

    private func githubContentsURL(path: String) -> String {
        let encoded = path
            .split(separator: "/")
            .map { component -> String in
                let value = String(component)
                return value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
            }
            .joined(separator: "/")

        return "https://api.github.com/repos/\(transferGitHubRepo)/contents/\(encoded)"
    }

    private func githubRequest(url: URL, token: String, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("NS-Transfers", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validateGitHubResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = json?["message"] as? String
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw rootError("GitHub HTTP \(http.statusCode): \(message)")
        }
    }

    private func rootError(_ message: String) -> NSError {
        NSError(
            domain: "NS-Transfers.RootDelete",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

@main
struct NextSolutionTransferApp: App {
    @StateObject private var store = TransferStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            FilesView()
                .tabItem {
                    Label("Files", systemImage: "tray.and.arrow.down.fill")
                }

            EnhancedUploadView()
                .tabItem {
                    Label("Upload", systemImage: "arrow.up.doc.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(Color(red: 0.43, green: 0.57, blue: 1.0))
    }
}

struct FilesView: View {
    @EnvironmentObject private var store: TransferStore
    @State private var searchText = ""
    @State private var showSearch = false

    private var filteredItems: [TransferItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return store.items
        }

        return store.items.filter { item in
            [
                item.name,
                item.fileName,
                item.type,
                item.platform,
                item.version,
                item.notes ?? ""
            ].contains { value in
                value.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TransferGlassBackground()

                VStack(spacing: 0) {
                    transferHeader

                    if showSearch {
                        searchBar
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                    }

                    if store.items.isEmpty {
                        emptyState
                    } else {
                        fileList
                    }
                }
            }
            .navigationBarHidden(true)
            .task {
                if store.items.isEmpty {
                    await store.refresh()
                }
            }
            .alert(
                "NS Transfers",
                isPresented: Binding(
                    get: { store.errorMessage != nil },
                    set: { if !$0 { store.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    store.errorMessage = nil
                }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private var transferHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.19),
                                .white.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(.white.opacity(0.21), lineWidth: 0.8)
                    )

                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text("NS Transfers")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(store.items.isEmpty ? "Private transfer library" : "\(store.items.count) files available")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 6)

            headerButton(
                systemName: showSearch ? "xmark" : "magnifyingglass",
                accessibilityLabel: showSearch ? "Close search" : "Search files"
            ) {
                showSearch.toggle()
                if !showSearch {
                    searchText = ""
                }
            }

            headerButton(
                systemName: "arrow.clockwise",
                accessibilityLabel: "Refresh files",
                spinning: store.isRefreshing
            ) {
                Task {
                    await store.refresh()
                }
            }
            .disabled(store.isRefreshing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func headerButton(
        systemName: String,
        accessibilityLabel: String,
        spinning: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.15),
                                .white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if spinning {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.82)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .frame(width: 40, height: 40)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.48))

            TextField("Search files, versions, platforms…", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundStyle(.white)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .transferGlassPanel(cornerRadius: 16)
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 82, height: 82)

                if store.isRefreshing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "tray")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }

            Text("No Files Yet")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text("Refresh to check the live NS Transfer feed.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.56))

            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Text("Refresh")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 42)
                    .background(
                        Capsule()
                            .fill(TransferTheme.actionGradient)
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var fileList: some View {
        List {
            if !store.updatedAt.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.icloud.fill")
                        .foregroundStyle(Color.cyan.opacity(0.86))
                    Text("Updated \(store.updatedAt)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.46))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .transferGlassPanel(cornerRadius: 13)
                .listRowInsets(
                    EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.54))

                    Text("No Matching Files")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Try another file name, version, type, or platform.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.48))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredItems) { item in
                    TransferRow(item: item)
                        .listRowInsets(
                            EdgeInsets(top: 5, leading: 16, bottom: 7, trailing: 16)
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .refreshable {
            await store.refresh()
        }
    }
}

struct TransferRow: View {
    @EnvironmentObject private var store: TransferStore
    @State private var confirmRootDelete = false
    let item: TransferItem

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 13) {
                fileIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text("v\(item.version)")
                        Text("•")
                        Text(item.platform)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
                }

                Spacer(minLength: 6)

                statusPill
            }

            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.50))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 9) {
                actionArea

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    if let size = item.sizeBytes {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.43))
                    }

                    if let hash = item.sha256, !hash.isEmpty {
                        Text(String(hash.prefix(10)) + "…")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.27))
                    }
                }
            }
        }
        .padding(15)
        .transferGlassPanel(cornerRadius: 22)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                confirmRootDelete = true
            } label: {
                Label("Delete Root", systemImage: "trash.slash")
            }
            .disabled(store.deletingRootIDs.contains(item.id))
        }
        .confirmationDialog(
            "Delete from root server?",
            isPresented: $confirmRootDelete,
            titleVisibility: .visible
        ) {
            Button("Delete from Root", role: .destructive) {
                Task {
                    await store.deleteFromRoot(item)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the root/server file and its NS Transfer feed entry. A copy already downloaded to this device is not deleted.")
        }
    }

    private var fileIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.16),
                            .white.opacity(0.065)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: iconName)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white.opacity(0.91))
        }
        .frame(width: 54, height: 54)
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private var statusPill: some View {
        if store.deletingRootIDs.contains(item.id) {
            TransferStatusPill(text: "Deleting", systemName: "trash", tint: .orange)
        } else if store.downloadingIDs.contains(item.id) {
            HStack(spacing: 6) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.72)
                Text("Loading")
                    .font(.caption2.bold())
            }
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(Capsule().fill(.white.opacity(0.09)))
        } else if store.downloaded[item.id] != nil {
            TransferStatusPill(text: "Saved", systemName: "checkmark", tint: .green)
        } else {
            TransferStatusPill(text: item.type.uppercased(), systemName: nil, tint: .blue)
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if store.deletingRootIDs.contains(item.id) {
            EmptyView()
        } else if store.downloadingIDs.contains(item.id) {
            Text("Downloading…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.50))
        } else if let local = store.downloaded[item.id] {
            ShareLink(item: local) {
                TransferActionLabel(title: "Open / Share", systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                store.removeDeviceCopy(item)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.14))
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.red.opacity(0.93))
                }
                .frame(width: 38, height: 38)
                .overlay(
                    Circle()
                        .stroke(Color.red.opacity(0.20), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete from Device")
        } else {
            Button {
                Task {
                    await store.download(item)
                }
            } label: {
                TransferActionLabel(title: "Download", systemName: "arrow.down.circle.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private var iconName: String {
        switch item.type.lowercased() {
        case "deb":
            return "shippingbox.fill"
        case "tipa", "ipa":
            return "apps.iphone"
        case "zip":
            return "archivebox.fill"
        case "pdf":
            return "doc.richtext.fill"
        default:
            return "doc.fill"
        }
    }
}

struct TransferActionLabel: View {
    let title: String
    let systemName: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(
            Capsule()
                .fill(TransferTheme.actionGradient)
        )
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        )
    }
}

struct TransferStatusPill: View {
    let text: String
    let systemName: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .bold))
            }

            Text(text)
                .font(.caption2.bold())
        }
        .foregroundStyle(tint.opacity(0.96))
        .padding(.horizontal, 9)
        .frame(height: 29)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 0.8)
        )
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.item],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(
            onPick: @escaping (URL) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            onCancel()
        }
    }
}

struct SettingsView: View {
    @State private var token = SecureTokenStore.load()
    @State private var savedMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                TransferGlassBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        settingsHeader

                        settingsCard(
                            title: "Live Feed",
                            systemName: "network"
                        ) {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text("Server")
                                        .foregroundStyle(.white.opacity(0.62))
                                    Spacer()
                                    Text("nextjailbreak.com")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                }

                                Text(transferFeedURLString)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.white.opacity(0.42))
                                    .textSelection(.enabled)
                            }
                        }

                        settingsCard(
                            title: "GitHub Token",
                            systemName: "key.fill"
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                SecureField("Fine-grained token", text: $token)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 13)
                                    .frame(height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .fill(.white.opacity(0.07))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .stroke(.white.opacity(0.12), lineWidth: 0.8)
                                    )

                                Text("Use a fine-grained GitHub token restricted to zeshan0727/NextJailbreak with Repository permissions → Contents: Read and write. It stays in iOS Keychain on this device.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.48))

                                HStack(spacing: 9) {
                                    Button {
                                        SecureTokenStore.save(
                                            token.trimmingCharacters(in: .whitespacesAndNewlines)
                                        )
                                        token = SecureTokenStore.load()
                                        savedMessage = token.isEmpty
                                            ? "Token cleared"
                                            : "Token saved in Keychain"
                                    } label: {
                                        TransferActionLabel(
                                            title: "Save Token",
                                            systemName: "checkmark.shield.fill"
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if !SecureTokenStore.load().isEmpty {
                                        Button(role: .destructive) {
                                            SecureTokenStore.delete()
                                            token = ""
                                            savedMessage = "Token cleared"
                                        } label: {
                                            Text("Clear")
                                                .font(.caption.bold())
                                                .foregroundStyle(Color.red.opacity(0.94))
                                                .padding(.horizontal, 13)
                                                .frame(height: 38)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.red.opacity(0.12))
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Color.red.opacity(0.18), lineWidth: 0.8)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                if !savedMessage.isEmpty {
                                    Text(savedMessage)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.green.opacity(0.88))
                                }
                            }
                        }

                        settingsCard(
                            title: "Workflow",
                            systemName: "arrow.triangle.2.circlepath"
                        ) {
                            Text("Downloads appear from the live NS Transfer feed after Refresh. Uploads use the native Files or Photos picker and commit the selected item to transfer/uploads/ in the NextJailbreak repository. Swipe a file card from right to left to delete its root/server copy.")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.52))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text("NS Transfers 1.1.7")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.28))
                            .padding(.top, 4)
                            .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
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

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.20), lineWidth: 0.8)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("NS Transfers configuration")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.60))
            }

            Spacer()
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func settingsCard<Content: View>(
        title: String,
        systemName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemName)
                .font(.headline)
                .foregroundStyle(.white)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .transferGlassPanel(cornerRadius: 22)
    }
}

enum TransferTheme {
    static let actionGradient = LinearGradient(
        colors: [
            Color(red: 0.31, green: 0.60, blue: 1.0),
            Color(red: 0.62, green: 0.33, blue: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct TransferGlassBackground: View {
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

extension View {
    func transferGlassPanel(cornerRadius: CGFloat) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.115),
                                Color.white.opacity(0.052)
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
                                Color.white.opacity(0.23),
                                Color.white.opacity(0.075)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
    }
}
