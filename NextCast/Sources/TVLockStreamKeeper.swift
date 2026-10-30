import Foundation
import AVFoundation
import UIKit

/// Best-effort iOS 16 local Cast HTTP-server background support.
/// An active audio session may allow the app to keep serving local files
/// after a device lock, but suspension, interruptions, and battery policies
/// are controlled by iOS. Never claim this is guaranteed.
@MainActor
final class TVLockStreamKeeper {
    static let preference = "nextcast.keepLocalCastWhileLocked"
    private var player: AVAudioPlayer?
    private var graceTask: UIBackgroundTaskIdentifier = .invalid
    private var casting = false
    private var leavingForeground = false
    private var observer: NSObjectProtocol?

    var enabled: Bool {
        (UserDefaults.standard.object(forKey: Self.preference) as? Bool) ?? true
    }

    func setCasting(_ active: Bool) {
        casting = active
        if !active { stopSession() }
        else if leavingForeground { startSession() }
    }

    func willLeaveForeground() {
        leavingForeground = true
        if casting { startSession() }
    }

    func becameActive() {
        leavingForeground = false
        stopSession()
    }

    func stop() {
        casting = false
        stopSession()
    }

    private func startSession() {
        guard enabled, casting, player?.isPlaying != true else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let loop = try Self.writeQuietLoopIfNeeded()
            let audio = try AVAudioPlayer(contentsOf: loop)
            audio.numberOfLoops = -1
            audio.volume = 0.01
            audio.prepareToPlay()
            guard audio.play() else { return }
            player = audio
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: AVAudioSession.interruptionNotification,
                    object: AVAudioSession.sharedInstance(), queue: .main
                ) { [weak self] notice in
                    guard let typeRaw = notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          let type = AVAudioSession.InterruptionType(rawValue: typeRaw),
                          type == .ended else { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.casting, self.leavingForeground else { return }
                        try? AVAudioSession.sharedInstance().setActive(true)
                        _ = self.player?.play()
                    }
                }
            }
            if graceTask == .invalid {
                graceTask = UIApplication.shared.beginBackgroundTask(
                    withName: "Next Cast local streaming"
                ) { [weak self] in
                    Task { @MainActor [weak self] in self?.endGraceTask() }
                }
            }
        } catch {
            player = nil
        }
    }

    private func endGraceTask() {
        guard graceTask != .invalid else { return }
        let task = graceTask
        graceTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }

    private func stopSession() {
        player?.stop()
        player = nil
        endGraceTask()
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
    }

    /// Quiet 8 kHz PCM WAV (~32 kB) used exclusively for a local
    /// streaming background audio session; never sent to the TV.
    private static func writeQuietLoopIfNeeded() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nextcast-local-stream-loop.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let frames = 16000
        let dataLength = UInt32(frames * 2)
        var buffer = Data()
        buffer.append(contentsOf: "RIFF".utf8)
        buffer.appendLittleEndian(UInt32(36) + dataLength)
        buffer.append(contentsOf: "WAVEfmt ".utf8)
        buffer.appendLittleEndian(UInt32(16))
        buffer.appendLittleEndian(UInt16(1))
        buffer.appendLittleEndian(UInt16(1))
        buffer.appendLittleEndian(UInt32(8000))
        buffer.appendLittleEndian(UInt32(16000))
        buffer.appendLittleEndian(UInt16(2))
        buffer.appendLittleEndian(UInt16(16))
        buffer.append(contentsOf: "data".utf8)
        buffer.appendLittleEndian(dataLength)
        for i in 0..<frames {
            buffer.appendLittleEndian(UInt16(bitPattern: i.isMultiple(of: 2) ? 1 : -1))
        }
        try buffer.write(to: url, options: .atomic)
        return url
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var copy = value.littleEndian
        Swift.withUnsafeBytes(of: &copy) { append(contentsOf: $0) }
    }
}
