import SwiftUI

struct BuildView: View {
    @EnvironmentObject private var state: AppState

    private var elapsed: String {
        guard let run = state.activeRun,
              let date = ISO8601DateFormatter().date(from: run.created_at) else { return "—" }
        let sec = max(0, Int(Date().timeIntervalSince(date)))
        return "\(sec / 60)m \(sec % 60)s"
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    ScreenHeading(title: "Build Status", subtitle: "GitHub Actions checks the pushed commit every 8 seconds.")
                    NavigationLink(destination: DiagnosticsView()) {
                        Label("Import .ips Crash Report & Fix", systemImage: "stethoscope")
                    }.buttonStyle(.bordered)
                    if state.lastCommitSHA.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "hammer").font(.largeTitle).foregroundStyle(.secondary)
                            Text("No active build").font(.headline)
                            Text("Push a project from GitHub to begin.").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else {
                        LabeledContent("Repository", value: "\(state.lastOwner)/\(state.lastRepo)")
                        LabeledContent("Commit", value: String(state.lastCommitSHA.prefix(12)))
                        if !state.chosenBranch.isEmpty {
                            LabeledContent("App branch", value: state.chosenBranch)
                        }
                        LabeledContent("Elapsed", value: elapsed)
                        HStack {
                            Label(state.activeRun?.status ?? "Awaiting workflow", systemImage: state.activeRun?.conclusion == "success" ? "checkmark.circle.fill" : state.activeRun?.conclusion == "failure" ? "xmark.circle.fill" : "clock")
                                .font(.title3.bold())
                            Spacer()
                            if state.refreshing { ProgressView() }
                            Button {
                                Task { await state.refreshBuild() }
                            } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh")
                        }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        if let conclusion = state.activeRun?.conclusion {
                            Text("Conclusion: \(conclusion.capitalized)")
                                .foregroundStyle(conclusion == "success" ? Color.green : Color.red)
                        }
                        if !state.repairStatus.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: state.busyFix ? "wand.and.stars" : "wrench.adjustable")
                                Text(state.repairStatus).font(.subheadline).textSelection(.enabled)
                                if state.busyFix { ProgressView() }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        ForEach(state.jobs) { job in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(job.name).font(.headline)
                                    Spacer()
                                    Text(job.conclusion ?? job.status).font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(job.steps ?? []) { step in
                                    HStack(spacing: 10) {
                                        Image(systemName: step.conclusion == "success" ? "checkmark.circle.fill" :
                                            step.conclusion == "failure" ? "xmark.circle.fill" : "circle.dotted")
                                            .foregroundStyle(step.conclusion == "success" ? .green : .secondary)
                                        Text(step.name).font(.subheadline)
                                        Spacer()
                                        Text(step.conclusion ?? step.status).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13))
                        }
                        if !state.failureLog.isEmpty {
                            HStack {
                                Text("Failure logs").font(.headline)
                                Spacer()
                                Button {
                                    Task { await state.fixWithAI() }
                                } label: { Label("Fix with AI", systemImage: "wand.and.stars") }
                                .disabled(state.busyFix || state.busyPush)
                            }
                            ScrollView([.horizontal, .vertical]) {
                                Text(state.failureLog)
                                    .font(.system(size: 10, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                            }
                            .frame(height: 320).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if state.activeRun?.conclusion == "success" {
                            ForgeButton(title: "Open Downloads", symbol: "arrow.down.circle.fill") {
                                state.selectLastBuildDownloads()
                                state.selectedTab = .downloads
                                Task { await state.refreshReleases() }
                            }
                        }
                    }
                }.padding(.horizontal, 17).padding(.bottom, 30)
            }
            .refreshable { await state.refreshBuild() }
            .navigationTitle("Build")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: state.lastCommitSHA) {
                while !Task.isCancelled && !state.lastCommitSHA.isEmpty {
                    await state.refreshBuild()
                    if state.activeRun?.status == "completed" && !state.isRepairPending { break }
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                }
            }
        }
    }
}
