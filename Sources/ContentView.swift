import SwiftUI
import UserNotifications
import Combine

enum TimerStatus: String {
    case running = "Running"
    case paused = "Paused"
    case completed = "Completed"
    case stopped = "Stopped"
}

struct ContentView: View {
    @AppStorage("timerDuration") private var timerDuration: Int = 25 // default 25 minutes
    @State private var remainingSeconds: Int = 0
    @State private var timerStatus: TimerStatus = .stopped
    @State private var notificationAuthorized: Bool = false
    @State private var showNotificationDeniedMessage: Bool = false
    @State private var timerSubscription: Cancellable?
    @Environment(\.colorScheme) private var colorScheme

    private let minDuration = 1
    private let maxDuration = 120

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(timeString(from: remainingSeconds > 0 ? remainingSeconds : timerDuration * 60))
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel("Timer countdown")
                .accessibilityValue(timerAccessibilityValue())

            if timerStatus == .stopped || timerStatus == .paused || timerStatus == .completed {
                Picker("Timer Duration", selection: $timerDuration) {
                    ForEach(minDuration...maxDuration, id: \.self) { minute in
                        Text("\(minute) min")
                            .tag(minute)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: 150, maxHeight: 150)
                .clipped()
                .accessibilityLabel("Set timer duration")
                .accessibilityValue("\(timerDuration) minutes")
                .disabled(timerStatus == .running)
            }

            HStack(spacing: 40) {
                Button(action: startPauseTapped) {
                    Text(timerStatus == .running ? "Pause" : "Start")
                        .font(.title2.weight(.semibold))
                        .frame(minWidth: 100, minHeight: 44)
                        .background(buttonBackgroundColor())
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(timerDuration == 0 || (timerStatus == .completed && remainingSeconds == 0))
                .accessibilityLabel(timerStatus == .running ? "Pause timer" : "Start timer")

                Button(action: resetTapped) {
                    Text("Reset")
                        .font(.title2.weight(.semibold))
                        .frame(minWidth: 100, minHeight: 44)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                .accessibilityLabel("Reset timer")
            }

            Text(timerStatus.rawValue)
                .font(.headline)
                .accessibilityLabel("Timer status")
                .accessibilityValue(timerStatus.rawValue)

            if showNotificationDeniedMessage {
                VStack(spacing: 8) {
                    Text("Notifications are disabled.")
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Text("Enable notifications in Settings to receive alerts when the timer completes.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
            }

            Spacer()
        }
        .padding()
        .onAppear(perform: onAppear)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            pauseTimerIfRunning()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            checkNotificationAuthorization()
        }
    }

    private func onAppear() {
        remainingSeconds = timerDuration * 60
        checkNotificationAuthorization()
    }

    private func startPauseTapped() {
        switch timerStatus {
        case .running:
            pauseTimer()
        case .paused, .stopped, .completed:
            startTimer()
        }
    }

    private func resetTapped() {
        stopTimer()
        remainingSeconds = timerDuration * 60
        timerStatus = .stopped
        cancelPendingNotifications()
        showNotificationDeniedMessage = !notificationAuthorized
    }

    private func startTimer() {
        guard timerDuration > 0 else { return }

        if timerStatus == .completed {
            remainingSeconds = timerDuration * 60
        }

        timerStatus = .running
        scheduleNotification()

        timerSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                tick()
            }

        provideHapticFeedback(.start)
    }

    private func pauseTimer() {
        timerSubscription?.cancel()
        timerSubscription = nil
        timerStatus = .paused
        cancelPendingNotifications()
        provideHapticFeedback(.pause)
    }

    private func stopTimer() {
        timerSubscription?.cancel()
        timerSubscription = nil
        timerStatus = .stopped
        cancelPendingNotifications()
    }

    private func pauseTimerIfRunning() {
        if timerStatus == .running {
            pauseTimer()
        }
    }

    private func tick() {
        guard remainingSeconds > 0 else {
            timerCompleted()
            return
        }
        remainingSeconds -= 1
    }

    private func timerCompleted() {
        stopTimer()
        timerStatus = .completed
        remainingSeconds = 0
        provideHapticFeedback(.completion)
        // Play alert sound via notification
    }

    private func timeString(from seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func timerAccessibilityValue() -> String {
        let m = (remainingSeconds > 0 ? remainingSeconds : timerDuration * 60) / 60
        let s = (remainingSeconds > 0 ? remainingSeconds : timerDuration * 60) % 60
        return "\(m) minutes and \(s) seconds"
    }

    private func checkNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    notificationAuthorized = true
                    showNotificationDeniedMessage = false
                case .denied:
                    notificationAuthorized = false
                    showNotificationDeniedMessage = true
                case .notDetermined:
                    notificationAuthorized = false
                    showNotificationDeniedMessage = false
                    requestNotificationPermission()
                @unknown default:
                    notificationAuthorized = false
                    showNotificationDeniedMessage = true
                }
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                notificationAuthorized = granted
                showNotificationDeniedMessage = !granted
            }
        }
    }

    private func scheduleNotification() {
        guard notificationAuthorized else { return }
        cancelPendingNotifications()

        let content = UNMutableNotificationContent()
        content.title = "FocusTimer"
        content.body = "Your timer has completed!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(remainingSeconds), repeats: false)
        let request = UNNotificationRequest(identifier: "FocusTimerNotification", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                // Handle error silently
                print("Notification scheduling error: \(error.localizedDescription)")
            }
        }
    }

    private func cancelPendingNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["FocusTimerNotification"])
    }

    private func buttonBackgroundColor() -> Color {
        timerStatus == .running ? Color.red : Color.blue
    }

    private enum HapticType {
        case start, pause, completion
    }

    private func provideHapticFeedback(_ type: HapticType) {
        let generator = UINotificationFeedbackGenerator()
        switch type {
        case .start:
            generator.notificationOccurred(.success)
        case .pause:
            generator.notificationOccurred(.warning)
        case .completion:
            generator.notificationOccurred(.error)
        }
    }
}
