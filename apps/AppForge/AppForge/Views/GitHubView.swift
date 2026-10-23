import SwiftUI

struct GitHubView: View {
    @EnvironmentObject private var state: AppState
    @State private var newRepoName = ""
    @State private var newRepoPrivate = false
    @State private var showNewRepo = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScreenHeading(title: "GitHub Push", subtitle: "Commit the project and start an automated iOS build.")
                }
                Section("Repository owner") {
                    TextField("GitHub username", text: $state.preferences.githubUsername)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        Button("Load repositories") { Task { await state.refreshRepos() } }
                        Spacer()
                        Button { showNewRepo = true } label: { Label("Create repo", systemImage: "plus") }
                    }
                }
                Section("Repository") {
                    if !state.repositories.isEmpty {
                        Picker("Choose repository", selection: $state.chosenRepo) {
                            ForEach(state.repositories) { repo in
                                Text(repo.name).tag(repo.name)
                            }
                        }
                    }
                    TextField("Repository name", text: $state.chosenRepo)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    LabeledContent("Branch policy", value: "Isolated per app")
                    if state.chosenBranch.hasPrefix("appforge/"),
                       state.lastRepo == state.chosenRepo,
                       state.lastOwner == state.preferences.githubUsername,
                       !state.lastCommitSHA.isEmpty {
                        Text(state.chosenBranch)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                        Label("Rebuilds and AI repairs use only this app's branch.", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("AppForge will create a new unique branch like appforge/notes-8f3c21a2d491.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Main, master, and other projects' branches are never selected or modified. Each new generated app gets its own branch from this repository's default branch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Commit") {
                    TextField("Commit message", text: $state.commitMessage)
                    if let project = state.project {
                        LabeledContent("Application", value: project.appName)
                        LabeledContent("Files", value: "\(project.files.count)")
                    } else {
                        Text("Generate app source in Code first").foregroundStyle(.secondary)
                    }
                    ForgeButton(title: "Push & Build", symbol: "shippingbox", loading: state.busyPush) {
                        Task { await state.pushAndBuild() }
                    }.disabled(state.project == nil)
                }
                Section {
                    Text("GitHub Actions on public repositories can use standard runners without metered minutes. Your provider may enforce rate limits. Pushing code to a public repo makes the generated source public.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .task { if state.repositories.isEmpty && !Keychain.read("github").isEmpty { await state.refreshRepos() } }
            .alert("Create repository", isPresented: $showNewRepo) {
                TextField("Repository name", text: $newRepoName)
                Button("Public") {
                    newRepoPrivate = false
                    Task { await state.createRepo(name: newRepoName, isPrivate: false) }
                }
                Button("Private") {
                    newRepoPrivate = true
                    Task { await state.createRepo(name: newRepoName, isPrivate: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Public repos support free standard Actions builds. Private repo builds consume your included Actions minutes.")
            }
        }
    }
}
