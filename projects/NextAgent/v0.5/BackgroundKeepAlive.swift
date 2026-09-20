import AVFoundation

final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var loopBuffer: AVAudioPCMBuffer?
    private(set) var active = false

    private init() {
        engine.attach(player)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1) else { return }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.0001
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000) else { return }
        buffer.frameLength = 8_000
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) { samples[index] = 0 }
        }
        loopBuffer = buffer
    }

    @discardableResult
    func start() -> Bool {
        if active { return true }
        guard let buffer = loopBuffer else { return false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            try engine.start()
            player.play()
            active = true
            return true
        } catch {
            active = false
            return false
        }
    }

    func stop() {
        guard active else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        active = false
    }
}
