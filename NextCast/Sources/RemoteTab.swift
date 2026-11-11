import SwiftUI
import GoogleCast

/// Dark, solid tactile remote keys. Haptic fires at finger-down instead
/// of waiting for the remote command to finish on finger-up.
private struct SolidRemoteKeyStyle: ButtonStyle {
    var fill: Color = Color(red: 0.17, green: 0.19, blue: 0.23)
    var radius: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(configuration.isPressed ? 0.08 : 0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.06 : 0.23),
                    radius: configuration.isPressed ? 1 : 4,
                    y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
                }
            }
    }
}

/// Original Next Cast full-screen remote, designed around the actual
/// capabilities of each supported TV protocol.
struct RemoteTab: View {
    @ObservedObject var remote: RemoteControlModel
    @ObservedObject var cast: CastController
    @State private var showSetup = true
    @State private var showKeyboard = false
    @State private var keyboardText = ""
    @FocusState private var keyboardFocused: Bool
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
            .sheet(isPresented: $showKeyboard) {
                keyboardSheet
            }
            .sheet(isPresented: $remote.androidPINRequired) {
                androidPairingSheet
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
                    Text(remote.brand == .cast
                        ? (cast.isConnected ? "Media connected · TV keys not paired" : "Media not connected")
                        : (remote.connected ? "TV remote paired" : remote.status))
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
                            if brand == .android, !cast.tvIPAddress.isEmpty {
                                remote.address = cast.tvIPAddress
                            }
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
                VStack(alignment: .leading, spacing: 11) {
                    Label(cast.isConnected ? "Cast media session connected" : "Select a Cast receiver",
                          systemImage: "play.tv")
                        .font(.subheadline.bold())
                        .foregroundStyle(cast.isConnected ? Color.green : Color.secondary)
                    Text("Chromecast controls media only. For Home, Back, arrows and OK, you must pair a separate TV remote connection for your television's brand.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !cast.tvModelName.isEmpty {
                        Text("Detected Cast model: \(cast.tvModelName)")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    Menu {
                        Button("Skyworth / Android TV") {
                            remote.select(.android)
                            if !cast.tvIPAddress.isEmpty { remote.address = cast.tvIPAddress }
                            showSetup = true
                        }
                        Button("Samsung Smart TV") {
                            remote.select(.samsung)
                            if !cast.tvIPAddress.isEmpty { remote.address = cast.tvIPAddress }
                            showSetup = true
                        }
                        Button("LG webOS TV") {
                            remote.select(.lg)
                            if !cast.tvIPAddress.isEmpty { remote.address = cast.tvIPAddress }
                            showSetup = true
                        }
                        Button("Roku TV") {
                            remote.select(.roku)
                            if !cast.tvIPAddress.isEmpty { remote.address = cast.tvIPAddress }
                            showSetup = true
                        }
                    } label: {
                        Label("Set Up TV Navigation Remote", systemImage: "appletvremote.gen4")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    HStack(spacing: 12) {
                    CastButton().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Discover Chromecast devices")
                            .font(.subheadline.bold())
                        Text("Tap the Cast icon, then select your TV.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
                    Text(remote.brand == .android
                        ? "Skyworth Android TV: use the TV's IP address (Settings → Network). Android TV Remote Service must be available on the TV; approve pairing and enter its six-character code."
                        : "Find the TV IP in its Network Settings. Some TVs require enabling mobile remote control.")
                        .font(.caption).foregroundStyle(.secondary)
                    if remote.brand == .android && !remote.connected {
                        Button("Pair Android TV Again") {
                            remote.retryAndroidTVPairing()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .nextSurface()
    }

    private var displayName: String {
        remote.brand == .cast
            ? (cast.isConnected ? cast.tvName + " · Cast media" : "No Cast receiver")
            : (remote.deviceName.isEmpty ? remote.brand.rawValue : remote.deviceName)
    }

    private var castNote: some View {
        Label("Cast device connected does not mean TV remote paired. Chromecast media playback and volume are available; navigation keys need a Samsung, LG or Roku remote connection. Google TV / Android TV additionally requires its own secure remote pairing protocol.", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var remoteFace: some View {
        VStack(spacing: 18) {
            HStack(spacing: 15) {
                keyButton(.power, symbol: "power", title: "Power", tint: Color(red: 1, green: 0.35, blue: 0.38))
                keyButton(.home, symbol: "house.fill", title: "Home")
                keyButton(.back, symbol: "arrow.uturn.backward", title: "Back")
            }

            // Fill the available remote width with a 3 × 3 directional grid.
            // Each key occupies a complete square cell; no layout Spacers push
            // the buttons apart. The 5 active keys form the classic D-pad cross.
            GeometryReader { geometry in
                let gap: CGFloat = 7
                let tile = max(1, (geometry.size.width - gap * 2) / 3)
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        Color.clear.frame(width: tile, height: tile)
                            .accessibilityHidden(true)
                        arrowButton(.up, "chevron.up", tile: tile)
                        Color.clear.frame(width: tile, height: tile)
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: gap) {
                        arrowButton(.left, "chevron.left", tile: tile)
                        Button {
                            send(.ok)
                        } label: {
                            Text("OK")
                                .font(.system(size: max(19, tile * 0.24), weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: tile, height: tile)
                                .contentShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(SolidRemoteKeyStyle(
                            fill: Color(red: 0.03, green: 0.53, blue: 0.74), radius: 20))
                        .disabled(!ready || remote.brand == .cast)
                        .opacity(ready && remote.brand != .cast ? 1 : 0.65)
                        .accessibilityLabel("OK")
                        arrowButton(.right, "chevron.right", tile: tile)
                    }
                    HStack(spacing: gap) {
                        Color.clear.frame(width: tile, height: tile)
                            .accessibilityHidden(true)
                        arrowButton(.down, "chevron.down", tile: tile)
                        Color.clear.frame(width: tile, height: tile)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.width)
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(7)
            .background(Color.secondary.opacity(0.075),
                        in: RoundedRectangle(cornerRadius: 26))

            Button {
                keyboardText = ""
                showKeyboard = true
            } label: {
                Label("Keyboard · Type on TV", systemImage: "keyboard")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 58)
            }
            .buttonStyle(SolidRemoteKeyStyle())
            .disabled(!ready || remote.brand == .cast)
            .opacity(ready && remote.brand != .cast ? 1 : 0.35)
            .accessibilityHint("Opens the iPhone keyboard only when needed")

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
        .padding(13)
        .background(.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28).strokeBorder(.secondary.opacity(0.10))
        }
    }

    private func arrowButton(_ key: RemoteCommand, _ symbol: String,
                             tile: CGFloat) -> some View {
        Button { send(key) } label: {
            Image(systemName: symbol)
                .font(.system(size: max(25, min(42, tile * 0.34)), weight: .bold))
                .frame(width: tile, height: tile)
                .foregroundStyle(.white)
                .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(SolidRemoteKeyStyle(radius: 20))
        .disabled(!ready || remote.brand == .cast)
        .opacity(ready && remote.brand != .cast ? 1 : 0.65)
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
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(6)
        }
        .buttonStyle(SolidRemoteKeyStyle())
        .disabled(!ready || unsupported)
        .opacity((ready && !unsupported) ? 1 : 0.35)
    }

    private func send(_ command: RemoteCommand) {
        remote.press(command, cast: cast)
    }

    private var androidPairingSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("Skyworth Android TV pairing", systemImage: "tv")
                    .font(.headline)
                Text("Your TV should show a 6-character pairing code. Enter those characters here to authorize Next Cast as a navigation remote.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("TV code · 6 characters", text: $remote.androidPIN)
                    .font(.title3.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .padding(13)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                Button("Pair & Enable Remote") {
                    remote.submitAndroidTVCode()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .frame(maxWidth: .infinity)
                .disabled(remote.androidPIN.count != 6)
                Text("The Android TV Remote v2 pairing service generally uses ports 6467 and 6466 over local Wi-Fi. If no code appears, check whether Android TV Remote Service is enabled/updated on the TV.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(20)
            .navigationTitle("Pair Android TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        remote.androidPINRequired = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var keyboardSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 15) {
                Label("Type on \(remote.brand.rawValue)", systemImage: "keyboard")
                    .font(.headline)
                Text("First select a search box or text field on your TV. The iPhone keyboard appears only while this panel is open.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("Enter text for your TV", text: $keyboardText, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .focused($keyboardFocused)
                    .padding(12)
                    .background(Color.secondary.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 12))
                    .submitLabel(.done)
                    .onSubmit { keyboardFocused = false }

                Button {
                    remote.typeOnTV(keyboardText)
                    keyboardFocused = false
                } label: {
                    Label("Send Text to TV", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(keyboardText.isEmpty || keyboardText.count > 512)

                Button {
                    remote.finishTextEntry()
                    keyboardFocused = false
                    showKeyboard = false
                } label: {
                    Label("Enter / Finish on TV", systemImage: "return")
                        .frame(maxWidth: .infinity)
                        .frame(height: 45)
                }
                .buttonStyle(.bordered)

                Text("Typing requires a TV text field to be focused. Android TV accepts basic ASCII key events, while Roku, Samsung and LG use their respective input protocols. Chromecast media receivers do not support general typing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Remote Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        keyboardFocused = false
                        showKeyboard = false
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    keyboardFocused = true
                }
            }
        }
        .presentationDetents([.large])
    }

    private var protocolFootnote: String {
        switch remote.brand {
        case .cast:
            return "Cast playback and volume work when a media session is active. The default Cast receiver does not expose a universal TV-keyboard or D-pad."
        case .android:
            return "Skyworth Android TV uses Remote v2 over Wi-Fi with a one-time on-TV pairing code. Cast media and TV navigation are separate connections; Home, D-pad, Back and OK enable after remote pairing."
        case .roku:
            return "Roku ECP over Wi-Fi (port 8060). On Roku OS 14.1+, enable Settings → System → Advanced system settings → Control by mobile apps. Volume and power require a Roku TV or supported device."
        case .samsung:
            return "Samsung Tizen pairing over local WebSocket (port 8002). Accept the TV's authorization popup. Model and firmware support vary; older TVs may require a different network protocol."
        case .lg:
            return "LG webOS SSAP and pointer input over local WebSockets. Approve Next Cast on the TV when prompted. Some models do not expose every key."
        }
    }
}
