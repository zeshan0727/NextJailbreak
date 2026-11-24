import SwiftUI
import GoogleCast

/// Original Next Cast full-screen remote, designed around the actual
/// capabilities of each supported TV protocol.
struct RemoteTab: View {
    @ObservedObject var remote: RemoteControlModel
    @ObservedObject var cast: CastController
    @State private var showSetup = true
    @State private var showNumbers = false
    @Environment(\.dismiss) private var dismiss

    private var ready: Bool {
        remote.brand == .cast ? cast.isConnected : remote.connected
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 17) {
                    connectionPanel
                    if remote.brand != .cast && !ready {
                        Text("Connect to a TV to enable its remote buttons.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if remote.brand == .cast {
                        castNote
                    }
                    remoteFace
                    if remote.brand != .cast {
                        HStack(spacing: 10) {
                            keyButton(.info, symbol: "info.circle", title: "Info")
                            keyButton(.channelDown, symbol: "minus", title: "CH −")
                            keyButton(.channelUp, symbol: "plus", title: "CH +")
                        }
                        .padding(.horizontal, 10)
                    }
                    Text(protocolFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    Text("Remote controls work only with a compatible TV on the same Wi-Fi network. No external account is required.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(17)
            }
            .navigationTitle("TV Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Connection settings", systemImage: "wifi") { showSetup.toggle() }
                        if remote.brand != .cast && remote.connected {
                            Button("Disconnect", systemImage: "xmark.circle") { remote.disconnect() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("TV Remote", isPresented: Binding(
                get: { remote.alertText != nil },
                set: { if !$0 { remote.alertText = nil } }
            )) {
                Button("OK") { remote.alertText = nil }
            } message: {
                Text(remote.alertText ?? "")
            }
        }
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "tv.fill")
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ready ? displayName : "Select a TV")
                        .font(.headline)
                    Text(ready ? "Connected" : remote.status)
                        .font(.caption)
                        .foregroundStyle(ready ? .green : .secondary)
                        .lineLimit(3)
                }
                Spacer()
                Circle()
                    .fill(ready ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(RemoteBrand.allCases) { brand in
                        Button {
                            remote.select(brand)
                            showSetup = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: brand.symbol)
                                Text(brand.rawValue)
                            }
                            .font(.caption.bold())
                            .foregroundStyle(remote.brand == brand ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(remote.brand == brand ? Color.cyan : Color.secondary.opacity(0.10),
                                        in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if remote.brand == .cast {
                HStack(spacing: 12) {
                    CastButton().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Discover Chromecast devices")
                            .font(.subheadline.bold())
                        Text("Tap the Cast icon, then select your TV.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if showSetup || !remote.connected {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 9) {
                        Image(systemName: "network")
                        TextField("TV IP address · 192.168.1.25", text: $remote.address)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(12)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    HStack(spacing: 10) {
                        Button {
                            remote.connect()
                        } label: {
                            Label(remote.connected ? "Reconnect" : "Connect to TV", systemImage: "wifi")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .foregroundStyle(.black)
                        if remote.connected {
                            Button("Done") { showSetup = false }
                                .buttonStyle(.bordered)
                        }
                    }
                    if remote.pairing {
                        Label("Accept the pairing prompt on the television.", systemImage: "hand.tap")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    Text("Find the TV IP in its Network Settings. Some TVs require enabling mobile remote control.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .nextSurface()
    }

    private var displayName: String {
        remote.brand == .cast ? cast.tvName : (remote.deviceName.isEmpty ? remote.brand.rawValue : remote.deviceName)
    }

    private var castNote: some View {
        Label("Chromecast supports media playback and volume. TV D-pad, Home, channel, and power keys require a separate TV-specific protocol.", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var remoteFace: some View {
        VStack(spacing: 18) {
            HStack(spacing: 15) {
                keyButton(.power, symbol: "power", title: "Power", tint: .red)
                Spacer()
                keyButton(.home, symbol: "house.fill", title: "Home")
                keyButton(.back, symbol: "arrow.uturn.backward", title: "Back")
            }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    arrowButton(.up, "chevron.up")
                    Spacer()
                }
                HStack(spacing: 14) {
                    arrowButton(.left, "chevron.left")
                    Spacer(minLength: 0)
                    Button {
                        send(.ok)
                    } label: {
                        Text("OK")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 74, height: 74)
                            .background(.cyan, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!ready || remote.brand == .cast)
                    .opacity(ready && remote.brand != .cast ? 1 : 0.35)
                    Spacer(minLength: 0)
                    arrowButton(.right, "chevron.right")
                }
                HStack {
                    Spacer()
                    arrowButton(.down, "chevron.down")
                    Spacer()
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.075), in: RoundedRectangle(cornerRadius: 38))

            HStack(spacing: 18) {
                keyButton(.rewind, symbol: "backward.end.fill", title: "Back 10s")
                keyButton(.playPause, symbol: cast.isPlaying && remote.brand == .cast ? "pause.fill" : "playpause.fill", title: "Play / Pause")
                keyButton(.forward, symbol: "forward.end.fill", title: "Forward 10s")
            }

            HStack(spacing: 10) {
                VStack(spacing: 11) {
                    Text("VOLUME").font(.caption2.bold()).tracking(1.6).foregroundStyle(.secondary)
                    keyButton(.volumeUp, symbol: "speaker.plus.fill", title: "Vol +")
                    keyButton(.volumeDown, symbol: "speaker.minus.fill", title: "Vol −")
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 11) {
                    Text("AUDIO").font(.caption2.bold()).tracking(1.6).foregroundStyle(.secondary)
                    keyButton(.mute, symbol: "speaker.slash.fill", title: "Mute")
                    if remote.brand == .cast {
                        Text("\(Int(cast.remoteVolume * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(height: 56)
                    } else {
                        keyButton(.info, symbol: "line.3.horizontal.decrease", title: "Info")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(22)
        .background(.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28).strokeBorder(.secondary.opacity(0.10))
        }
    }

    private func arrowButton(_ key: RemoteCommand, _ symbol: String) -> some View {
        Button { send(key) } label: {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .frame(width: 75, height: 67)
                .foregroundStyle(.primary)
                .background(Color.secondary.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(!ready || remote.brand == .cast)
        .opacity(ready && remote.brand != .cast ? 1 : 0.35)
        .accessibilityLabel(key.rawValue.capitalized)
    }

    private func keyButton(_ key: RemoteCommand, symbol: String, title: String,
                           tint: Color = .cyan) -> some View {
        let unsupported = remote.brand == .cast &&
            ![RemoteCommand.playPause, .rewind, .forward, .volumeUp, .volumeDown, .mute].contains(key)
        return Button { send(key) } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(height: 29)
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(6)
            .background(Color.secondary.opacity(0.095),
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!ready || unsupported)
        .opacity((ready && !unsupported) ? 1 : 0.35)
    }

    private func send(_ command: RemoteCommand) {
        remote.press(command, cast: cast)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var protocolFootnote: String {
        switch remote.brand {
        case .cast:
            return "Cast playback and volume work when a media session is active. The default Cast receiver does not expose a universal TV-keyboard or D-pad."
        case .roku:
            return "Roku ECP over Wi-Fi (port 8060). On Roku OS 14.1+, enable Settings → System → Advanced system settings → Control by mobile apps. Volume and power require a Roku TV or supported device."
        case .samsung:
            return "Samsung Tizen pairing over local WebSocket (port 8002). Accept the TV's authorization popup. Model and firmware support vary; older TVs may require a different network protocol."
        case .lg:
            return "LG webOS SSAP and pointer input over local WebSockets. Approve Next Cast on the TV when prompted. Some models do not expose every key."
        }
    }
}
