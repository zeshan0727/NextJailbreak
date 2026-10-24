import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = VPNViewModel()
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            CountryListView()
                .navigationTitle("FreeLocalVPN")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Settings")
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView().environmentObject(viewModel)
                }
        }
        .environmentObject(viewModel)
        .onChange(of: scenePhase) { phase in
            if phase == .active { viewModel.reloadConfiguration() }
        }
    }
}

private struct CountryListView: View {
    @EnvironmentObject private var model: VPNViewModel

    var body: some View {
        List {
            Section {
                VPNStatusView()
                if model.isLoading { ProgressView("Reading VPN configuration…") }
            }
            if model.errorMessage != nil { VPNErrorSection() }
            Section {
                Text("The previous online server feed is unavailable. Your saved servers remain on this device. Add or import a provider's server list in Settings.")
                    .font(.footnote).foregroundColor(.secondary)
            } header: { Text("Server availability") }
            Section {
                if model.servers.isEmpty {
                    Text("No servers saved. Open Settings to add a server or import a JSON list.")
                        .foregroundColor(.secondary)
                }
                ForEach(model.serversByCountry.keys.sorted(), id: \.self) { country in
                    NavigationLink(destination: ServerListView(country: country)) {
                        CountryRow(country: country, count: model.serversByCountry[country]?.count ?? 0)
                    }
                }
            } header: { Text("Countries") }
        }
        .listStyle(.insetGrouped)
    }
}

private struct CountryRow: View {
    let country: String
    let count: Int
    var body: some View {
        HStack {
            Text(country)
            Spacer()
            Text("\(count) \(count == 1 ? "server" : "servers")").foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct VPNStatusView: View {
    @EnvironmentObject private var model: VPNViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.connectionStatus.title, systemImage: model.connectionStatus == .connected ? "lock.shield.fill" : "shield")
                .font(.headline)
                .foregroundColor(model.connectionStatus == .connected ? .green : .primary)
                .accessibilityLabel("VPN status: \(model.connectionStatus.title)")
            if model.canDisconnect {
                if let server = model.selectedServer { Text(server.name).font(.subheadline) }
                Button("Disconnect", role: .destructive) { model.disconnect() }
            } else {
                Text("Traffic is not protected by this app's VPN.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct VPNErrorSection: View {
    @EnvironmentObject private var model: VPNViewModel
    var body: some View {
        Section {
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundColor(.red)
                    .accessibilityLabel("Error: \(error)")
                Button("Dismiss message") { model.errorMessage = nil }
            }
        } header: { Text("Attention") }
    }
}

struct ServerListView: View {
    let country: String
    @EnvironmentObject private var model: VPNViewModel
    private var servers: [VPNServer] { model.serversByCountry[country] ?? [] }

    var body: some View {
        serverList
            .navigationTitle(country)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { model.pingAllServers(servers) } label: {
                        if model.isRefreshingLatency { ProgressView() }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(model.isRefreshingLatency || servers.isEmpty)
                    .accessibilityLabel("Refresh server reachability")
                }
            }
    }

    private var serverList: some View {
        List {
            Section { VPNStatusView() }
            if model.errorMessage != nil { VPNErrorSection() }
            Section {
                ForEach(servers) { server in
                    Button {
                        if model.selectedServer?.id == server.id && model.canDisconnect { model.disconnect() }
                        else { model.connect(to: server) }
                    } label: {
                        ServerRowView(server: server, status: model.selectedServer?.id == server.id ? model.connectionStatus : .disconnected)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Reachability measures a TCP connection to port 443, not VPN speed. An unavailable result does not prove a VPN server is offline. Only an authenticated system VPN configuration can connect.")
            }
        }
    }
}

struct ServerRowView: View {
    let server: VPNServer
    let status: VPNConnectionStatus
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name).font(.body)
                Text(server.ipAddress).font(.caption).foregroundColor(.secondary)
                Text(server.latency.map { "TCP reachability: \($0) ms" } ?? "TCP reachability: unknown")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            if status == .connecting || status == .disconnecting { ProgressView() }
            else {
                Image(systemName: status == .connected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(status == .connected ? .green : .secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Server \(server.name), \(server.latency.map { "TCP reachability \($0) milliseconds" } ?? "Reachability unknown"), status: \(status.title)")
        .accessibilityHint(status == .disconnected ? "Attempts to connect using the app's existing VPN configuration" : "Disconnects the VPN")
    }
}
