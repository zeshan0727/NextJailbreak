import SwiftUI
import UniformTypeIdentifiers

/// Manage immutable successful GitHub Actions builds. Modifications run on new
/// isolated branches; a known-good IPA and source commit are always preserved.
struct MyAppsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingPaste = false
    @State private var pastedLog = ""
    @State private var showingFilePicker = false
    @State private var showReferenceLog = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose a successful AppForge build, restore its exact Swift source, and request changes without touching the working IPA.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        Task { await state.refreshSuccessfulApps() }
                    } label: {
                        Label("Refresh successful builds", systemImage: "arrow.clockwise")
                    }
                    .disabled(state.appsLoading || state.loadingSelectedApp)
                    if state.appsLoading {
                        ProgressView("Finding successful GitHub builds…")
                    }
                    if let error = state.appsError {
                        Text(error).foregroundStyle(.red).font(.footnote)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("My Apps")
                } footer: {
                    Text("Lists the latest successful build on each AppForge branch from recent GitHub Actions history. Failed builds are excluded.")
                }

                if let origin = state.selectedOrigin, let current = state.project {
                    Section("Selected successful build") {
                        LabeledContent("App", value: current.appName)
                        LabeledContent("Original branch", value: origin.branch)
                        LabeledContent("Passing commit", value: String(origin.successfulCommit.prefix(12)))
                        LabeledContent("Swift files", value: String(current.files.filter {
                            $0.path.hasSuffix(".swift") && $0.path != "Sources/AppEntry.swift"
                        }.count))
                        Label("The successful build is read-only. New edits use another appforge/ branch.",
                              systemImage: "checkmark.shield.fill")
                            .font(.footnote).foregroundStyle(.green)
                        HStack {
                            Button {
                                state.selectedTab = .code
                            } label: {
                                Label("Review Code", systemImage: "curlybraces")
                            }
                            Spacer()
                            Button {
                                state.moreSection = .support
                            } label: {
                                Label("Give AI a Command", systemImage: "bubble.left.and.text.bubble.right")
                            }
                        }.buttonStyle(.borderless)
                    }
                    Section("Connect diagnostics") {
                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Attach .ips / .crash / .txt log", systemImage: "doc.badge.plus")
                        }
                        DisclosureGroup(isExpanded: $showingPaste) {
                            TextEditor(text: $pastedLog)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(height: 135)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.25)))
                            Button("Attach Pasted Log") {
                                state.attachDeviceLog(pastedLog)
                                showingPaste = false
                            }.disabled(pastedLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } label: {
                            Label("Paste a device or application log", systemImage: "text.alignleft")
                        }
                        NavigationLink(destination: DiagnosticsView()) {
                            Label("iOS Crash Diagnostics and Privacy Repair", systemImage: "stethoscope")
                        }
                        if !state.userDiagnosticLog.isEmpty {
                            Label("Device log attached to AI Support", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.caption)
                        }
                        DisclosureGroup(isExpanded: $showReferenceLog) {
                            if state.referenceBuildLog.isEmpty {
                                Text("No build log was returned. You can still edit the successful source.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                ScrollView([.horizontal, .vertical]) {
                                    Text(state.referenceBuildLog)
                                        .font(.system(size: 10, design: .monospaced))
                                        .textSelection(.enabled)
                                }.frame(height: 170)
                            }
                        } label: {
                            Label("View Successful GitHub Build Log", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }

                Section("Successful apps") {
                    if state.successfulApps.isEmpty && !state.appsLoading {
                        Text("No successful builds loaded. Tap Refresh to search the repository.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(state.successfulApps) { run in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(displayName(run)).font(.headline)
                                Spacer()
                                Text("#\(run.run_number ?? run.id)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(run.head_branch ?? "Unknown branch")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            HStack {
                                Text(String(run.head_sha.prefix(12)))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let url = URL(string: run.html_url) {
                                    Link("GitHub log", destination: url).font(.caption)
                                }
                                Button {
                                    Task { await state.loadSuccessfulApp(run) }
                                } label: {
                                    if state.loadingSelectedApp {
                                        ProgressView()
                                    } else {
                                        Label("Open for Editing", systemImage: "square.and.pencil")
                                    }
                                }
                                .disabled(state.loadingSelectedApp || state.busyPush)
                                .buttonStyle(.borderedProminent)
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("My Apps")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await state.refreshSuccessfulApps() }
            .task {
                if state.successfulApps.isEmpty {
                    await state.refreshSuccessfulApps()
                }
            }
            .fileImporter(isPresented: $showingFilePicker,
                          allowedContentTypes: [.data, .plainText, .json, .content]) { outcome in
                do {
                    let url = try outcome.get()
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 3_000_000,
                          let contents = String(data: data, encoding: .utf8) else {
                        throw ForgeError.message("Log must be UTF-8 text, smaller than 3 MB.")
                    }
                    if url.pathExtension.lowercased() == "ips" ||
                       url.pathExtension.lowercased() == "crash" {
                        let sanitized = try CrashDoctor.analyze(contents)
                        state.attachDeviceLog(sanitized.safeReport)
                        state.loadCrashReport(contents)
                    } else {
                        state.attachDeviceLog(contents)
                    }
                } catch {
                    state.appsError = "Cannot import log: \(error.localizedDescription)"
                }
            }
        }
    }

    private func displayName(_ run: GitHubRun) -> String {
        let branch = run.head_branch ?? "AppForge app"
        let name = branch.replacingOccurrences(of: "appforge/", with: "")
        guard let last = name.lastIndex(of: "-") else { return name }
        return String(name[..<last]).replacingOccurrences(of: "-", with: " ").capitalized
    }
}
