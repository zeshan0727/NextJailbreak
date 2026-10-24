import SwiftUI

/// User-controlled repair chat. Answers use the API configured in AppForge Settings.
struct SupportView: View {
    @EnvironmentObject private var state: AppState
    @State private var draft = ""
    @State private var showConfirm = false
    @State private var editMode: SupportEditMode = .modify

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("AI Support", systemImage: "bubble.left.and.wrench.bubble.right")
                            .font(.title2.bold())
                        Spacer()
                        if state.supportBusy || state.busyFix { ProgressView() }
                    }
                    Text("Modify, fix or regenerate the selected app using your configured AI API. This is not your ChatGPT conversation.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let project = state.project {
                        Text("Current project: \(project.appName) (\(project.bundleId))")
                            .font(.caption.bold()).lineLimit(2)
                        if let origin = state.selectedOrigin {
                            Label("Working from successful run #\(origin.runID)", systemImage: "checkmark.shield")
                                .font(.caption).foregroundStyle(.green)
                        }
                    } else {
                        Label("Generate or restore app code in the Code tab first.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Button("Analyze build errors") {
                            Task { await state.askSupport("Analyze the latest failed compilation and explain the smallest safe correction.") }
                        }.disabled(state.supportBusy || state.lastCommitSHA.isEmpty)
                        Spacer()
                        Button("Clear chat", role: .destructive) { state.supportMessages = [] }
                            .disabled(state.supportBusy)
                    }.font(.caption)
                }
                .padding(14)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if state.supportMessages.isEmpty {
                                Text("Describe an issue such as ‘Vault build fails at line 564’ or ‘the notes screen freezes’. AppForge includes the selected app's source and compiler diagnostics automatically.")
                                    .foregroundStyle(.secondary).padding(.vertical, 22)
                            }
                            ForEach(state.supportMessages) { message in
                                HStack {
                                    if message.role == "user" { Spacer(minLength: 24) }
                                    Text(message.content)
                                        .textSelection(.enabled)
                                        .font(.subheadline)
                                        .padding(12)
                                        .background(message.role == "user" ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1),
                                                    in: RoundedRectangle(cornerRadius: 14))
                                    if message.role != "user" { Spacer(minLength: 24) }
                                }.id(message.id)
                            }
                            if state.supportBusy {
                                ProgressView("Analyzing source and compiler errors")
                                    .padding(10)
                            }
                        }.padding()
                    }
                    .onChange(of: state.supportMessages.count) { _ in
                        if let id = state.supportMessages.last?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
                Divider()
                if !state.repairStatus.isEmpty {
                    Text(state.repairStatus)
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                HStack(alignment: .bottom) {
                    TextField("Describe the problem…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send() }
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.supportBusy)
                }.padding(12)
                Picker("Action", selection: $editMode) {
                    ForEach(SupportEditMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                Button {
                    showConfirm = true
                } label: {
                    Label("\(editMode.rawValue) & Build New IPA", systemImage: "hammer.circle.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.project == nil || state.supportBusy || state.busyFix || state.busyPush || state.supportMessages.isEmpty)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .navigationTitle("AI Support")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Apply \(editMode.rawValue.lowercased()) and build a new IPA?", isPresented: $showConfirm) {
                Button("\(editMode.rawValue) & Build") { Task { await state.applyAppChange(mode: editMode) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Modify and Repair request localized edits; Regenerate recreates the app's Swift code. A new revision branch protects the selected successful build. AI API usage may be billed.")
            }
        }
    }

    private func send() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        draft = ""
        Task { await state.askSupport(message) }
    }
}
