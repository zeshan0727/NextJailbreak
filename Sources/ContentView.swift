import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = VPNViewModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("FreeLocalVPN")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showingSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .navigationDestination(for: String.self) { country in
                    ServerListView(country: country)
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView().environmentObject(viewModel)
                }
        }
        .environmentObject(viewModel)
    }

    @ViewBuilder private var content: some View {
        if viewModel.isLoading {
            ProgressView("Loading servers...")
                .accessibilityLabel("Loading VPN servers")
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 16) {
                Text(error)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Error: \(error)")
                Button("Retry") { viewModel.fetchServers() }
                    .accessibilityLabel("Retry fetching VPN servers")
            }
            .padding()
        } else {
            CountryListView()
        }
    }
}

private struct CountryListView: View {
    @EnvironmentObject private var viewModel: VPNViewModel

    var body: some View {
        List {
            ForEach(viewModel.serversByCountry.keys.sorted(), id: \.self) { country in
                NavigationLink(value: country) {
                    HStack {
                        Text(country)
                            .font(.body)
                            .accessibilityLabel("Country: \(country)")
                        Spacer()
                        let count = viewModel.serversByCountry[country]?.count ?? 0
                        Text("\(count) servers")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("\(count) servers available")
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct ServerListView: View {
    let country: String
    @EnvironmentObject var viewModel: VPNViewModel

    private var servers: [VPNServer] {
        viewModel.serversByCountry[country] ?? []
    }

    // alert(item:) requires Identifiable; String does not conform. A Boolean
    // presentation binding is the smallest safe correction and retains String?
    // error storage. Do not add a global retroactive String conformance.
    private var showingError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    var body: some View {
        serverList
            .navigationTitle(country)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.pingAllServers(servers)
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
            .alert("Error", isPresented: showingError) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
    }

    private var serverList: some View {
        List(servers) { server in
            Button {
                if viewModel.selectedServer?.id == server.id && viewModel.connectionStatus == .connected {
                    viewModel.disconnect()
                } else {
                    viewModel.connect(to: server)
                }
            } label: {
                ServerRowView(
                    server: server,
                    isConnected: viewModel.selectedServer?.id == server.id && viewModel.connectionStatus == .connected,
                    isConnecting: viewModel.selectedServer?.id == server.id && viewModel.connectionStatus == .connecting
                )
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: server))
        }
    }

    private func accessibilityLabel(for server: VPNServer) -> String {
        var status = "Disconnected"
        if viewModel.selectedServer?.id == server.id {
            switch viewModel.connectionStatus {
            case .connected: status = "Connected"
            case .connecting: status = "Connecting"
            case .disconnected: status = "Disconnected"
            }
        }
        let latency = server.latency.map { "Latency \($0) milliseconds" } ?? "Latency unknown"
        return "Server \(server.name), \(latency), Status: \(status)"
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
                Text(server.latency.map { "Latency: \($0) ms" } ?? "Latency: unknown")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isConnecting {
                ProgressView().accessibilityLabel("Connecting")
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
        .contentShape(Rectangle())
    }
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                            .accessibilityLabel("Close settings")
                    }
                }
        }
    }

    private var settingsForm: some View {
        Form {
            Section(header: Text("App Settings")) {
                Toggle("Auto-connect on launch", isOn: $viewModel.autoConnectOnLaunch)
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
                Text("FreeLocalVPN v1.0").accessibilityLabel("App version 1.0")
                Text("© 2024 FreeLocalVPN").accessibilityLabel("Copyright 2024 FreeLocalVPN")
            }
        }
    }
}
