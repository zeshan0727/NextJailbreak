import SwiftUI
import UIKit
import MobileVLCKit
import Combine

/// libVLC gives Next Cast local MKV/AVI/FLV/WMV playback, without converting
/// or uploading files. Actual support still depends on stream codecs and device.
@MainActor
final class VLCPlayback: ObservableObject {
    let engine = VLCMediaPlayer()
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playing = false
    private var loadedURL: URL?
    private var queuedResumeSeconds: Double?
    private var resumeAttempts = 0

    func attach(_ view: UIView) {
        engine.drawable = view
    }
    func open(_ url: URL) {
        guard loadedURL != url else { return }
        engine.stop()
        loadedURL = url
        engine.media = VLCMedia(url: url)
        currentTime = 0
        duration = 0
        queuedResumeSeconds = nil
        resumeAttempts = 0
    }
    func resumeWhenReady(at seconds: Double) {
        queuedResumeSeconds = seconds.isFinite ? max(0, seconds) : 0
        resumeAttempts = 0
    }
    func play() {
        engine.play()
        playing = true
    }
    func pause() {
        engine.pause()
        playing = false
    }
    func stop() {
        engine.stop()
        playing = false
    }
    func togglePlay() {
        if engine.isPlaying { pause() } else { play() }
    }
    func refresh() {
        let elapsed = Double(engine.time.intValue) / 1000.0
        let total = Double(engine.media?.length.intValue ?? 0) / 1000.0
        if elapsed.isFinite { currentTime = max(0, elapsed) }
        if total.isFinite { duration = max(0, total) }
        if let desired = queuedResumeSeconds, duration > 0 {
            // Seek only after libVLC knows the duration. Some containers do not
            // expose seekability immediately; retry a few times if needed.
            if desired < 1 {
                queuedResumeSeconds = nil
                engine.position = 0
            } else if resumeAttempts < 12 {
                resumeAttempts += 1
                let fraction = Float(max(0, min(0.995, desired / duration)))
                engine.position = fraction
                let actual = Double(engine.time.intValue) / 1000
                if actual.isFinite && abs(actual - desired) < 4 {
                    queuedResumeSeconds = nil
                }
            } else {
                queuedResumeSeconds = nil
            }
        }
        playing = engine.isPlaying
    }
    func seek(to time: Double) {
        guard duration > 0, time.isFinite else { return }
        engine.position = Float(max(0, min(1, time / duration)))
        currentTime = max(0, min(duration, time))
    }
    func skip(_ seconds: Double) { seek(to: currentTime + seconds) }
}

struct VLCVideoSurface: UIViewRepresentable {
    @ObservedObject var player: VLCPlayback
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.attach(view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        player.attach(uiView)
    }
}
