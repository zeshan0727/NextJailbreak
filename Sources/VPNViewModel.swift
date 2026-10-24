import Foundation
import Combine
import Network
import NetworkExtension

struct VPNServer: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let country: String
    let ipAddress: String
    var latency: Int?

    init(id: UUID = UUID(), name: String, country: String, ipAddress: String, latency: Int? = nil) {
        self.id = id
        self.name = name
        self.country = country
        self.ipAddress = ipAddress
        self.latency = latency
    }

    enum CodingKeys: String, CodingKey { case id, name, country, ipAddress, latency }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        country = try values.decode(String.self, forKey: .country)
        ipAddress = try values.decode(String.self, forKey: .ipAddress)
        latency = try values.decodeIfPresent(Int.self, forKey: .latency)
    }
}

enum VPNConnectionStatus: String {
    case disconnected, connecting, connected, disconnecting
    var title: String { rawValue.capitalized }
}

final class VPNViewModel: ObservableObject {
    @Published private(set) var servers: [VPNServer] = []
    @Published private(set) var selectedServer: VPNServer?
    @Published private(set) var connectionStatus: VPNConnectionStatus = .disconnected
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshingLatency = false
    @Published var errorMessage: String?
    @Published var autoConnectOnLaunch: Bool {
        didSet { defaults.set(autoConnectOnLaunch, forKey: "autoConnectOnLaunch") }
    }

    private let defaults = UserDefaults.standard
    private let manager = NEVPNManager.shared()
    private var observer: NSObjectProtocol?
    private var loadingConfiguration = false
    private var starting = false
    private var configurationLoaded = false
    private let cacheKey = "savedVPNServers"

    var serversByCountry: [String: [VPNServer]] { Dictionary(grouping: servers, by: \.country) }
    var canDisconnect: Bool { connectionStatus != .disconnected }

    init() {
        autoConnectOnLaunch = UserDefaults.standard.bool(forKey: "autoConnectOnLaunch")
        if let data = defaults.data(forKey: cacheKey), let cached = try? JSONDecoder().decode([VPNServer].self, from: data) {
            servers = cached
        }
        if let data = defaults.data(forKey: "lastConnectedServer"), let last = try? JSONDecoder().decode(VPNServer.self, from: data) {
            selectedServer = last
            if !servers.contains(where: { $0.ipAddress == last.ipAddress }) { servers.append(last) }
        }
        // A saved status is not evidence that a VPN tunnel is still running.
        defaults.set(VPNConnectionStatus.disconnected.rawValue, forKey: "lastConnectionStatus")
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: manager.connection, queue: .main) { [weak self] _ in
            self?.updateStatus()
        }
        reloadConfiguration(autoConnect: true)
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    func reloadConfiguration(autoConnect: Bool = false) {
        guard !loadingConfiguration else { return }
        loadingConfiguration = true
        isLoading = true
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loadingConfiguration = false
                self.isLoading = false
                if let error = error {
                    self.configurationLoaded = false
                    self.errorMessage = "Could not read the system VPN configuration. \(error.localizedDescription) VPN access also requires the app's Personal VPN entitlement."
                    return
                }
                self.configurationLoaded = true
                self.includeConfiguredServer()
                self.updateStatus()
                if autoConnect, self.autoConnectOnLaunch, self.connectionStatus == .disconnected, let server = self.selectedServer {
                    self.connect(to: server)
                }
            }
        }
    }

    private func includeConfiguredServer() {
        guard let address = manager.protocolConfiguration?.serverAddress, !address.isEmpty else { return }
        if !servers.contains(where: { $0.ipAddress.caseInsensitiveCompare(address) == .orderedSame }) {
            servers.append(VPNServer(name: manager.localizedDescription ?? "Configured VPN", country: "Configured VPN", ipAddress: address))
            saveServers()
        }
    }

    func connect(to server: VPNServer) {
        guard !starting, connectionStatus == .disconnected else {
            errorMessage = "Disconnect the current VPN before selecting another server."
            return
        }
        guard configurationLoaded else {
            errorMessage = "VPN configuration is unavailable. Reload it in Settings and check the app's VPN permissions."
            return
        }
        guard let configuration = manager.protocolConfiguration,
              configuration.serverAddress?.caseInsensitiveCompare(server.ipAddress) == .orderedSame else {
            errorMessage = "This server has no usable VPN configuration in this app. An address alone is not enough: your provider must supply a supported Personal VPN configuration and authentication. Importing a server list does not install a VPN profile."
            return
        }
        guard manager.isEnabled else {
            errorMessage = "The app's VPN configuration is disabled. Enable it in iOS Settings, then reload the configuration here."
            return
        }
        errorMessage = nil
        selectedServer = server
        starting = true
        do {
            try manager.connection.startVPNTunnel()
            // startVPNTunnel only requests a connection. The system reports success later.
            connectionStatus = .connecting
            updateStatus(keepStarting: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.starting = false
                self?.updateStatus()
            }
        } catch {
            starting = false
            connectionStatus = .disconnected
            errorMessage = "Unable to start VPN: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        starting = false
        manager.connection.stopVPNTunnel()
        updateStatus()
    }

    private func updateStatus(keepStarting: Bool = false) {
        let oldStatus = connectionStatus
        switch manager.connection.status {
        case .connected: connectionStatus = .connected; starting = false
        case .connecting, .reasserting: connectionStatus = .connecting
        case .disconnecting: connectionStatus = .disconnecting
        case .invalid, .disconnected:
            if keepStarting { return }
            connectionStatus = .disconnected
        @unknown default: connectionStatus = .disconnected
        }
        if connectionStatus != .disconnected,
           let address = manager.protocolConfiguration?.serverAddress,
           let match = servers.first(where: { $0.ipAddress.caseInsensitiveCompare(address) == .orderedSame }) {
            selectedServer = match
        }
        if connectionStatus == .connected, let server = selectedServer, let data = try? JSONEncoder().encode(server) {
            defaults.set(data, forKey: "lastConnectedServer")
        }
        defaults.set(connectionStatus.rawValue, forKey: "lastConnectionStatus")
        if oldStatus == .connecting && connectionStatus == .disconnected {
            errorMessage = "The system did not establish a VPN connection. Check your provider's configuration, authentication and network connection."
        }
    }

    static func validAddress(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:")
        return !value.isEmpty && value.count <= 253 && value.unicodeScalars.allSatisfy { allowed.contains($0) } && value.rangeOfCharacter(from: .alphanumerics) != nil
    }

    func addServer(name: String, country: String, address: String) {
        let server = VPNServer(name: name.trimmingCharacters(in: .whitespacesAndNewlines), country: country.trimmingCharacters(in: .whitespacesAndNewlines), ipAddress: address.trimmingCharacters(in: .whitespacesAndNewlines))
        merge([server])
    }

    private func merge(_ incoming: [VPNServer]) {
        for server in incoming {
            if !servers.contains(where: { $0.ipAddress.caseInsensitiveCompare(server.ipAddress) == .orderedSame }) {
                servers.append(server)
            }
        }
        saveServers()
    }

    private func saveServers() {
        if let data = try? JSONEncoder().encode(servers) { defaults.set(data, forKey: cacheKey) }
    }

    func importServers(from url: URL) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 2_000_000 else { throw ImportError.invalid("The server list must be smaller than 2 MB.") }
        let data = try Data(contentsOf: url)
        guard data.count <= 2_000_000 else { throw ImportError.invalid("The server list is too large.") }
        let decoded = try JSONDecoder().decode([VPNServer].self, from: data)
        guard !decoded.isEmpty, decoded.count <= 2000 else { throw ImportError.invalid("Import between 1 and 2,000 servers.") }
        guard decoded.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Self.validAddress($0.ipAddress) }) else {
            throw ImportError.invalid("Each server needs a name, country and valid hostname or IP address, without a URL scheme or port.")
        }
        let before = servers.count
        // Do not trust imported latency measurements or duplicate IDs.
        merge(decoded.map { VPNServer(name: $0.name, country: $0.country, ipAddress: $0.ipAddress) })
        return servers.count - before
    }

    func pingAllServers(_ targets: [VPNServer]) {
        guard !isRefreshingLatency, !targets.isEmpty else { return }
        isRefreshingLatency = true
        var pending = targets
        func next() {
            guard !pending.isEmpty else { self.isRefreshingLatency = false; return }
            let batch = Array(pending.prefix(12))
            pending.removeFirst(batch.count)
            let group = DispatchGroup()
            for server in batch {
                group.enter()
                probe(server) { [weak self] latency in
                    DispatchQueue.main.async {
                        if let self = self, let index = self.servers.firstIndex(where: { $0.id == server.id }) {
                            self.servers[index].latency = latency
                        }
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) { next() }
        }
        next()
    }

    private func probe(_ server: VPNServer, completion: @escaping (Int?) -> Void) {
        let queue = DispatchQueue(label: "com.example.freelocalvpn.probe")
        let socket = NWConnection(host: NWEndpoint.Host(server.ipAddress), port: .https, using: .tcp)
        let start = DispatchTime.now().uptimeNanoseconds
        var finished = false
        func finish(_ latency: Int?) {
            guard !finished else { return }
            finished = true
            socket.stateUpdateHandler = nil
            socket.cancel()
            completion(latency)
        }
        socket.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000))
            case .failed, .cancelled: finish(nil)
            default: break
            }
        }
        socket.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) { finish(nil) }
    }
}

private enum ImportError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
