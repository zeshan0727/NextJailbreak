import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("counterValue") private var counter: Int = 0

    var body: some View {
        VStack(spacing: 40) {
            Text("\(counter)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Current count")
                .accessibilityValue("\(counter)")

            HStack(spacing: 30) {
                Button(action: decrement) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 50))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(counter == 0)
                .accessibilityLabel("Decrement")
                .accessibilityHint("Decreases the counter by one")
                .buttonStyle(.borderedProminent)

                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 50))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Reset")
                .accessibilityHint("Resets the counter to zero")
                .buttonStyle(.borderedProminent)

                Button(action: increment) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 50))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Increment")
                .accessibilityHint("Increases the counter by one")
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            // No additional setup needed as @AppStorage handles persistence
        }
    }

    private func increment() {
        counter += 1
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    private func decrement() {
        if counter > 0 {
            counter -= 1
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        }
    }

    private func reset() {
        counter = 0
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
}
