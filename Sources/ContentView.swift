import SwiftUI
import Combine
import UIKit

// MARK: - Models

enum TestColor: String, CaseIterable, Identifiable {
    case red, green, blue, white, black
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        case .white: return .white
        case .black: return .black
        }
    }
    
    var accessibilityName: String {
        rawValue.capitalized
    }
}

// MARK: - ViewModels

final class FPSTestViewModel: ObservableObject {
    @Published var fps: Int = 0
    @Published var errorMessage: String? = nil
    
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    
    init() {
        startDisplayLink()
    }
    
    deinit {
        stopDisplayLink()
    }
    
    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func updateFrame(link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            frameCount = 0
            return
        }
        
        frameCount += 1
        let elapsed = link.timestamp - lastTimestamp
        
        if elapsed >= 1.0 {
            let calculatedFPS = Int(round(Double(frameCount) / elapsed))
            DispatchQueue.main.async {
                self.fps = calculatedFPS
            }
            lastTimestamp = link.timestamp
            frameCount = 0
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @State private var refreshRate: Int = 60
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("Display Quality Checker")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                
                VStack(spacing: 16) {
                    NavigationLink(destination: ColorTestView()) {
                        Text("Color Test")
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(10)
                    }
                    .accessibilityLabel("Start Color Test")
                    
                    NavigationLink(destination: FPSTestView()) {
                        Text("FPS Test")
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(10)
                    }
                    .accessibilityLabel("Start FPS Test")
                }
                .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 8) {
                    Text("Device Refresh Rate")
                        .font(.headline)
                    Text("\(refreshRate) Hz")
                        .font(.title)
                        .bold()
                        .accessibilityLabel("Device refresh rate is \(refreshRate) Hertz")
                }
                .padding()
            }
            .padding()
            .onAppear {
                refreshRate = Int(UIScreen.main.maximumFramesPerSecond)
            }
        }
    }
}

struct ColorTestView: View {
    @State private var currentIndex: Int = 0
    private let colors = TestColor.allCases
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                colors[currentIndex].color
                    .ignoresSafeArea()
                    .accessibilityLabel(colors[currentIndex].accessibilityName)
                    .accessibilityAddTraits(.isImage)
                
                Text(colors[currentIndex].accessibilityName)
                    .font(.largeTitle.bold())
                    .foregroundColor(colors[currentIndex] == .black ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.25))
                    .accessibilityHidden(true)
            }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.width < 0 {
                            // Swipe left: next color
                            withAnimation {
                                currentIndex = (currentIndex + 1) % colors.count
                            }
                        } else if value.translation.width > 0 {
                            // Swipe right: previous color
                            withAnimation {
                                currentIndex = (currentIndex - 1 + colors.count) % colors.count
                            }
                        }
                    }
            )
        }
        .navigationTitle("Color Test")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FPSTestView: View {
    @StateObject private var viewModel = FPSTestViewModel()
    @State private var rotationAngle: Double = 0
    @State private var voiceOverTimer: Timer? = nil
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                    .accessibilityLabel("Error: \(error)")
            } else {
                RotatingShape()
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(rotationAngle))
                    .accessibilityHidden(true)
                    .onAppear {
                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    }
                
                Text("FPS: \(viewModel.fps)")
                    .font(.largeTitle.bold())
                    .accessibilityLabel("Frames per second is \(viewModel.fps)")
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("FPS Test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startVoiceOverAnnouncements()
        }
        .onDisappear {
            stopVoiceOverAnnouncements()
        }
    }
    
    private func startVoiceOverAnnouncements() {
        voiceOverTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            let announcement = "Current frames per second is \(viewModel.fps)"
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }
    
    private func stopVoiceOverAnnouncements() {
        voiceOverTimer?.invalidate()
        voiceOverTimer = nil
    }
}

struct RotatingShape: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 25)
            .fill(LinearGradient(
                colors: [.blue, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing))
            .shadow(radius: 10)
    }
}
