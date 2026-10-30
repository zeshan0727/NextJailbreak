import Foundation
import Security
import AndroidTVRemoteControl

/// Android TV / Google TV Remote v2 over TLS: pairing uses port 6467;
/// authenticated remote keys use port 6466. Cast media is independent.
final class AndroidTVRemoteBridge {
    var onStatus: ((String) -> Void)?
    var onPairingCodeRequired: (() -> Void)?
    var onConnected: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let pairingManager: PairingManager
    private let remoteManager: RemoteManager
    private let tls: TLSManager
    private var host = ""
    private var didRequestPairing = false
    private var intentionallyDisconnected = false
    private let sendQueue = DispatchQueue(label: "nextcast.androidtv.keys", qos: .userInitiated)

    init() throws {
        let (identity, publicKey) = try AndroidTVClientIdentity.identity()
        let crypto = CryptoManager()
        crypto.clientPublicCertificate = { .Result(publicKey) }
        let tls = TLSManager {
            .Result([[kSecImportItemIdentity as String: identity]] as CFArray)
        }
        tls.secTrustClosure = { trust in
            crypto.serverPublicCertificate = {
                guard let key = SecTrustCopyKey(trust) else { return .Error(.secTrustCopyKeyError) }
                return .Result(key)
            }
        }
        self.tls = tls
        pairingManager = PairingManager(tls, crypto)
        remoteManager = RemoteManager(
            tls,
            CommandNetwork.DeviceInfo("Next Cast", "iPhone", "1.4.2", "uk.zeshanbarvi.nextcast", "1")
        )
        pairingManager.stateChanged = { [weak self] state in
            DispatchQueue.main.async { self?.pairState(state) }
        }
        remoteManager.stateChanged = { [weak self] state in
            DispatchQueue.main.async { self?.remoteState(state) }
        }
    }

    func connect(_ address: String) {
        host = address
        intentionallyDisconnected = false
        didRequestPairing = false
        onConnected?(false)
        let saved = UserDefaults.standard.bool(forKey: "nextcast.androidtv.paired." + address)
        if saved {
            onStatus?("Connecting to Android TV Remote v2…")
            remoteManager.connect(address)
        } else {
            startPairing()
        }
    }

    func startPairing() {
        guard !host.isEmpty else { return }
        didRequestPairing = true
        pairingManager.disconnect()
        onStatus?("Requesting Android TV pairing code…")
        pairingManager.connect(host, "Next Cast", "iPhone")
    }

    func submitCode(_ code: String) {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleaned.count == 6, cleaned.allSatisfy({ $0.isHexDigit }) else {
            onError?("Enter the six-character code shown on your Android TV.")
            return
        }
        onStatus?("Verifying TV pairing code…")
        pairingManager.sendSecret(cleaned)
    }

    func disconnect() {
        intentionallyDisconnected = true
        pairingManager.disconnect()
        remoteManager.disconnect()
        onConnected?(false)
    }

    private func pairState(_ state: PairingManager.PairingState) {
        guard !intentionallyDisconnected else { return }
        switch state {
        case .waitingCode:
            onStatus?("Enter the six-character code displayed on the television.")
            onPairingCodeRequired?()
        case .successPaired:
            UserDefaults.standard.set(true, forKey: "nextcast.androidtv.paired." + host)
            onStatus?("Paired. Connecting Android TV remote…")
            remoteManager.connect(host)
        case .error(let error):
            onConnected?(false)
            onError?("Android TV pairing failed: \(error). Check the TV and Wi-Fi network, then try again.")
        default: break
        }
    }

    private func remoteState(_ state: RemoteManager.RemoteState) {
        guard !intentionallyDisconnected else { return }
        switch state {
        case .paired:
            onConnected?(true)
            onStatus?("Android TV remote paired · navigation enabled")
        case .error(let error):
            onConnected?(false)
            // Some devices require pairing again after changing firmware,
            // clearing TV Remote Service data, or changing certificates.
            if !didRequestPairing {
                UserDefaults.standard.removeObject(forKey: "nextcast.androidtv.paired." + host)
                startPairing()
            } else {
                onError?("Android TV remote connection failed: \(error)")
            }
        default: break
        }
    }

    func send(_ command: RemoteCommand) {
        let key: Key
        switch command {
        case .up: key = .KEYCODE_DPAD_UP
        case .down: key = .KEYCODE_DPAD_DOWN
        case .left: key = .KEYCODE_DPAD_LEFT
        case .right: key = .KEYCODE_DPAD_RIGHT
        case .ok: key = .KEYCODE_DPAD_CENTER
        case .back: key = .KEYCODE_BACK
        case .home: key = .KEYCODE_HOME
        case .playPause: key = .KEYCODE_MEDIA_PLAY_PAUSE
        case .rewind: key = .KEYCODE_MEDIA_REWIND
        case .forward: key = .KEYCODE_MEDIA_FAST_FORWARD
        case .volumeUp: key = .KEYCODE_VOLUME_UP
        case .volumeDown: key = .KEYCODE_VOLUME_DOWN
        case .mute: key = .KEYCODE_VOLUME_MUTE
        case .power: key = .KEYCODE_POWER
        case .channelUp: key = .KEYCODE_CHANNEL_UP
        case .channelDown: key = .KEYCODE_CHANNEL_DOWN
        case .info: key = .KEYCODE_INFO
        }
        sendQueue.async { [remoteManager] in
            remoteManager.send(KeyPress(key))
        }
    }

    func sendText(_ text: String) {
        // Basic ASCII keyboard support; Android TV Remote v2 does not expose
        // an unrestricted IME API. Only send key events to a focused TV field.
        sendQueue.async { [remoteManager] in
            for scalar in text.unicodeScalars {
                let v = scalar.value
                let key: Key?
                switch v {
                case 65...90: key = Key(rawValue: UInt(v - 65 + 29))
                case 97...122: key = Key(rawValue: UInt(v - 97 + 29))
                case 48...57: key = Key(rawValue: UInt(v - 48 + 7))
                case 32: key = .KEYCODE_SPACE
                case 46: key = .KEYCODE_PERIOD
                case 44: key = .KEYCODE_COMMA
                case 45: key = .KEYCODE_MINUS
                case 47: key = .KEYCODE_SLASH
                default: key = nil
                }
                if let key { remoteManager.send(KeyPress(key)) }
            }
        }
    }
}
