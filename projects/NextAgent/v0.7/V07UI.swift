import SwiftUI

struct ModernAutomationsView: View {
    @EnvironmentObject var state: AppState
    @State private var automationName = ""
    @State private var items: [[String: Any]] = []
    @State private var recordingName: String?
    @State private var refreshToken = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automations")
                                .font(.system(size: 33, weight: .bold, design: .rounded))
                            Text("Record once. Run again.")
                                .foregroundStyle(NATheme.secondary)
                        }
                        Spacer()
                        NANextMark(size: 43)
                    }

                    NAGlassCard {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill((recordingName == nil ? NATheme.cyan : NATheme.pink).opacity(0.14))
                                    Image(systemName: recordingName == nil ? "record.circle" : "record.circle.fill")
                                        .foregroundStyle(recordingName == nil ? NATheme.cyan : NATheme.pink)
                                }
                                .frame(width: 42, height: 42)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(recordingName == nil ? "Automation Recorder" : "Recording")
                                        .font(.headline)
                                    Text(recordingName ?? "Records Next Agent UI-control actions")
                                        .font(.caption)
                                        .foregroundStyle(NATheme.secondary)
                                }
                                Spacer()
                            }

                            if recordingName == nil {
                                HStack {
                                    TextField("Automation name", text: $automationName)
                                        .textInputAutocapitalization(.words)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                                    Button("Start") {
                                        let clean = automationName.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !clean.isEmpty else { return }
                                        state.input = "Start recording a saved automation named \(clean)."
                                        Task {
                                            await state.send()
                                            refresh()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(NATheme.blue)
                                }
                            } else {
                                HStack {
                                    Button("Stop & Save") {
                                        state.input = "Stop the current automation recording and save it."
                                        Task {
                                            await state.send()
                                            refresh()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(NATheme.blue)

                                    Button("Cancel") {
                                        state.input = "Cancel the current automation recording without saving it."
                                        Task {
                                            await state.send()
                                            refresh()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(NATheme.pink)
                                }
                            }
                        }
                    }

                    HStack {
                        Text("SAVED FLOWS")
                            .font(.caption2.weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(NATheme.secondary)
                        Spacer()
                        Button {
                            refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(NATheme.cyan)
                        }
                        .buttonStyle(.plain)
                    }

                    if items.isEmpty {
                        NAGlassCard {
                            VStack(spacing: 12) {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                    .font(.system(size: 34))
                                    .foregroundStyle(NATheme.cyan)
                                Text("No saved automations")
                                    .font(.headline)
                                Text("Start the recorder, then ask Next Agent to open apps, tap, swipe or type. Stop recording when the flow is complete.")
                                    .font(.caption)
                                    .foregroundStyle(NATheme.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                automationRow(item)
                            }
                        }
                    }

                    NAGlassCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("Background-safe replay", systemImage: "infinity")
                                .font(.headline)
                                .foregroundStyle(NATheme.cyan)
                            Text("Saved flows execute locally step-by-step, so opening another app does not require an Astra round-trip after every interaction.")
                                .font(.caption)
                                .foregroundStyle(NATheme.secondary)
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(Color.clear)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { refresh() }
        }
    }

    private func automationRow(_ item: [String: Any]) -> some View {
        let name = item["name"] as? String ?? "Unnamed"
        let count = (item["step_count"] as? NSNumber)?.intValue ?? 0

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NATheme.violet.opacity(0.14))
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(NATheme.violet)
            }
            .frame(width: 43, height: 43)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text("\(count) steps")
                    .font(.caption)
                    .foregroundStyle(NATheme.secondary)
            }

            Spacer()

            Button {
                state.input = "Run my saved automation named \(name)."
                Task { await state.send() }
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 34, height: 34)
                    .background(NATheme.cyan.opacity(0.12), in: Circle())
                    .foregroundStyle(NATheme.cyan)
            }
            .buttonStyle(.plain)

            Button {
                state.input = "Delete my saved automation named \(name)."
                Task {
                    await state.send()
                    refresh()
                }
            } label: {
                Image(systemName: "trash")
                    .frame(width: 34, height: 34)
                    .background(NATheme.pink.opacity(0.10), in: Circle())
                    .foregroundStyle(NATheme.pink)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(NATheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NATheme.stroke))
    }

    private func refresh() {
        items = AutomationRecorder.shared.list()
        recordingName = AutomationRecorder.shared.currentRecordingName
        refreshToken = UUID()
    }
}
