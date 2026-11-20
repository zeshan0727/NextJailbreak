import SwiftUI
import GoogleCast

/// A tactile visual press state; the controller sends haptics centrally,
/// including the plain-style D-pad and gesture-driven touchpad.
private struct SolidRemoteKeyStyle: ButtonStyle {
    var fill: Color = Color(red: 0.17, green: 0.19, blue: 0.23)
    var radius: CGFloat = 15
    var stroke: Color = .white.opacity(0.14)
    var glow: Color = .black.opacity(0.22)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(configuration.isPressed ? stroke.opacity(0.32) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(stroke.opacity(configuration.isPressed ? 1 : 0.8),
                              lineWidth: configuration.isPressed ? 2 : 1))
            .shadow(color: glow.opacity(configuration.isPressed ? 0.4 : 0.55),
                    radius: configuration.isPressed ? 1 : 8,
                    y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

/// NexaPlay compatible full-screen multi-brand remote, designed around the actual
/// capabilities of each supported TV protocol.
struct RemoteTab: View {
    @ObservedObject var remote: RemoteControlModel
    @ObservedObject var cast: CastController
    @Environment(\.colorScheme) private var scheme
    @State private var showSetup = true
    // Visual-only preferences. These do not touch saved TV pairing, commands,
    // network sessions, or the existing Keychain client identity.
    @AppStorage("nextcast.remote.visualStyle") private var visualStyleRaw = NexaRemoteStyle.modernDark.rawValue
    @AppStorage("nextcast.remote.controlLayout") private var controlLayoutRaw = NexaRemoteLayout.dpad.rawValue
    @State private var showStyleChooser = false
    @State private var showRemoteInfo = false
    @AppStorage("nextcast.remote.hapticsEnabled") private var hapticsEnabled = true
    @State private var lastPressedCommand: RemoteCommand?
    @State private var commandFeedbackGeneration = 0

    private var visualStyle: NexaRemoteStyle {
        NexaRemoteStyle(rawValue: visualStyleRaw) ?? .modernDark
    }

    private var controlLayout: NexaRemoteLayout {
        NexaRemoteLayout(rawValue: controlLayoutRaw) ?? .dpad
    }

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
                VStack(spacing: 14) {
                    connectionPanel
                    remoteFace
                    if remote.brand != .cast {
                        HStack(spacing: 9) {
                            keyButton(.channelDown, symbol: "minus", title: "CH −")
                            keyButton(.channelUp, symbol: "plus", title: "CH +")
                        }
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRemoteInfo.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                            Text("Remote compatibility")
                            Spacer()
                            Image(systemName: showRemoteInfo ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(visualStyle.secondary)
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                    if showRemoteInfo {
                        Text(protocolFootnote)
                            .font(.caption)
                            .foregroundStyle(visualStyle.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                            .background(visualStyle.surface,
                                        in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
            }
            .background(visualStyle.canvas.ignoresSafeArea())
            .navigationTitle("TV Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showStyleChooser = true
                    } label: {
                        Label("Styles", systemImage: "paintpalette.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(visualStyle.accent)
                    .accessibilityLabel("Choose remote appearance")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showStyleChooser = true
                        } label: {
                            Label("Remote Style", systemImage: "paintpalette")
                        }
                        Button {
                            showSetup.toggle()
                        } label: {
                            Label("Connection Settings", systemImage: "wifi")
                        }
                        if remote.brand != .cast && remote.connected {
                            Button {
                                remote.disconnect()
                            } label: {
                                Label("Disconnect", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .tint(visualStyle.accent)
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
            .sheet(isPresented: $showKeyboard) { keyboardSheet }
            .sheet(isPresented: $remote.androidPINRequired) { androidPairingSheet }
            .sheet(isPresented: $showStyleChooser) { styleChooser }
            .onAppear {
                // Keep Build 39 pairing lifecycle unmodified.
                showSetup = !remote.connected && !remote.hasSavedAndroidTVPairing
                remote.restoreSavedAndroidTVConnectionIfNeeded()
            }
            .onChange(of: remote.connected) { connected in
                if connected { showSetup = false }
            }
        }
        .preferredColorScheme(visualStyle.isLight ? .light : .dark)
    }

    private var styleChooser: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose your remote style")
                        .font(.title3.bold())
                    Text("Switch instantly. Your TV connection and button functions stay the same.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)], spacing: 14) {
                        ForEach(NexaRemoteStyle.allCases) { choice in
                            Button {
                                visualStyleRaw = choice.rawValue
                                selectionHaptic()
                            } label: {
                                NexaRemoteStyleSwatch(style: choice,
                                                    selected: visualStyle == choice)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.title)
                        }
                    }
                    Toggle(isOn: $hapticsEnabled) {
                        Label("Remote vibration", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    .tint(visualStyle.accent)
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 15))
                    Text("Your style, layout and vibration preference are saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .navigationTitle("Remote Styles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showStyleChooser = false }
                        .tint(visualStyle.accent)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func selectTVBrand(_ brand: RemoteBrand) {
        remote.select(brand)
        // Respect the previously stored address. Cast discovery may report a
        // different receiver or a stale IP and must not overwrite paired TV.
        if remote.address.isEmpty, brand != .cast, !cast.tvIPAddress.isEmpty {
            remote.address = cast.tvIPAddress
        }
        showSetup = !remote.connected && !remote.hasSavedAndroidTVPairing
        remote.restoreSavedAndroidTVConnectionIfNeeded()
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "tv.fill")
                    .foregroundStyle(visualStyle.accent)
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
                            selectTVBrand(brand)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: brand.symbol)
                                Text(brand.rawValue)
                            }
                            .font(.caption.bold())
                            .foregroundStyle(remote.brand == brand ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(remote.brand == brand ? visualStyle.accent : visualStyle.key,
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
                            selectTVBrand(.android)
                        }
                        Button("Samsung Smart TV") {
                            selectTVBrand(.samsung)
                        }
                        Button("LG webOS TV") {
                            selectTVBrand(.lg)
                        }
                        Button("Roku TV") {
                            selectTVBrand(.roku)
                        }
                    } label: {
                        Label("Set Up TV Navigation Remote", systemImage: "appletvremote.gen4")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(visualStyle.accent)
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
            } else if showSetup || (!remote.connected && !remote.pairing) {
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
                        .tint(visualStyle.accent)
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
                        ? (remote.hasSavedAndroidTVPairing
                           ? "Saved pairing retained. Reconnect without a code; pair again only if the TV was reset."
                           : "First connection requires the six-character code shown on TV.")
                        : "Use your TV's local network address.")
                        .font(.caption).foregroundStyle(.secondary)
                    if remote.brand == .android && !remote.connected {
                        Button("Pair TV Again (new code)") {
                            remote.retryAndroidTVPairing()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(15)
        .background(visualStyle.surface,
                    in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous)
            .strokeBorder(visualStyle.stroke, lineWidth: 1))
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
        VStack(spacing: 15) {
            HStack {
                Text("CONTROLS")
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(visualStyle.secondary)
                Spacer()
                Button {
                    showStyleChooser = true
                } label: {
                    Label(visualStyle.title, systemImage: "paintpalette")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(visualStyle.accent)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 5) {
                ForEach(NexaRemoteLayout.allCases) { mode in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            controlLayoutRaw = mode.rawValue
                        }
                        selectionHaptic()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.caption2)
                            Text(mode.title)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(controlLayout == mode ?
                                         (visualStyle.isLight ? Color.white : Color.white) :
                                         visualStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(controlLayout == mode ? visualStyle.accent : .clear,
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(controlLayout == mode ? [.isSelected] : [])
                }
            }
            .padding(4)
            .background(visualStyle.key, in: Capsule())

            HStack(spacing: 12) {
                keyButton(.power, symbol: "power", title: "Power",
                          tint: Color(red: 1, green: 0.27, blue: 0.22))
                keyButton(.mute, symbol: "speaker.slash.fill", title: "Mute")
                keyButton(.info, symbol: "info.circle", title: "Info")
            }

            selectedControlSurface

            HStack(spacing: 12) {
                keyButton(.back, symbol: "arrow.uturn.backward", title: "Back")
                keyButton(.home, symbol: "house.fill", title: "Home", tint: visualStyle.accent)
                keyButton(.info, symbol: "line.3.horizontal", title: "Menu / Info")
            }

            HStack(spacing: 10) {
                keyButton(.rewind, symbol: "backward.end.fill", title: "Rewind")
                keyButton(.playPause,
                          symbol: cast.isPlaying && remote.brand == .cast ? "pause.fill" : "playpause.fill",
                          title: "Play / Pause", tint: visualStyle.accent)
                keyButton(.forward, symbol: "forward.end.fill", title: "Forward")
            }

            HStack(spacing: 12) {
                keyButton(.volumeDown, symbol: "speaker.minus.fill", title: "Vol −")
                keyButton(.volumeUp, symbol: "speaker.plus.fill", title: "Vol +")
                if remote.brand == .cast {
                    Text("\(Int(cast.remoteVolume * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(visualStyle.text)
                        .frame(maxWidth: .infinity, minHeight: 63)
                } else {
                    keyButton(.mute, symbol: "speaker.slash", title: "Mute")
                }
            }

            Button {
                keyboardText = ""
                showKeyboard = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "keyboard")
                        .font(.title3)
                    Text("Open TV Keyboard")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundStyle(visualStyle.text)
                .padding(14)
            }
            .buttonStyle(SolidRemoteKeyStyle(fill: visualStyle.key, radius: 15,
                                             stroke: visualStyle.stroke, glow: visualStyle.shadow))
            .disabled(!ready || remote.brand == .cast)
            .opacity(ready && remote.brand != .cast ? 1 : 0.45)
        }
        .padding(14)
        .background(visualStyle.surface,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(visualStyle.stroke, lineWidth: 1))
    }

    @ViewBuilder
    private var selectedControlSurface: some View {
        switch controlLayout {
        case .dpad: dpadWheel
        case .touchpad: touchSurface
        case .keys: quickKeys
        }
    }

    private var dpadWheel: some View {
        ZStack {
            Circle()
                .fill(visualStyle.key)
                .overlay(Circle().strokeBorder(visualStyle.stroke,
                                             lineWidth: visualStyle == .neon ? 2.5 : 1))
                .shadow(color: visualStyle.shadow, radius: visualStyle == .neon ? 18 : 6, y: 4)

            wheelButton(.up, symbol: "chevron.up", x: 0, y: -91)
            wheelButton(.left, symbol: "chevron.left", x: -91, y: 0)
            wheelButton(.right, symbol: "chevron.right", x: 91, y: 0)
            wheelButton(.down, symbol: "chevron.down", x: 0, y: 91)

            Button { send(.ok) } label: {
                Text("OK")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(visualStyle.text)
                    .frame(width: 91, height: 91)
                    .background(lastPressedCommand == .ok ?
                                visualStyle.accent.opacity(0.3) : visualStyle.canvas, in: Circle())
                    .overlay(Circle().strokeBorder(visualStyle.accent,
                                                 lineWidth: lastPressedCommand == .ok ? 4 : 2))
                    .shadow(color: visualStyle.shadow, radius: 10)
            }
            .buttonStyle(.plain)
            .disabled(!ready || remote.brand == .cast)
            .opacity(ready && remote.brand != .cast ? 1 : 0.45)
            .accessibilityLabel("OK")
        }
        .frame(width: 270, height: 270)
        .frame(maxWidth: .infinity)
    }

    private func wheelButton(_ command: RemoteCommand, symbol: String,
                             x: CGFloat, y: CGFloat) -> some View {
        Button { send(command) } label: {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(lastPressedCommand == command ?
                                 visualStyle.accent : visualStyle.text)
                .frame(width: 70, height: 70)
                .background(lastPressedCommand == command ?
                            visualStyle.accent.opacity(0.24) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: x, y: y)
        .disabled(!ready || remote.brand == .cast)
        .opacity(ready && remote.brand != .cast ? 1 : 0.45)
        .accessibilityLabel(command.rawValue.capitalized)
    }

    /// These gestures translate only into the SAME already-supported
    /// D-pad/OK commands. No TV protocol or pairing behavior is changed.
    private var touchSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(lastPressedCommand == nil ?
                      visualStyle.key : visualStyle.accent.opacity(0.23))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(visualStyle.accent.opacity(0.85),
                                  lineWidth: lastPressedCommand == nil ? 1.5 : 3))
                .shadow(color: visualStyle.shadow, radius: 10, y: 2)
            VStack(spacing: 13) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(visualStyle.accent)
                Text("Touch to navigate")
                    .font(.headline)
                    .foregroundStyle(visualStyle.text)
                Text("Swipe directions  ·  Tap for OK")
                    .font(.caption)
                    .foregroundStyle(visualStyle.secondary)
            }
        }
        .frame(height: 250)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {
            guard ready && remote.brand != .cast else { return }
            send(.ok)
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { movement in
                    guard ready && remote.brand != .cast else { return }
                    let x = movement.translation.width
                    let y = movement.translation.height
                    guard max(abs(x), abs(y)) >= 32 else { return }
                    if abs(x) > abs(y) {
                        send(x > 0 ? .right : .left)
                    } else {
                        send(y > 0 ? .down : .up)
                    }
                }
        )
        .opacity(ready && remote.brand != .cast ? 1 : 0.45)
        .accessibilityLabel("TV touchpad. Swipe to navigate, tap to select.")
    }

    private var quickKeys: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
            keyButton(.volumeDown, symbol: "speaker.minus.fill", title: "Vol −")
            keyButton(.volumeUp, symbol: "speaker.plus.fill", title: "Vol +")
            keyButton(.mute, symbol: "speaker.slash.fill", title: "Mute")
            keyButton(.home, symbol: "house.fill", title: "Home")
            keyButton(.back, symbol: "arrow.uturn.backward", title: "Back")
            keyButton(.info, symbol: "info.circle", title: "Info")
            keyButton(.power, symbol: "power", title: "Power")
            keyButton(.channelDown, symbol: "minus", title: "CH −")
            keyButton(.channelUp, symbol: "plus", title: "CH +")
        }
        .padding(.vertical, 9)
    }

    private func keyButton(_ key: RemoteCommand, symbol: String, title: String,
                           tint: Color? = nil) -> some View {
        let unsupported = remote.brand == .cast &&
            ![RemoteCommand.playPause, .rewind, .forward, .volumeUp,
              .volumeDown, .mute].contains(key)
        return Button { send(key) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint ?? visualStyle.text)
                    .frame(height: 26)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(visualStyle.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.horizontal, 3)
            .background(lastPressedCommand == key ?
                        visualStyle.accent.opacity(0.24) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(SolidRemoteKeyStyle(fill: visualStyle.key, radius: 15,
                                         stroke: visualStyle.stroke, glow: visualStyle.shadow))
        .disabled(!ready || unsupported)
        .opacity(ready && !unsupported ? 1 : 0.4)
        .accessibilityLabel(title)
    }

    private func send(_ command: RemoteCommand) {
        // The same command dispatch as previous builds. Feedback acknowledges
        // the local tap, NOT delivery confirmation from the television.
        if hapticsEnabled {
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.prepare()
            feedback.impactOccurred(intensity: 0.95)
        }
        commandFeedbackGeneration += 1
        let generation = commandFeedbackGeneration
        withAnimation(.easeOut(duration: 0.09)) {
            lastPressedCommand = command
        }
        remote.press(command, cast: cast)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            guard generation == commandFeedbackGeneration else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                lastPressedCommand = nil
            }
        }
    }

    private func selectionHaptic() {
        guard hapticsEnabled else { return }
        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
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
                .tint(NexaPalette.orange)
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
                .tint(NexaPalette.orange)
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
