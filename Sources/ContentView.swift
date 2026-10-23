import SwiftUI
import Combine
import Network

struct TVDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let ipAddress: String
    let port: UInt16
}

enum ConnectionStatus: String {
    case connected, disconnected, error
}

enum CommandStatus: String {
    case idle, sending, error
}

final class DeviceDiscoveryViewModel: ObservableObject {
    @Published var discoveredDevices: [TVDevice] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private var browser: NWBrowser?
    private var queue = DispatchQueue(label: "DeviceDiscoveryQueue")

    func startDiscovery() {
        errorMessage = nil
        discoveredDevices.removeAll()
        isLoading = true

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let bonjourType = "_http._tcp"

        browser = NWBrowser(for: .bonjour(type: bonjourType, domain: nil), using: parameters)

        browser?.stateUpdateHandler = { [weak self] newState in
            DispatchQueue.main.async {
                switch newState {
                case .failed(let error):
                    self?.errorMessage = "Discovery failed: \(error.localizedDescription)"
                    self?.isLoading = false
                case .ready:
                    break
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            DispatchQueue.main.async {
                self?.discoveredDevices = results.compactMap { result in
                    guard case let NWEndpoint.service(name: name, type: _, domain: _, interface: _) = result.endpoint else {
                        return nil
                    }
                    // Extract IP and port from metadata
                    if let ipPort = result.metadata.first(where: { $0 is NWProtocolTCP.Metadata }) as? NWProtocolTCP.Metadata {
                        // We can't get IP from metadata directly, fallback to name only
                        return TVDevice(name: name, ipAddress: "", port: 0)
                    } else {
                        return TVDevice(name: name, ipAddress: "", port: 0)
                    }
                }
                self?.isLoading = false
                if self?.discoveredDevices.isEmpty == true {
                    self?.errorMessage = "No TVs found on the network."
                }
            }
        }

        browser?.start(queue: queue)
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isLoading = false
    }
}

final class RemoteControlViewModel: ObservableObject {
    @Published var connectedDevice: TVDevice
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var commandStatus: CommandStatus = .idle
    @Published var errorMessage: String? = nil

    private var connection: NWConnection?
    private var queue = DispatchQueue(label: "RemoteControlQueue")

    init(device: TVDevice) {
        self.connectedDevice = device
        connect()
    }

    func connect() {
        connectionStatus = .disconnected
        commandStatus = .idle
        errorMessage = nil

        guard !connectedDevice.ipAddress.isEmpty, connectedDevice.port != 0 else {
            connectionStatus = .error
            errorMessage = "Invalid device address or port."
            return
        }

        let host = NWEndpoint.Host(connectedDevice.ipAddress)
        let port = NWEndpoint.Port(rawValue: connectedDevice.port) ?? NWEndpoint.Port(80)

        connection = NWConnection(host: host, port: port, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.connectionStatus = .connected
                case .failed(let error):
                    self?.connectionStatus = .error
                    self?.errorMessage = "Connection failed: \(error.localizedDescription)"
                case .waiting(let error):
                    self?.connectionStatus = .error
                    self?.errorMessage = "Connection waiting: \(error.localizedDescription)"
                case .cancelled:
                    self?.connectionStatus = .disconnected
                default:
                    break
                }
            }
        }

        connection?.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connectionStatus = .disconnected
        commandStatus = .idle
        errorMessage = nil
    }

    func sendCommand(_ command: String) {
        guard connectionStatus == .connected else {
            errorMessage = "Not connected to device."
            commandStatus = .error
            return
        }

        commandStatus = .sending
        errorMessage = nil

        let commandData = command.data(using: .utf8) ?? Data()

        connection?.send(content: commandData, completion: .contentProcessed({ [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.commandStatus = .error
                    self?.errorMessage = "Failed to send command: \(error.localizedDescription)"
                } else {
                    self?.commandStatus = .idle
                }
            }
        }))
    }
}

struct ContentView: View {
    @StateObject private var discoveryVM = DeviceDiscoveryViewModel()
    @State private var selectedDevice: TVDevice? = nil

    var body: some View {
        NavigationStack {
            DeviceDiscoveryView(
                discoveredDevices: discoveryVM.discoveredDevices,
                isLoading: discoveryVM.isLoading,
                errorMessage: discoveryVM.errorMessage,
                onRefresh: {
                    discoveryVM.startDiscovery()
                },
                onSelectDevice: { device in
                    selectedDevice = device
                }
            )
            .navigationDestination(isPresented: Binding(
                get: { selectedDevice != nil },
                set: { if !$0 { selectedDevice = nil } }
            )) {
                if let device = selectedDevice {
                    RemoteControlView(device: device) {
                        selectedDevice = nil
                        discoveryVM.startDiscovery()
                    }
                }
            }
            .onAppear {
                discoveryVM.startDiscovery()
            }
            .onDisappear {
                discoveryVM.stopDiscovery()
            }
        }
    }
}

struct DeviceDiscoveryView: View {
    let discoveredDevices: [TVDevice]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void
    let onSelectDevice: (TVDevice) -> Void

    var body: some View {
        VStack {
            Text("Select Your TV")
                .font(.title)
                .bold()
                .padding(.top)

            if isLoading {
                ProgressView("Searching...")
                    .padding()
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        onRefresh()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if discoveredDevices.isEmpty {
                Text("No TVs found on the network.")
                    .foregroundColor(.secondary)
                    .padding()
                Button("Refresh") {
                    onRefresh()
                }
                .buttonStyle(.bordered)
            } else {
                List(discoveredDevices) { device in
                    Button(action: {
                        onSelectDevice(device)
                    }) {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.headline)
                                if !device.ipAddress.isEmpty {
                                    Text(device.ipAddress)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Connect to TV named \(device.name)"))
                }
                .listStyle(.plain)
                .refreshable {
                    onRefresh()
                }
            }

            Spacer()

            Button(action: {
                onRefresh()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom)
        }
        .padding(.horizontal)
    }
}

struct RemoteControlView: View {
    @StateObject private var vm: RemoteControlViewModel
    let onDisconnect: () -> Void

    init(device: TVDevice, onDisconnect: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: RemoteControlViewModel(device: device))
        self.onDisconnect = onDisconnect
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(vm.connectedDevice.name)
                    .font(.title2)
                    .bold()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Disconnect") {
                    vm.disconnect()
                    onDisconnect()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Disconnect from TV"))
            }
            .padding(.horizontal)

            connectionStatusView

            remoteButtons

            Spacer()
        }
        .padding()
        .onDisappear {
            vm.disconnect()
        }
        .alert(isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Alert(title: Text("Error"), message: Text(vm.errorMessage ?? ""), dismissButton: .default(Text("OK")))
        }
    }

    private var connectionStatusView: some View {
        HStack {
            Circle()
                .fill(colorForConnectionStatus(vm.connectionStatus))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text(vm.connectionStatus.rawValue.capitalized)
                .font(.subheadline)
                .foregroundColor(colorForConnectionStatus(vm.connectionStatus))
            Spacer()
            if vm.commandStatus == .sending {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .accessibilityLabel(Text("Sending command"))
            }
        }
        .padding(.horizontal)
    }

    private func colorForConnectionStatus(_ status: ConnectionStatus) -> Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var remoteButtons: some View {
        VStack(spacing: 20) {
            HStack(spacing: 40) {
                remoteButton(title: "Power", systemImage: "power", command: "power_toggle")
                remoteButton(title: "Mute", systemImage: "speaker.slash", command: "mute")
            }

            HStack(spacing: 40) {
                remoteButton(title: "Vol +", systemImage: "speaker.wave.3", command: "volume_up")
                remoteButton(title: "Vol -", systemImage: "speaker.wave.1", command: "volume_down")
            }

            HStack(spacing: 40) {
                remoteButton(title: "Ch +", systemImage: "chevron.up", command: "channel_up")
                remoteButton(title: "Ch -", systemImage: "chevron.down", command: "channel_down")
            }

            navigationPad

            HStack(spacing: 40) {
                remoteButton(title: "Back", systemImage: "arrow.backward", command: "back")
                remoteButton(title: "Home", systemImage: "house", command: "home")
            }
        }
    }

    private var navigationPad: some View {
        VStack(spacing: 8) {
            remoteButton(title: "Up", systemImage: "chevron.up", command: "nav_up")
            HStack(spacing: 40) {
                remoteButton(title: "Left", systemImage: "chevron.left", command: "nav_left")
                remoteButton(title: "OK", systemImage: "circle.fill", command: "select")
                remoteButton(title: "Right", systemImage: "chevron.right", command: "nav_right")
            }
            remoteButton(title: "Down", systemImage: "chevron.down", command: "nav_down")
        }
    }

    private func remoteButton(title: String, systemImage: String, command: String) -> some View {
        Button(action: {
            vm.sendCommand(command)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }) {
            VStack {
                Image(systemName: systemImage)
                    .font(.title)
                Text(title)
                    .font(.caption)
            }
            .frame(width: 60, height: 60)
            .background(Color(UIColor.secondarySystemFill))
            .cornerRadius(12)
        }
        .accessibilityLabel(Text(title))
        .disabled(vm.connectionStatus != .connected || vm.commandStatus == .sending)
    }
}
