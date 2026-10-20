import SwiftUI

@main
struct GeneratedAppApp: App {
    var body: some Scene {
        WindowGroup {
            CounterView()
        }
    }
}

private struct CounterView: View {
    @AppStorage("factoryCounterValue") private var count: Int = 0

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 16)

                VStack(spacing: 8) {
                    Text("Factory Counter")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text("Your count")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(count.formatted())
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    .accessibilityLabel("Counter value")
                    .accessibilityValue(count.formatted())

                VStack(spacing: 12) {
                    Button {
                        if count < Int.max { count += 1 }
                    } label: {
                        Label("Increase", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(count == Int.max)

                    Button {
                        if count > Int.min { count -= 1 }
                    } label: {
                        Label("Decrease", systemImage: "minus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(count == Int.min)

                    Button("Reset") {
                        count = 0
                    }
                    .font(.headline)
                    .padding(.top, 8)
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
}
