import SwiftUI

struct FactoryCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.indigo.opacity(0.09)))
    }
}
struct FactoryLabel: View {
    let value: String
    var body: some View { Text(value).font(.footnote.weight(.medium)).foregroundStyle(.secondary) }
}
struct NextFactoryHome: View {
    @EnvironmentObject var factory: LocalFactoryState
    @State private var activeResult: AgentTaskRow?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FactoryCard {
                        HStack(spacing: 12) {
                            Image(systemName: "cpu.fill").font(.largeTitle).foregroundStyle(.indigo)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Next IPA Factory").font(.title2.bold())
                                Text("iPhone → OpenAI agents → GitHub").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Your app request", systemImage: "sparkles").font(.headline)
                            TextEditor(text: $factory.prompt)
                                .frame(minHeight: 150)
                                .scrollContentBackground(.hidden)
                                .padding(5)
                                .background(Color.indigo.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                            HStack {
                                Text("Agents").font(.subheadline)
                                Spacer()
                                Picker("Agent count", selection: $factory.selectedAgentCount) {
                                    ForEach([4, 6, 8], id: \.self) { Text(String($0)).tag($0) }
                                }.pickerStyle(.segmented).frame(width: 185)
                            }
                            Button {
                                Task { await factory.runCommand() }
                            } label: {
                                Label(factory.busy ? "Agents working…" : "Send command to agents", systemImage: "bolt.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                            .disabled(factory.busy || factory.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("Status", systemImage: "list.bullet.rectangle").font(.headline)
                            Text(factory.logs)
                                .font(.footnote).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    if !factory.tasks.isEmpty {
                        Text("Agent execution").font(.headline).padding(.horizontal, 4)
                        ForEach(factory.tasks) { result in
                            FactoryCard {
                                Button {
                                    activeResult = result
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: result.status == "Completed" ? "checkmark.circle.fill" : result.status == "Failed" ? "xmark.circle.fill" : "circle.dotted")
                                            .foregroundStyle(result.status == "Completed" ? Color.green : result.status == "Failed" ? Color.red : Color.indigo)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(result.role).font(.subheadline.bold()).foregroundStyle(.primary)
                                            Text(result.status + (result.output.isEmpty ? "" : " — Tap to inspect"))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(16)
            }
            .background(Color(red: 0.962, green: 0.967, blue: 0.988))
            .navigationTitle("Factory")
            .sheet(item: $activeResult) { result in
                NavigationStack {
                    ScrollView {
                        Text(result.output.isEmpty ? "No output yet." : result.output)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }.navigationTitle(result.role)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: result.output) { Image(systemName: "square.and.arrow.up") }
                        }}
                }
            }
        }
    }
}

struct NextFactoryConnections: View {
    @EnvironmentObject var factory: LocalFactoryState
    @State private var showOpenAI = false
    @State private var showGitHub = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("OpenAI — direct connection", systemImage: "brain.head.profile").font(.headline)
                            Text("No server URL. Your own OpenAI API key is stored only in this device's Keychain.")
                                .font(.caption).foregroundStyle(.secondary)
                            Group {
                                if showOpenAI {
                                    TextField("sk-…", text: $factory.openaiKey)
                                } else {
                                    SecureField("OpenAI API key", text: $factory.openaiKey)
                                }
                            }
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            Toggle("Show OpenAI key", isOn: $showOpenAI).font(.caption)
                            HStack {
                                Button("Save credentials") { factory.saveSettings() }
                                    .buttonStyle(.borderedProminent).tint(.indigo)
                                Button("Test first agent") { Task { await factory.verify() } }
                                    .disabled(factory.busy)
                            }
                        }
                    }
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                Label("Eight saved agent IDs", systemImage: "person.3.fill").font(.headline)
                                Spacer()
                                Text("Stored on iPhone").font(.caption2).foregroundStyle(.secondary)
                            }
                            ForEach(FactoryRoles.all) { role in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(String(role.id + 1) + ". " + role.name).font(.subheadline.weight(.semibold))
                                        Spacer()
                                        if !(factory.agentIDs[role.name] ?? "").isEmpty {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        }
                                    }
                                    TextField("agent_...", text: Binding(
                                        get: { factory.agentIDs[role.name] ?? "" },
                                        set: { factory.agentIDs[role.name] = $0 }
                                    ))
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .font(.footnote.monospaced()).textFieldStyle(.roundedBorder)
                                }
                                if role.id != 7 { Divider() }
                            }
                            Button {
                                factory.saveSettings()
                            } label: {
                                Label("Save all 8 IDs locally", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent).tint(.indigo)
                        }
                    }
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 11) {
                            Label("GitHub — cloud compiler", systemImage: "hammer.fill").font(.headline)
                            Text("Fine-grained token for your selected repository. This token is stored only in Keychain.")
                                .font(.caption).foregroundStyle(.secondary)
                            Group {
                                if showGitHub {
                                    TextField("github_pat_…", text: $factory.githubToken)
                                } else {
                                    SecureField("GitHub access token", text: $factory.githubToken)
                                }
                            }
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            Toggle("Show GitHub token", isOn: $showGitHub).font(.caption)
                            FactoryLabel(value: "Repository (owner/name)")
                            TextField("owner/repository", text: $factory.repo)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            FactoryLabel(value: "Build branch")
                            TextField("branch", text: $factory.branch)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            FactoryLabel(value: "Workflow filename")
                            TextField("build-next-ipa-factory.yml", text: $factory.workflow)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Button("Save") { factory.saveSettings() }
                                    .buttonStyle(.borderedProminent).tint(.indigo)
                                Button("Test GitHub") { Task { await factory.checkGithub() } }
                                    .disabled(factory.busy)
                            }
                        }
                    }
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Security", systemImage: "lock.shield").font(.headline)
                            Text("No Windows PC, tunnel, local server, or hard-coded secret is needed. OpenAI API calls require internet and API billing. Github Actions provides macOS compilation.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Agents cannot modify your repository without using an explicitly authorized GitHub action. Agent-written code is not automatically a verified IPA.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Connection status").font(.headline)
                            Text(factory.logs).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }.padding(16)
            }
            .navigationTitle("Connections")
            .background(Color(red: 0.962, green: 0.967, blue: 0.988))
        }
    }
}

struct NextFactoryBuilds: View {
    @EnvironmentObject var factory: LocalFactoryState
    @Environment(\.openURL) private var openURL
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("GitHub Actions build", systemImage: "hammer.fill").font(.headline)
                            Text("Run Xcode on GitHub's macOS runner, not your iPhone or Windows PC.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(factory.repo + "\n" + factory.branch)
                                .font(.caption.monospaced()).textSelection(.enabled)
                            HStack(spacing: 10) {
                                Button("Start Build") { Task { await factory.build() } }
                                    .buttonStyle(.borderedProminent).tint(.indigo)
                                    .disabled(factory.busy)
                                Button("Refresh") { Task { await factory.refreshBuild() } }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    if let run = factory.latestBuild {
                        FactoryCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Latest build").font(.headline)
                                Text("Run #" + String(run.id))
                                Text("Status: " + run.status)
                                Text("Conclusion: " + (run.conclusion ?? "Pending"))
                                Button("Open artifacts in GitHub") {
                                    if let url = URL(string: run.html_url) { openURL(url) }
                                }.buttonStyle(.borderedProminent).tint(.indigo)
                            }.font(.subheadline)
                        }
                    }
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("Current capabilities", systemImage: "checklist").font(.headline)
                            Text("The iPhone can contact saved OpenAI agents, coordinate tasks, inspect responses, and trigger the configured GitHub Xcode workflow.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text("Automatic collection of agent-generated source, commits, tests, and final IPA download are the next integration milestone. A GitHub success result verifies compilation only for the workflow's actual source tree.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Text(factory.logs).font(.caption).foregroundStyle(.secondary).padding()
                }.padding(16)
            }
            .navigationTitle("Builds")
            .background(Color(red: 0.962, green: 0.967, blue: 0.988))
        }.task { await factory.refreshBuild() }
    }
}

struct NextFactoryOnDeviceRoot: View {
    @StateObject private var factory = LocalFactoryState()
    var body: some View {
        TabView {
            NextFactoryHome().tabItem { Label("Agents", systemImage: "cpu") }
            FactoryCodeDeliveryView().tabItem { Label("Generate", systemImage: "wand.and.stars") }
            NextFactoryBuilds().tabItem { Label("Builds", systemImage: "hammer") }
            NextFactoryConnections().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environmentObject(factory)
        .tint(.indigo)
    }
}
