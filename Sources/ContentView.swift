import SwiftUI
import Combine
import NetworkExtension

struct VPNServer: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let country: String
    let ipAddress: String
    var latency: Int?
}

enum VPNConnectionStatus: String {
    case disconnected
    case connecting
    case connected
}

final class VPNViewModel: ObservableObject {
    @Published var serversByCountry: [String: [VPNServer]] = [:]
    @Published var selectedServer: VPNServer? = nil
    @Published var connectionStatus: VPNConnectionStatus = .disconnected
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isRefreshingLatency: Bool = false
    @Published var autoConnectOnLaunch: Bool = false
    
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
            .tryMap { data, response -> [VPNServer] in
                let decoder = JSONDecoder()
                return try decoder.decode([VPNServer].self, from: data)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self = self else { return }
                self.isLoading = false
                switch completion {
                case .failure:
                    self.errorMessage = "Failed to fetch VPN servers. Please try again."
                case .finished:
                    break
                }
            } receiveValue: { [weak self] servers in
                guard let self = self else { return }
                self.groupServersByCountry(servers)
                self.pingAllServers(servers)
            }
            .store(in: &cancellables)
    }
    
    private func groupServersByCountry(_ servers: [VPNServer]) {
        var grouped: [String: [VPNServer]] = [:]
        for server in servers {
            grouped[server.country, default: []].append(server)
        }
        serversByCountry = grouped
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
            self.groupServersByCountry(updatedServers)
            self.isRefreshingLatency = false
        }
    }
    
    private func ping(server: VPNServer, completion: @escaping (Int?) -> Void) {
        // Simple TCP connect to port 80 or 443 to estimate latency
        // Since ICMP ping is not available in iOS SDK
        let host = server.ipAddress
        let port: UInt16 = 443
        let start = DispatchTime.now()
        let socket = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        socket.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let end = DispatchTime.now()
                let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
                let ms = Int(Double(nanoTime) / 1_000_000)
                socket.cancel()
                completion(ms)
            case .failed(_), .cancelled:
                socket.cancel()
                completion(nil)
            default:
                break
            }
        }
        socket.start(queue: .global())
        // Timeout after 3 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            socket.cancel()
            completion(nil)
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
                    self.persistConnection()
                } else {
                    self.connectionStatus = .disconnected
                    self.errorMessage = error?.localizedDescription ?? "Failed to connect VPN."
                    self.selectedServer = nil
                    self.persistConnection()
                }
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

struct ContentView: View {
    @StateObject private var viewModel = VPNViewModel()
    @State private var selectedCountry: String? = nil
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading servers...")
                        .accessibilityLabel("Loading VPN servers")
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Error: \(error)")
                        Button("Retry") {
                            viewModel.fetchServers()
                        }
                        .accessibilityLabel("Retry fetching VPN servers")
                    }
                    .padding()
                } else {
                    List {
                        ForEach(viewModel.serversByCountry.keys.sorted(), id: \String.self) { country in
                            NavigationLink(value: country) {
                                HStack {
                                    Text(country)
                                        .font(.body)
                                        .accessibilityLabel("Country: \(country)")
                                    Spacer()
                                    if let count = viewModel.serversByCountry[country]?.count {
                                        Text("\(count) servers")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .accessibilityLabel("\(count) servers available")
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationTitle("FreeLocalVPN")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("Settings")
                        }
                    }
                    .navigationDestination(for: String.self) { country in
                        if let servers = viewModel.serversByCountry[country] {
                            ServerListView(country: country, servers: servers)
                                .environmentObject(viewModel)
                        } else {
                            Text("No servers available")
                        }
                    }
                    .sheet(isPresented: $showingSettings) {
                        SettingsView()
                            .environmentObject(viewModel)
                    }
                }
            }
        }
        .environment(
            \.
            sizeCategory,
            .large
        )
    }
}

struct ServerListView: View {
    let country: String
    @State var servers: [VPNServer]
    @EnvironmentObject var viewModel: VPNViewModel
    @State private var isRefreshing = false
    
    var body: some View {
        List {
            ForEach(servers) { server in
                ServerRowView(server: server,
                              isConnected: viewModel.selectedServer == server && viewModel.connectionStatus == .connected,
                              isConnecting: viewModel.selectedServer == server && viewModel.connectionStatus == .connecting)
                .contentShape(Rectangle())
                .onTapGesture {
                    if viewModel.selectedServer == server && viewModel.connectionStatus == .connected {
                        viewModel.disconnect()
                    } else {
                        viewModel.connect(to: server)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: server))
                .accessibilityAddTraits(.isButton)
            }
        }
        .navigationTitle(country)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    refreshLatency()
                } label: {
                    if viewModel.isRefreshingLatency {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityLabel("Refresh server latency")
                .disabled(viewModel.isRefreshingLatency)
            }
        }
        .onReceive(viewModel.$serversByCountry) { newDict in
            if let updated = newDict[country] {
                servers = updated
            }
        }
        .alert(item: $viewModel.errorMessage) { msg in
            Alert(title: Text("Error"), message: Text(msg), dismissButton: .default(Text("OK")))
        }
    }
    
    private func refreshLatency() {
        viewModel.isRefreshingLatency = true
        viewModel.pingAllServers(servers)
    }
    
    private func accessibilityLabel(for server: VPNServer) -> String {
        var status = "Disconnected"
        if viewModel.selectedServer == server {
            switch viewModel.connectionStatus {
            case .connected: status = "Connected"
            case .connecting: status = "Connecting"
            case .disconnected: status = "Disconnected"
            }
        }
        let latencyText = server.latency.map { "Latency \($0) milliseconds" } ?? "Latency unknown"
        return "Server \(server.name), \(latencyText), Status: \(status)"
    }
}

struct ServerRowView: View {
    let server: VPNServer
    let isConnected: Bool
    let isConnecting: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(server.name)
                    .font(.body)
                    .foregroundColor(.primary)
                if let latency = server.latency {
                    Text("Latency: \(latency) ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Latency: unknown")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if isConnecting {
                ProgressView()
                    .accessibilityLabel("Connecting")
            } else if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .accessibilityLabel("Connected")
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
                    .accessibilityLabel("Disconnected")
            }
        }
        .padding(.vertical, 6)
    }
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("App Settings")) {
                    Toggle(isOn: $viewModel.autoConnectOnLaunch) {
                        Text("Auto-connect on launch")
                    }
                    .accessibilityLabel("Toggle auto-connect on app launch")
                    .onChange(of: viewModel.autoConnectOnLaunch) { _ in
                        viewModel.saveAutoConnectSetting()
                    }
                }
                Section(header: Text("VPN Permissions")) {
                    Text("This app uses Apple's NetworkExtension framework to manage VPN connections. Please ensure VPN permissions are granted in Settings.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("VPN permissions information")
                }
                Section(header: Text("App Info")) {
                    Text("FreeLocalVPN v1.0")
                        .accessibilityLabel("App version 1.0")
                    Text("© 2024 FreeLocalVPN")
                        .accessibilityLabel("Copyright 2024 FreeLocalVPN")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Close settings")
                }
            }
        }
    }
}
