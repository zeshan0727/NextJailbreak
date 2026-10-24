import Foundation
import Combine
import NetworkExtension
import Network

// Compilation analysis (no build log was supplied): NWConnection and NWEndpoint
// belong to Network, not NetworkExtension. Importing Network is the minimal fix.
// The other visible compilation issue, String-based alert identity, is corrected
// locally in ServerListView without changing the persisted error/model types.

struct VPNServer: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let country: String
    let ipAddress: String
    var latency: Int?
}

enum VPNConnectionStatus: String {
    case disconnected, connecting, connected
}

final class VPNViewModel: ObservableObject {
    @Published var serversByCountry: [String: [VPNServer]] = [:]
    @Published var selectedServer: VPNServer?
    @Published var connectionStatus: VPNConnectionStatus = .disconnected
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isRefreshingLatency = false
    @Published var autoConnectOnLaunch = false

    private var cancellables = Set<AnyCancellable>()
    private let vpnManager = NEVPNManager.shared()
    private let serversURL = URL(string: "https://raw.githubusercontent.com/FreeVPNServers/vpnservers/main/servers.json")!
    private let userDefaults = UserDefaults.standard
    private let lastServerKey = "lastConnectedServer"
    private let lastStatusKey = "lastConnectionStatus"
    private let autoConnectKey = "autoConnectOnLaunch"

    init() {
        loadAutoConnectSetting()
        loadPersistedConnection()
        fetchServers()
    }

    func loadAutoConnectSetting() {
        autoConnectOnLaunch = userDefaults.bool(forKey: autoConnectKey)
    }

    func saveAutoConnectSetting() {
        userDefaults.set(autoConnectOnLaunch, forKey: autoConnectKey)
    }

    func fetchServers() {
        isLoading = true
        errorMessage = nil
        URLSession.shared.dataTaskPublisher(for: serversURL)
            .tryMap { data, _ in
                try JSONDecoder().decode([VPNServer].self, from: data)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self = self else { return }
                self.isLoading = false
                if case .failure = completion {
                    self.errorMessage = "Failed to fetch VPN servers. Please try again."
                }
            } receiveValue: { [weak self] servers in
                self?.groupServersByCountry(servers)
                self?.pingAllServers(servers)
            }
            .store(in: &cancellables)
    }

    private func groupServersByCountry(_ servers: [VPNServer]) {
        serversByCountry = Dictionary(grouping: servers, by: \.country)
    }

    func pingAllServers(_ servers: [VPNServer]) {
        isRefreshingLatency = true
        let group = DispatchGroup()
        var updatedServers = servers
        for i in updatedServers.indices {
            group.enter()
            ping(server: updatedServers[i]) { latency in
                DispatchQueue.main.async {
                    updatedServers[i].latency = latency
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            // Preserve countries outside a country-specific refresh.
            var merged = self.serversByCountry
            for (country, values) in Dictionary(grouping: updatedServers, by: \.country) {
                merged[country] = values
            }
            self.serversByCountry = merged
            self.isRefreshingLatency = false
        }
    }

    private func ping(server: VPNServer, completion: @escaping (Int?) -> Void) {
        let queue = DispatchQueue(label: "com.example.freelocalvpn.latency")
        let socket = NWConnection(host: NWEndpoint.Host(server.ipAddress), port: .https, using: .tcp)
        let start = DispatchTime.now()
        var finished = false
        // All callbacks use this serial queue. Complete only once: cancellation
        // and timeout must not produce extra DispatchGroup.leave() calls.
        func finish(_ latency: Int?) {
            guard !finished else { return }
            finished = true
            socket.stateUpdateHandler = nil
            socket.cancel()
            completion(latency)
        }
        socket.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                finish(Int(elapsed / 1_000_000))
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }
        socket.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) {
            finish(nil)
        }
    }

    func connect(to server: VPNServer) {
        guard connectionStatus != .connecting else { return }
        errorMessage = nil
        connectionStatus = .connecting
        selectedServer = server
        configureVPN(server: server) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    self.connectionStatus = .connected
                } else {
                    self.connectionStatus = .disconnected
                    self.errorMessage = error?.localizedDescription ?? "Failed to connect VPN."
                    self.selectedServer = nil
                }
                self.persistConnection()
            }
        }
    }

    func disconnect() {
        vpnManager.connection.stopVPNTunnel()
        connectionStatus = .disconnected
        selectedServer = nil
        persistConnection()
    }

    private func configureVPN(server: VPNServer, completion: @escaping (Bool, Error?) -> Void) {
        vpnManager.loadFromPreferences { error in
            if let error = error {
                completion(false, error)
                return
            }
            let protocolConfig = NEVPNProtocolIPSec()
            protocolConfig.serverAddress = server.ipAddress
            protocolConfig.authenticationMethod = .none
            protocolConfig.useExtendedAuthentication = false
            protocolConfig.disconnectOnSleep = false
            self.vpnManager.protocolConfiguration = protocolConfig
            self.vpnManager.localizedDescription = "FreeLocalVPN - \(server.name)"
            self.vpnManager.isEnabled = true
            self.vpnManager.saveToPreferences { error in
                if let error = error {
                    completion(false, error)
                    return
                }
                do {
                    try self.vpnManager.connection.startVPNTunnel()
                    completion(true, nil)
                } catch {
                    completion(false, error)
                }
            }
        }
    }

    private func persistConnection() {
        if let server = selectedServer, connectionStatus == .connected {
            if let data = try? JSONEncoder().encode(server) {
                userDefaults.set(data, forKey: lastServerKey)
            }
            userDefaults.set(connectionStatus.rawValue, forKey: lastStatusKey)
        } else {
            userDefaults.removeObject(forKey: lastServerKey)
            userDefaults.set(VPNConnectionStatus.disconnected.rawValue, forKey: lastStatusKey)
        }
    }

    private func loadPersistedConnection() {
        guard let data = userDefaults.data(forKey: lastServerKey),
              let server = try? JSONDecoder().decode(VPNServer.self, from: data),
              let statusRaw = userDefaults.string(forKey: lastStatusKey),
              let status = VPNConnectionStatus(rawValue: statusRaw) else {
            connectionStatus = .disconnected
            selectedServer = nil
            return
        }
        selectedServer = server
        connectionStatus = status
        if autoConnectOnLaunch && status == .connected {
            connect(to: server)
        }
    }
}
