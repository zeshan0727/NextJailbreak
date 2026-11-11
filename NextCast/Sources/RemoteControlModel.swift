import SwiftUI
import Foundation
import Combine
import Security

enum RemoteBrand: String, CaseIterable, Identifiable {
    case cast = "Chromecast"
    case android = "Android TV"
    case roku = "Roku TV"
    case samsung = "Samsung TV"
    case lg = "LG webOS"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .cast: return "dot.radiowaves.left.and.right"
        case .android: return "tv.fill"
        case .roku: return "tv"
        case .samsung: return "display"
        case .lg: return "tv.and.hifispeaker.fill"
        }
    }
}

enum RemoteCommand: String {
    case up, down, left, right, ok, back, home, playPause
    case rewind, forward, volumeUp, volumeDown, mute, power, channelUp, channelDown, info

    var rokuKey: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .ok: return "Select"
        case .back: return "Back"
        case .home: return "Home"
        case .playPause: return "Play"
        case .rewind: return "Rev"
        case .forward: return "Fwd"
        case .volumeUp: return "VolumeUp"
        case .volumeDown: return "VolumeDown"
        case .mute: return "VolumeMute"
        case .power: return "PowerOff"
        case .channelUp: return "ChannelUp"
        case .channelDown: return "ChannelDown"
        case .info: return "Info"
        }
    }

    var samsungKey: String {
        switch self {
        case .up: return "KEY_UP"
        case .down: return "KEY_DOWN"
        case .left: return "KEY_LEFT"
        case .right: return "KEY_RIGHT"
        case .ok: return "KEY_ENTER"
        case .back: return "KEY_RETURN"
        case .home: return "KEY_HOME"
        case .playPause: return "KEY_PLAY"
        case .rewind: return "KEY_REWIND"
        case .forward: return "KEY_FF"
        case .volumeUp: return "KEY_VOLUP"
        case .volumeDown: return "KEY_VOLDOWN"
        case .mute: return "KEY_MUTE"
        case .power: return "KEY_POWEROFF"
        case .channelUp: return "KEY_CHUP"
        case .channelDown: return "KEY_CHDOWN"
        case .info: return "KEY_INFO"
        }
    }

    var lgKey: String {
        switch self {
        case .up: return "UP"
        case .down: return "DOWN"
        case .left: return "LEFT"
        case .right: return "RIGHT"
        case .ok: return "ENTER"
        case .back: return "BACK"
        case .home: return "HOME"
        case .playPause: return "PLAY"
        case .rewind: return "REWIND"
        case .forward: return "FASTFORWARD"
        case .volumeUp: return "VOLUMEUP"
        case .volumeDown: return "VOLUMEDOWN"
        case .mute: return "MUTE"
        case .power: return "POWER"
        case .channelUp: return "CHANNELUP"
        case .channelDown: return "CHANNELDOWN"
        case .info: return "INFO"
        }
    }
}

@MainActor
final class RemoteControlModel: NSObject, ObservableObject, @preconcurrency URLSessionDelegate {
    @Published var brand: RemoteBrand = .cast
    @Published var address = ""
    @Published private(set) var connected = false
    @Published private(set) var deviceName = ""
    @Published var status = "Choose your TV."
    @Published var alertText: String?
    @Published var pairing = false
    @Published var androidPINRequired = false
    @Published var androidPIN = ""

    private var androidBridge: AndroidTVRemoteBridge?
    private var controlSession: URLSession?
    private var controlSocket: URLSessionWebSocketTask?
    private var pointerSocket: URLSessionWebSocketTask?
    private var activeBrand: RemoteBrand?
    private var activeHost = ""
    private var serial = UUID()
    private var lgRequestID = 0
    private var sessionToken: String?
    private let savedHostKey = "nextcast.remote.host."
    private let savedBrandKey = "nextcast.remote.brand"

    override init() {
        super.init()
        if let raw = UserDefaults.standard.string(forKey: savedBrandKey),
           let value = RemoteBrand(rawValue: raw) { brand = value }
        address = UserDefaults.standard.string(forKey: savedHostKey + brand.rawValue) ?? ""
    }

    func select(_ value: RemoteBrand) {
        if activeBrand != value { disconnect() }
        brand = value
        address = UserDefaults.standard.string(forKey: savedHostKey + value.rawValue) ?? ""
        status = value == .cast ? "Use the Cast button to discover your Chromecast." :
            "Enter your TV's local IP address and connect."
        UserDefaults.standard.set(value.rawValue, forKey: savedBrandKey)
    }

    private func validatedHost(_ text: String) -> String? {
        let host = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only local IP literals are accepted; they are user supplied,
        // never extracted from downloaded pages or QR codes.
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({
            !$0.isEmpty && $0.count <= 3 && $0.allSatisfy(\.isNumber) &&
            (Int($0) ?? 256) <= 255
        }) else { return nil }
        return host
    }

    func connect() {
        disconnect()
        guard brand != .cast else {
            status = "Tap the Cast icon to choose a compatible receiver."
            return
        }
        guard let host = validatedHost(address) else {
            alertText = "Enter the TV's local IPv4 address, such as 192.168.1.25."
            return
        }
        address = host
        activeHost = host
        activeBrand = brand
        serial = UUID()
        status = "Connecting…"
        UserDefaults.standard.set(host, forKey: savedHostKey + brand.rawValue)
        switch brand {
        case .android: connectAndroid(host: host, generation: serial)
        case .roku: connectRoku(host: host, generation: serial)
        case .samsung: connectSamsung(host: host, generation: serial)
        case .lg: connectLG(host: host, generation: serial)
        case .cast: break
        }
    }

    func disconnect() {
        serial = UUID()
        androidBridge?.disconnect()
        androidBridge = nil
        androidPINRequired = false
        androidPIN = ""
        controlSocket?.cancel(with: .goingAway, reason: nil)
        pointerSocket?.cancel(with: .goingAway, reason: nil)
        controlSession?.invalidateAndCancel()
        controlSocket = nil
        pointerSocket = nil
        controlSession = nil
        activeBrand = nil
        activeHost = ""
        connected = false
        deviceName = ""
        pairing = false
    }

    private func connectAndroid(host: String, generation: UUID) {
        pairing = true
        connected = false
        deviceName = "Skyworth / Android TV"
        do {
            let bridge = try AndroidTVRemoteBridge()
            androidBridge = bridge
            bridge.onStatus = { [weak self] message in
                guard let self, self.serial == generation else { return }
                self.status = message
            }
            bridge.onPairingCodeRequired = { [weak self] in
                guard let self, self.serial == generation else { return }
                self.androidPIN = ""
                self.androidPINRequired = true
                self.status = "Enter the six-character TV pairing code."
            }
            bridge.onConnected = { [weak self] connected in
                guard let self, self.serial == generation else { return }
                self.connected = connected
                self.pairing = !connected
                if connected {
                    self.androidPINRequired = false
                    self.status = "Android TV remote paired · D-pad enabled"
                }
            }
            bridge.onError = { [weak self] message in
                guard let self, self.serial == generation else { return }
                self.pairing = false
                self.status = message
                self.alertText = message
            }
            status = "Connecting Skyworth Android TV Remote v2…"
            bridge.connect(host)
        } catch {
            pairing = false
            alertText = "Android TV pairing identity error: \(error.localizedDescription)"
            status = "Could not establish Android TV remote connection"
        }
    }

    func submitAndroidTVCode() {
        guard brand == .android else { return }
        let code = androidPIN.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6, code.allSatisfy({ $0.isHexDigit }) else {
            alertText = "Enter the six-character code shown on the TV (0–9, A–F)."
            return
        }
        androidPINRequired = false
        androidBridge?.submitCode(code)
    }

    func retryAndroidTVPairing() {
        guard brand == .android, !activeHost.isEmpty else { return }
        pairing = true
        androidBridge?.startPairing()
    }

    private func connectRoku(host: String, generation: UUID) {
        guard let url = URL(string: "http://\(host):8060/query/device-info") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self, self.serial == generation else { return }
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                      let xml = String(data: data, encoding: .utf8),
                      xml.contains("<device-info") else {
                    self.status = "Roku unavailable. Check IP and TV Settings → System → Advanced → Control by mobile apps."
                    self.alertText = error?.localizedDescription ?? "Roku did not respond on port 8060."
                    return
                }
                self.connected = true
                self.deviceName = self.xmlValue("friendly-device-name", in: xml) ??
                    self.xmlValue("model-name", in: xml) ?? "Roku"
                self.status = "Connected · \(self.deviceName)"
            }
        }.resume()
    }

    private func xmlValue(_ key: String, in xml: String) -> String? {
        let first = "<" + key + ">"
        let last = "</" + key + ">"
        guard let a = xml.range(of: first), let b = xml.range(of: last),
              a.upperBound <= b.lowerBound else { return nil }
        return String(xml[a.upperBound..<b.lowerBound])
    }

    private func connectSamsung(host: String, generation: UUID) {
        // Modern Samsung TVs use the 8002 TLS WebSocket; older TV models
        // may accept the non-TLS endpoint on 8001.
        let name = Data("Next Cast Remote".utf8).base64EncodedString()
        let tokenKey = "nextcast.samsung.token.\(host)"
        let savedToken = UserDefaults.standard.string(forKey: tokenKey)
        sessionToken = savedToken
        var urlText = "wss://\(host):8002/api/v2/channels/samsung.remote.control?name=\(name)"
        if let savedToken, let token = savedToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlText += "&token=\(token)"
        }
        guard let url = URL(string: urlText) else { return }
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        controlSession = session
        let task = session.webSocketTask(with: url)
        controlSocket = task
        task.resume()
        status = "Connecting to Samsung · allow Next Cast on the TV."
        pairing = true
        readSocket(task, brand: .samsung, generation: generation)
    }

    private func connectLG(host: String, generation: UUID) {
        guard let url = URL(string: "ws://\(host):3000") else { return }
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        controlSession = session
        let task = session.webSocketTask(with: url)
        controlSocket = task
        task.resume()
        status = "Pairing LG webOS · accept the prompt on your TV."
        pairing = true
        let manifest: [String: Any] = [
            "manifestVersion": 1,
            "appVersion": "1.0",
            "permissions": [
                "CONTROL_AUDIO", "CONTROL_INPUT_JOYSTICK", "CONTROL_INPUT_MEDIA_PLAYBACK",
                "CONTROL_INPUT_TV", "CONTROL_MOUSE_AND_KEYBOARD",
                "READ_CURRENT_CHANNEL", "READ_RUNNING_APPS", "LAUNCH",
                "CONTROL_POWER", "WRITE_NOTIFICATION_TOAST"
            ],
            "signatures": [["signatureVersion": 1, "signature": "nextcast"]]
        ]
        var payload: [String: Any] = ["forcePairing": false, "manifest": manifest]
        if let key = UserDefaults.standard.string(forKey: "nextcast.lg.clientKey.\(host)") {
            payload["client-key"] = key
        }
        sendJSON(["type":"register","id":"register","payload":payload], socket: task)
        readSocket(task, brand: .lg, generation: generation)
    }

    private func readSocket(_ socket: URLSessionWebSocketTask, brand: RemoteBrand,
                            generation: UUID, pointer: Bool = false) {
        socket.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.serial == generation else { return }
                switch result {
                case .failure(let error):
                    if pointer {
                        self.status = "Pointer channel disconnected: \(error.localizedDescription)"
                    } else {
                        self.connected = false
                        self.pairing = false
                        self.status = "TV connection failed. Verify the TV is on the same Wi-Fi network."
                        self.alertText = error.localizedDescription
                    }
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.processMessage(text, brand: brand, pointer: pointer, generation: generation)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.processMessage(text, brand: brand, pointer: pointer, generation: generation)
                        }
                    @unknown default: break
                    }
                    self.readSocket(socket, brand: brand, generation: generation, pointer: pointer)
                }
            }
        }
    }

    private func processMessage(_ text: String, brand: RemoteBrand,
                                pointer: Bool, generation: UUID) {
        guard let data = text.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = dict["type"] as? String ?? ""
        if brand == .samsung {
            let event = dict["event"] as? String ?? ""
            if event == "ms.channel.connect" {
                if let payload = dict["data"] as? [String: Any],
                   let token = payload["token"] as? String {
                    UserDefaults.standard.set(token, forKey: "nextcast.samsung.token.\(activeHost)")
                }
                connected = true
                pairing = false
                deviceName = "Samsung Smart TV"
                status = "Connected · Samsung Smart TV"
            } else if event == "ms.channel.unauthorized" {
                status = "Pairing declined on the Samsung TV. Allow Next Cast in Device Connection Manager."
                pairing = false
            }
        } else if brand == .lg {
            if type == "registered" {
                if let payload = dict["payload"] as? [String: Any],
                   let key = payload["client-key"] as? String {
                    UserDefaults.standard.set(key, forKey: "nextcast.lg.clientKey.\(activeHost)")
                }
                connected = true
                deviceName = "LG webOS TV"
                status = "Connected · LG webOS TV"
                pairing = false
                requestLG("ssap://com.webos.service.networkinput/getPointerInputSocket", id: "pointer")
            } else if type == "response", (dict["id"] as? String) == "pointer" {
                if let payload = dict["payload"] as? [String: Any],
                   let socketPath = payload["socketPath"] as? String,
                   let url = URL(string: socketPath) {
                    let session = controlSession ?? URLSession(configuration: .default,
                                                              delegate: self, delegateQueue: nil)
                    let task = session.webSocketTask(with: url)
                    pointerSocket = task
                    task.resume()
                    readSocket(task, brand: .lg, generation: generation, pointer: true)
                } else {
                    status = "LG paired, but navigation is unavailable on this TV."
                }
            } else if type == "error" {
                let message = (dict["error"] as? String) ?? "TV rejected a remote request."
                status = message
            }
        }
    }

    private func requestLG(_ uri: String, id: String? = nil, payload: [String: Any] = [:]) {
        lgRequestID += 1
        sendJSON(["type": "request", "id": id ?? "req-\(lgRequestID)",
                  "uri": uri, "payload": payload], socket: controlSocket)
    }

    private func sendJSON(_ object: [String: Any], socket: URLSessionWebSocketTask?) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(json)) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.alertText = "Remote command failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // Only a local TV IP provided by the user can receive this certificate
    // exception. Samsung and LG TVs often use self-signed local certificates.
    nonisolated func urlSession(_ session: URLSession,
          didReceive challenge: URLAuthenticationChallenge,
          completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let host = challenge.protectionSpace.host
        let components = host.split(separator: ".")
        guard components.count == 4,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    /// Sends a one-time text entry command to an already focused text field
    /// on the television. Called only from the on-demand Keyboard sheet.
    /// Does not expose text to logs, preferences, or external services.
    func typeOnTV(_ text: String) {
        guard connected, activeBrand == brand, !activeHost.isEmpty else {
            alertText = "Connect to a compatible TV first."
            return
        }
        guard !text.isEmpty else { return }
        guard text.count <= 512 else {
            alertText = "Send at most 512 characters at a time."
            return
        }

        switch brand {
        case .cast:
            alertText = "Chromecast's default media receiver cannot accept general text input."
        case .android:
            androidBridge?.sendText(text)
            status = "Sent basic keyboard keys to Android TV; focus a TV text field first."
        case .roku:
            // Roku ECP accepts Lit_ followed by one percent-encoded UTF-8
            // Unicode scalar. Keep requests in order, never launch them all
            // concurrently or the on-screen search text may be scrambled.
            let host = activeHost
            let generation = serial
            Task { @MainActor [weak self] in
                guard let self else { return }
                for char in text {
                    guard self.serial == generation, self.connected else { return }
                    let encoded = String(char).addingPercentEncoding(
                        withAllowedCharacters: .alphanumerics
                    ) ?? ""
                    guard !encoded.isEmpty,
                          let url = URL(string: "http://\(host):8060/keypress/Lit_\(encoded)") else {
                        continue
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 8
                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                            self.alertText = "Roku rejected keyboard entry. Open a TV text field and enable Control by mobile apps."
                            return
                        }
                    } catch {
                        self.alertText = "Roku text entry failed: \(error.localizedDescription)"
                        return
                    }
                }
                self.status = "Text sent to Roku · \(text.count) characters"
            }
        case .samsung:
            // Tizen sends base64 UTF-8 to the active on-screen IME.
            // Not every TV app implements SendInputString.
            let encoded = Data(text.utf8).base64EncodedString()
            sendJSON(["method": "ms.remote.control",
                      "params": ["Cmd": encoded,
                                 "DataOfCmd": "base64",
                                 "TypeOfRemote": "SendInputString"]],
                     socket: controlSocket)
            status = "Text sent to Samsung · requires a focused TV text field"
        case .lg:
            // SSAP's IME is supported only while a TV text input is focused.
            requestLG("ssap://com.webos.service.ime/insertText",
                      payload: ["text": text, "replace": false])
            status = "Text sent to LG · requires a focused TV text field"
        }
    }

    func finishTextEntry() {
        guard connected, activeBrand == brand else { return }
        switch brand {
        case .android:
            androidBridge?.send(.ok)
        case .roku:
            pressRokuEnter()
        case .samsung:
            sendJSON(["method": "ms.remote.control",
                      "params": ["TypeOfRemote": "SendInputEnd"]], socket: controlSocket)
        case .lg:
            requestLG("ssap://com.webos.service.ime/sendEnterKey")
        case .cast:
            break
        }
    }

    private func pressRokuEnter() {
        guard let url = URL(string: "http://\(activeHost):8060/keypress/Enter") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }

    func press(_ command: RemoteCommand, cast: CastController) {
        if brand == .cast {
            guard cast.isConnected else {
                alertText = "Choose a Chromecast using the Cast icon first."
                return
            }
            switch command {
            case .playPause: cast.togglePlay()
            case .rewind: cast.skip(-10)
            case .forward: cast.skip(10)
            case .volumeUp: cast.changeVolume(min(1, cast.remoteVolume + 0.08))
            case .volumeDown: cast.changeVolume(max(0, cast.remoteVolume - 0.08))
            case .mute: cast.toggleRemoteMute()
            default: alertText = "The default Chromecast media receiver supports playback and volume, not television navigation or power keys."
            }
            return
        }
        guard connected, activeBrand == brand, !activeHost.isEmpty else {
            alertText = "Connect to your TV before pressing remote buttons."
            return
        }
        switch brand {
        case .android:
            androidBridge?.send(command)
        case .roku:
            guard let url = URL(string: "http://\(activeHost):8060/keypress/\(command.rokuKey)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
                Task { @MainActor in
                    if let error { self?.alertText = error.localizedDescription }
                    else if (response as? HTTPURLResponse)?.statusCode != 200 {
                        self?.status = "Roku rejected this key. Enable Control by mobile apps in TV settings."
                    }
                }
            }.resume()
        case .samsung:
            sendJSON(["method": "ms.remote.control", "params": [
                "Cmd": "Click", "DataOfCmd": command.samsungKey,
                "Option": "false", "TypeOfRemote": "SendRemoteKey"
            ]], socket: controlSocket)
        case .lg:
            switch command {
            case .volumeUp: requestLG("ssap://audio/volumeUp")
            case .volumeDown: requestLG("ssap://audio/volumeDown")
            case .mute: requestLG("ssap://audio/setMute", payload: ["mute": true])
            case .power: requestLG("ssap://system/turnOff")
            case .channelUp: requestLG("ssap://tv/channelUp")
            case .channelDown: requestLG("ssap://tv/channelDown")
            default:
                guard let pointerSocket else {
                    alertText = "LG pointer control is not connected. Reconnect and approve access on the TV."
                    return
                }
                pointerSocket.send(.string("type:button\nname:\(command.lgKey)\n\n")) { [weak self] error in
                    if let error {
                        Task { @MainActor in self?.alertText = error.localizedDescription }
                    }
                }
            }
        case .cast: break
        }
    }
}
